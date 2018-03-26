// Copyright 2012 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// Package types declares the data types and implements
// the algorithms for type-checking of Go packages. Use
// Config.Check to invoke the type checker for a package.
// Alternatively, create a new type checker with NewChecker
// and invoke it incrementally by calling Checker.Files.
//
// Type-checking consists of several interdependent phases:
//
// Name resolution maps each identifier (ast.Ident) in the program to the
// language object (Object) it denotes.
// Use Info.{Defs,Uses,Implicits} for the results of name resolution.
//
// Constant folding computes the exact constant value (constant.Value)
// for every expression (ast.Expr) that is a compile-time constant.
// Use Info.Types[expr].Value for the results of constant folding.
//
// Type inference computes the type (Type) of every expression (ast.Expr)
// and checks for compliance with the language specification.
// Use Info.Types[expr].Type for the results of type inference.
//
// For a tutorial, see https://golang.org/s/types-tutorial.
//
package types

import (
	"bytes"
	"fmt"
	"github.com/glycerine/gi/pkg/ast"
	"github.com/glycerine/gi/pkg/constant"
	"github.com/glycerine/gi/pkg/token"
	pathutil "path"
)

// An Error describes a type-checking error; it implements the error interface.
// A "soft" error is an error that still permits a valid interpretation of a
// package (such as "unused variable"); "hard" errors may lead to unpredictable
// behavior if ignored.
type Error struct {
	Fset *token.FileSet // file set for interpretation of Pos
	Pos  token.Pos      // error position
	Msg  string         // error message
	Soft bool           // if set, error is "soft"
}

// Error returns an error string formatted as follows:
// filename:line:column: message
func (err Error) Error() string {
	return fmt.Sprintf("%s: %s", err.Fset.Position(err.Pos), err.Msg)
}

// An Importer resolves import paths to Packages.
//
// CAUTION: This interface does not support the import of locally
// vendored packages. See https://golang.org/s/go15vendor.
// If possible, external implementations should implement ImporterFrom.
type Importer interface {
	// Import returns the imported package for the given import path.
	// The semantics is like for ImporterFrom.ImportFrom except that
	// dir and mode are ignored (since they are not present).
	Import(path string, depth int) (*Package, error)
}

// ImportMode is reserved for future use.
type ImportMode int

// An ImporterFrom resolves import paths to packages; it
// supports vendoring per https://golang.org/s/go15vendor.
// Use go/importer to obtain an ImporterFrom implementation.
type ImporterFrom interface {
	// Importer is present for backward-compatibility. Calling
	// Import(path, depth) is the same as calling ImportFrom(path, "", 0, depth);
	// i.e., locally vendored packages may not be found.
	// The types package does not call Import if an ImporterFrom
	// is present.
	Importer

	// ImportFrom returns the imported package for the given import
	// path when imported by a package file located in dir.
	// If the import failed, besides returning an error, ImportFrom
	// is encouraged to cache and return a package anyway, if one
	// was created. This will reduce package inconsistencies and
	// follow-on type checker errors due to the missing package.
	// The mode value must be 0; it is reserved for future use.
	// Two calls to ImportFrom with the same path and dir must
	// return the same package.
	ImportFrom(path, dir string, mode ImportMode, depth int) (*Package, error)
}

// A Config specifies the configuration for type checking.
// The zero value for Config is a ready-to-use default configuration.
type Config struct {
	// If IgnoreFuncBodies is set, function bodies are not
	// type-checked.
	IgnoreFuncBodies bool

	// If FakeImportC is set, `import "C"` (for packages requiring Cgo)
	// declares an empty "C" package and errors are omitted for qualified
	// identifiers referring to package C (which won't find an object).
	// This feature is intended for the standard library cmd/api tool.
	//
	// Caution: Effects may be unpredictable due to follow-on errors.
	//          Do not use casually!
	FakeImportC bool

	// If Error != nil, it is called with each error found
	// during type checking; err has dynamic type Error.
	// Secondary errors (for instance, to enumerate all types
	// involved in an invalid recursive type declaration) have
	// error strings that start with a '\t' character.
	// If Error == nil, type-checking stops with the first
	// error found.
	Error func(err error)

	// An importer is used to import packages referred to from
	// import declarations.
	// If the installed importer implements ImporterFrom, the type
	// checker calls ImportFrom instead of Import.
	// The type checker reports an error if an importer is needed
	// but none was installed.
	Importer Importer

	// If Sizes != nil, it provides the sizing functions for package unsafe.
	// Otherwise SizesFor("gc", "amd64") is used instead.
	Sizes Sizes

	// If DisableUnusedImportCheck is set, packages are not checked
	// for unused imports.
	DisableUnusedImportCheck bool

	// AllowImportCaching is critical for source imports --
	// by default now we force all imports to re-compile every
	// time, under the assumption that the user is likely
	// editing the packages at the repl.
	AllowImportCaching bool

	// FullPackage true indicates we are type checking
	// an import, a full package, and can use the
	// traditional whole-package type checking paths rather than
	// the incremental ones.
	FullPackage bool

	// AllowOverShadowedNakedReturns allows the stdlib strconv
	// to compile without getting
	// /usr/local/go/src/strconv/extfloat.go:372:2: result parameter exp10 not in scope at return
	// in frexp10Many()
	/*
		// frexp10Many applies a common shift by a power of ten to a, b, c.
		func frexp10Many(a, b, c *extFloat) (exp10 int) {
			exp10, i := c.frexp10()
			a.Multiply(powersOfTen[i])
			b.Multiply(powersOfTen[i])
			return
		}
	*/
	AllowOverShadowedNakedReturns bool

	AllowUnusedVar bool
}

// Info holds result type information for a type-checked package.
// Only the information for which a map is provided is collected.
// If the package has type errors, the collected information may
// be incomplete.
type Info struct {
	// Types maps expressions to their types, and for constant
	// expressions, also their values. Invalid expressions are
	// omitted.
	//
	// For (possibly parenthesized) identifiers denoting built-in
	// functions, the recorded signatures are call-site specific:
	// if the call result is not a constant, the recorded type is
	// an argument-specific signature. Otherwise, the recorded type
	// is invalid.
	//
	// The Types map does not record the type of every identifier,
	// only those that appear where an arbitrary expression is
	// permitted. For instance, the identifier f in a selector
	// expression x.f is found only in the Selections map, the
	// identifier z in a variable declaration 'var z int' is found
	// only in the Defs map, and identifiers denoting packages in
	// qualified identifiers are collected in the Uses map.
	Types map[ast.Expr]TypeAndValue

	// Defs maps identifiers to the objects they define (including
	// package names, dots "." of dot-imports, and blank "_" identifiers).
	// For identifiers that do not denote objects (e.g., the package name
	// in package clauses, or symbolic variables t in t := x.(type) of
	// type switch headers), the corresponding objects are nil.
	//
	// For an anonymous field, Defs returns the field *Var it defines.
	//
	// Invariant: Defs[id] == nil || Defs[id].Pos() == id.Pos()
	Defs map[*ast.Ident]Object

	// Uses maps identifiers to the objects they denote.
	//
	// For an anonymous field, Uses returns the *TypeName it denotes.
	//
	// Invariant: Uses[id].Pos() != id.Pos()
	Uses map[*ast.Ident]Object

	// Implicits maps nodes to their implicitly declared objects, if any.
	// The following node and object types may appear:
	//
	//     node               declared object
	//
	//     *ast.ImportSpec    *PkgName for imports without renames
	//     *ast.CaseClause    type-specific *Var for each type switch case clause (incl. default)
	//     *ast.Field         anonymous parameter *Var
	//
	Implicits map[ast.Node]Object

	// Selections maps selector expressions (excluding qualified identifiers)
	// to their corresponding selections.
	Selections map[*ast.SelectorExpr]*Selection

	// Scopes maps ast.Nodes to the scopes they define. Package scopes are not
	// associated with a specific node but with all files belonging to a package.
	// Thus, the package scope can be found in the type-checked Package object.
	// Scopes nest, with the Universe scope being the outermost scope, enclosing
	// the package scope, which contains (one or more) files scopes, which enclose
	// function scopes which in turn enclose statement and function literal scopes.
	// Note that even though package-level functions are declared in the package
	// scope, the function scopes are embedded in the file scope of the file
	// containing the function declaration.
	//
	// The following node types may appear in Scopes:
	//
	//     *ast.File
	//     *ast.FuncType
	//     *ast.BlockStmt
	//     *ast.IfStmt
	//     *ast.SwitchStmt
	//     *ast.TypeSwitchStmt
	//     *ast.CaseClause
	//     *ast.CommClause
	//     *ast.ForStmt
	//     *ast.RangeStmt
	//
	Scopes map[ast.Node]*Scope

	// jea add: map name to the Node, to support re-declaration.
	Name2node map[string]*FtypeAndScope

	// InitOrder is the list of package-level initializers in the order in which
	// they must be executed. Initializers referring to variables related by an
	// initialization dependency appear in topological order, the others appear
	// in source order. Variables without an initialization expression do not
	// appear in this list.
	// jea: hurtful to reorder assignments at the repl, don't do it.
	InitOrder []*Initializer

	// standalone statements/expressions, in order
	NewCode []*NewStuff
}

type NewStuff struct {
	Obj    Object
	Scope  *Scope
	Node   ast.Node
	IsExpr bool

	IsPkgScope bool
}

// TypeOf returns the type of expression e, or nil if not found.
// Precondition: the Types, Uses and Defs maps are populated.
//
func (info *Info) TypeOf(e ast.Expr) Type {
	if t, ok := info.Types[e]; ok {
		return t.Type
	}
	if id, _ := e.(*ast.Ident); id != nil {
		if obj := info.ObjectOf(id); obj != nil {
			return obj.Type()
		}
	}
	return nil
}

// ObjectOf returns the object denoted by the specified id,
// or nil if not found.
//
// If id is an anonymous struct field, ObjectOf returns the field (*Var)
// it uses, not the type (*TypeName) it defines.
//
// Precondition: the Uses and Defs maps are populated.
//
func (info *Info) ObjectOf(id *ast.Ident) Object {
	if obj := info.Defs[id]; obj != nil {
		return obj
	}
	return info.Uses[id]
}

// TypeAndValue reports the type and value (for constants)
// of the corresponding expression.
type TypeAndValue struct {
	mode  operandMode
	Type  Type
	Value constant.Value
}

// TODO(gri) Consider eliminating the IsVoid predicate. Instead, report
// "void" values as regular values but with the empty tuple type.

// IsVoid reports whether the corresponding expression
// is a function call without results.
func (tv TypeAndValue) IsVoid() bool {
	return tv.mode == novalue
}

// IsType reports whether the corresponding expression specifies a type.
func (tv TypeAndValue) IsType() bool {
	return tv.mode == typexpr
}

// IsBuiltin reports whether the corresponding expression denotes
// a (possibly parenthesized) built-in function.
func (tv TypeAndValue) IsBuiltin() bool {
	return tv.mode == builtin
}

// IsValue reports whether the corresponding expression is a value.
// Builtins are not considered values. Constant values have a non-
// nil Value.
func (tv TypeAndValue) IsValue() bool {
	switch tv.mode {
	case constant_, variable, mapindex, value, commaok:
		return true
	}
	return false
}

// IsNil reports whether the corresponding expression denotes the
// predeclared value nil.
func (tv TypeAndValue) IsNil() bool {
	return tv.mode == value && tv.Type == Typ[UntypedNil]
}

// Addressable reports whether the corresponding expression
// is addressable (https://golang.org/ref/spec#Address_operators).
func (tv TypeAndValue) Addressable() bool {
	return tv.mode == variable
}

// Assignable reports whether the corresponding expression
// is assignable to (provided a value of the right type).
func (tv TypeAndValue) Assignable() bool {
	return tv.mode == variable || tv.mode == mapindex
}

// HasOk reports whether the corresponding expression may be
// used on the lhs of a comma-ok assignment.
func (tv TypeAndValue) HasOk() bool {
	return tv.mode == commaok || tv.mode == mapindex
}

// An Initializer describes a package-level variable, or a list of variables in case
// of a multi-valued initialization expression, and the corresponding initialization
// expression.
type Initializer struct {
	Lhs []*Var // var Lhs = Rhs
	Rhs ast.Expr
}

func (init *Initializer) String() string {
	var buf bytes.Buffer
	for i, lhs := range init.Lhs {
		if i > 0 {
			buf.WriteString(", ")
		}
		buf.WriteString(lhs.Name())
	}
	buf.WriteString(" = ")
	WriteExpr(&buf, init.Rhs)
	return buf.String()
}

// Check type-checks a package and returns the resulting package object and
// the first error if any. Additionally, if info != nil, Check populates each
// of the non-nil maps in the Info struct.
//
// The package is marked as complete if no errors occurred, otherwise it is
// incomplete. See Config.Error for controlling behavior in the presence of
// errors.
//
// The package is specified by a list of *ast.Files and corresponding
// file set, and the package path the package is identified with.
// The clean path must not be empty or dot (".").
func (conf *Config) Check(pkg *Package, check *Checker, path string, fset *token.FileSet, files []*ast.File, info *Info, addPreludeToNewPkg func(pkg *Package), depth int) (*Package, *Checker, error) {
	// jea: gotta make these incremental, not new every time!
	if pkg == nil {
		// jea, I used to have:
		// pkg = NewPackage(path, "")
		// instead, try:
		name := pathutil.Base(path)
		if path == "" || name == "." {
			name = "main"
		}
		//pp("NewPackage, using path='%s' and name='%s'", path, name)
		pkg = NewPackage(path, name)
		if addPreludeToNewPkg != nil {
			addPreludeToNewPkg(pkg)
		}
	}
	if check == nil {
		check = NewChecker(conf, fset, pkg, info)
	}

	return pkg, check, check.Files(files, depth+1)
}

// AssertableTo reports whether a value of type V can be asserted to have type T.
func AssertableTo(V *Interface, T Type) bool {
	m, _ := assertableTo(V, T)
	return m == nil
}

// AssignableTo reports whether a value of type V is assignable to a variable of type T.
func AssignableTo(V, T Type) bool {
	x := operand{mode: value, typ: V}
	return x.assignableTo(nil, T, nil) // config not needed for non-constant x
}

// ConvertibleTo reports whether a value of type V is convertible to a value of type T.
func ConvertibleTo(V, T Type) bool {
	x := operand{mode: value, typ: V}
	return x.convertibleTo(nil, T) // config not needed for non-constant x
}

// Implements reports whether type V implements interface T.
func Implements(V Type, T *Interface) bool {
	f, _ := MissingMethod(V, T, true)
	return f == nil
}

type FtypeAndScope struct {
	Ftype *ast.FuncType
	Scope *Scope
}
