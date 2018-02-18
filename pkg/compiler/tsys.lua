--
-- tsys.lua the type system for gijit.
-- It started life as a port of the GopherJS type
-- system to LuaJIT, and still shows some
-- javascript vestiges.

-- We would typically assume these dofile imports
-- are already done by prelude loading.
-- For dev work, we'll load them if not already.
--
if __min == nil then
   dofile 'math.lua' -- for __max, __min, __truncateToInt
end
if int8 == nil then
   dofile 'int64.lua' -- for integer types with Go naming.
end
if complex == nil then
   dofile 'complex.lua'
end

-- translation of javascript builtin 'prototype' -> typ.prototype
--                                   'constructor' -> typ.__constructor

__ffi = require("ffi")
__bit = require("bit")

__global ={};
__module ={};
__packages = {}
__idCounter = 0;

function __ipairsZeroCheck(arr)
   if arr[0] ~= nil then error("ipairs will miss the [0] index of this array") end
end

__mod = function(y) return x % y; end;
__parseInt = parseInt;
__parseFloat = function(f)
   if f ~= nil  and  f ~= nil  and  f.constructor == Number then
      return f;
   end
   return parseFloat(f);
end;

-- __fround returns nearest float32
__fround = function(x)
   return float32(x)
end;

--[[
   __imul = Math.imul  or  function(b)
   local ah = __bit.band(__bit.rshift(a, 16), 0xffff);
   local al = __bit.band(a, 0xffff);
   local bh = __bit.band(__bit.rshift(b, 16), 0xffff);
   local bl = __bit.band(b, 0xffff);
   return ((al * bl) + __bit.arshift((__bit.rshift(__bit.lshift(ah * bl + al * bh), 16), 0), 0);
   end;
--]]

__floatKey = function(f)
   if f ~= f then
      __idCounter=__idCounter+1;
      return "NaN__" .. tostring(__idCounter);
   end
   return tostring(f);
end;

__flatten64 = function(x)
   return x.__high * 4294967296 + x.__low;
end;


__Infinity = math.huge

-- returned by __basicValue2kind(v) on unrecognized kind.
__kindUnknown = -1;

__kindBool = 1;
__kindInt = 2;
__kindInt8 = 3;
__kindInt16 = 4;
__kindInt32 = 5;
__kindInt64 = 6;
__kindUint = 7;
__kindUint8 = 8;
__kindUint16 = 9;
__kindUint32 = 10;
__kindUint64 = 11;
__kindUintptr = 12;
__kindFloat32 = 13;
__kindFloat64 = 14;
__kindComplex64 = 15;
__kindComplex128 = 16;
__kindArray = 17;
__kindChan = 18;
__kindFunc = 19;
__kindInterface = 20;
__kindMap = 21;
__kindPtr = 22;
__kindSlice = 23;
__kindString = 24;
__kindStruct = 25;
__kindUnsafePointer = 26;

-- jea: sanity check my assumption by comparing
-- length with #a
function __assertIsArray(a)
   local n = 0
   for k,v in pairs(a) do
      n=n+1
   end
   if #a ~= n then
      error("not an array, __assertIsArray failed")
   end
end


-- length of array, counting [0] if present.
function __lenz(array)      
   local n = #array
   if array[0] ~= nil then
      n=n+1
   end
   return n
end

-- st or showtable, a debug print helper.
-- seen avoids infinite looping on self-recursive types.
function __st(t, name, indent, quiet, methods_desc, seen)
   if t == nil then
      local s = "<nil>"
      if not quiet then
         print(s)
      end
      return s
   end

   seen = seen or {}
   if seen[t] ~= nil then
      return
   end
   seen[t] =true   
   
   if type(t) ~= "table" then
      local s = tostring(t)
      if not quiet then
         if type(t) == "string" then
            print('"'..s..'"')
         else 
            print(s)
         end
      end
      return s
   end   

   -- get address, avoiding infinite loop of self-calls.
   local mt = getmetatable(t)
   setmetatable(t, nil)
   local addr = tostring(t) 
   -- restore the metatable just before returning!
   
   local k = 0
   local name = name or ""
   local namec = name
   if name ~= "" then
      namec = namec .. ": "
   end
   local indent = indent or 0
   local pre = string.rep(" ", 4*indent)..namec
   local s = pre .. "============================ "..addr.."\n"
   for i,v in pairs(t) do
      k=k+1
      local vals = ""
      if methods_desc then
         --print("methods_desc is true")
         --vals = __st(v,"",indent+1,quiet,methods_desc, seen)
      else 
         vals = tostring(v)
      end
      s = s..pre.." "..tostring(k).. " key: '"..tostring(i).."' val: '"..vals.."'\n"
   end
   if k == 0 then
      s = pre.."<empty table>"
   end

   --local mt = getmetatable(t)
   if mt ~= nil then
      s = s .. "\n"..__st(mt, "mt.of."..name, indent+1, true, methods_desc, seen)
   end
   if not quiet then
      print(s)
   end
   -- restore metamethods
   setmetatable(t, mt)
   return s
end


-- apply fun to each element of the array arr,
-- then concatenate them together with splice in
-- between each one. It arr is empty then we
-- return the empty string. arr can start at
-- [0] or [1].
function __mapAndJoinStrings(splice, arr, fun)
   local newarr = {}
   -- handle a zero argument, if present.
   local bump = 0
   local zval = arr[0]
   if zval ~= nil then
      bump = 1
      newarr[1] = fun(zval)
   end
   for i,v in ipairs(arr) do
      newarr[i+bump] = fun(v)
   end
   return table.concat(newarr, splice)
end

-- return sorted keys from table m
__keys = function(m)
   if type(m) ~= "table" then
      return {}
   end
   local r = {}
   for k in pairs(m) do
      local tyk = type(k)
      if tyk == "function" then
         k = tostring(k)
      end
      table.insert(r, k)
   end
   table.sort(r)
   return r
end

--
__flushConsole = function() end;
__throwRuntimeError = function(...) error(...) end
__throwNilPointerError = function()  __throwRuntimeError("invalid memory address or nil pointer dereference"); end;
__call = function(fn, rcvr, args)  return fn(rcvr, args); end;
__makeFunc = function(fn)
   return function()
      -- TODO: port this!
      print("jea TODO: port this, what is __externalize doing???")
      error("NOT DONE: port this!")
      --return __externalize(fn(this, (__sliceType({},__jsObjectPtr))(__global.Array.prototype.slice.call(arguments, {}))), __type__emptyInterface);
   end;
end;
__unused = function(v) end;

--
__mapArray = function(arr, fun)
   local newarr = {}
   -- handle a zero argument, if present.
   local bump = 0
   local zval = arr[0]
   if zval ~= nil then
      bump = 1
      newarr[1] = fun(zval)
   end
   __ipairsZeroCheck(arr)
   for i,v in ipairs(arr) do
      newarr[i+bump] = fun(v)
   end
   return newarr
end;

__methodVal = function(recv, name) 
   local vals = recv.__methodVals  or  {};
   recv.__methodVals = vals; -- /* noop for primitives */
   local f = vals[name];
   if f ~= nil then
      return f;
   end
   local method = recv[name];
   f = function() 
      __stackDepthOffset = __stackDepthOffset-1;
      -- try
      local res = {pcall(function()
                         return recv[method](arguments);
      end)}
      -- finally
      __stackDepthOffset=__stackDepthOffset+1;
      -- no catch, so either re-throw or return results
      local ok, err = unpack(res)
      if not ok then
         -- rethrow
         error(err)
      end
      -- return results (without the ok/not first value)
      return table.remove(res, 1)
   end;
   vals[name] = f;
   return f;
end;

__methodExpr = function(typ, name) 
   local method = typ.prototype[name];
   if method.__expr == nil then
      method.__expr = function() 
         __stackDepthOffset=__stackDepthOffset-1;

         -- try
         local res ={pcall(
                        function()
                           if typ.wrapped then
                              arguments[0] = typ(arguments[0]);
                           end
                           return method(arguments);
         end)}
         local ok, threw = unpack(res)
         -- finally
         __stackDepthOffset=__stackDepthOffset+1;
         -- no catch, so rethrow any exception
         if not ok then
            error(threw)
         end
         return table.remove(res, 1)
      end;
   end
   return method.__expr;
end;

__ifaceMethodExprs = {};
__ifaceMethodExpr = function(name) 
   local expr = __ifaceMethodExprs["_"  ..  name];
   if expr == nil then
      expr = function()
         __stackDepthOffset = __stackDepthOffset-1;
         -- try
         local res = {pcall(
                         function()
                            return Function.call.apply(arguments[0][name], arguments);
         end)}
         -- finally
         __stackDepthOffset = __stackDepthOffset+1;
         -- no catch
         local ok, threw = unpack(res)
         if not ok then
            error(threw)
         else
            -- non-panic return from pcall
            return table.remove(res, 1)
         end   
      end;
      __ifaceMethodExprs["_"  ..  name] = expr
   end
   return expr;
end;

--

__subslice = function(slice, low, high, max)
   if high == nil then
      
   end
   if low < 0  or  (high ~= nil and high < low)  or  (max ~= nil and high ~= nil and max < high)  or  (high ~= nil and high > slice.__capacity)  or  (max ~= nil and max > slice.__capacity) then
      __throwRuntimeError("slice bounds out of range");
   end
   
   local s = {}
   slice.__constructor.tfun(s, slice.__array);
   s.__offset = slice.__offset + low;
   s.__length = slice.__length - low;
   s.__capacity = slice.__capacity - low;
   if high ~= nil then
      s.__length = high - low;
   end
   if max ~= nil then
      s.__capacity = max - low;
   end
   return s;
end;

__copySlice = function(dst, src)
   local n = __min(src.__length, dst.__length);
   __copyArray(dst.__array, src.__array, dst.__offset, src.__offset, n, dst.__constructor.elem);
   return n;
end;

--

__copyArray = function(dst, src, dstOffset, srcOffset, n, elem)
   --print("__copyArray called with n = ", n, " dstOffset=", dstOffset, " srcOffset=", srcOffset)
   --print("__copyArray has dst:")
   --__st(dst)
   --print("__copyArray has src:")
   --__st(src)
   
   n = tonumber(n)
   if n == 0  or  (dst == src  and  dstOffset == srcOffset) then
      --setmetatable(dst, getmetatable(src))
      return;
   end

   local sw = elem.kind
   if sw == __kindArray or sw == __kindStruct then
      
      if dst == src  and  dstOffset > srcOffset then
         for i = n-1,0,-1 do
            elem.copy(dst[dstOffset + i], src[srcOffset + i]);
         end
         --setmetatable(dst, getmetatable(src))         
         return;
      end
      for i = 0,n-1 do
         elem.copy(dst[dstOffset + i], src[srcOffset + i]);
      end
      --setmetatable(dst, getmetatable(src))      
      return;
   end

   if dst == src  and  dstOffset > srcOffset then
      for i = n-1,0,-1 do
         dst[dstOffset + i] = src[srcOffset + i];
      end
      --setmetatable(dst, getmetatable(src))      
      return;
   end
   for i = 0,n-1 do
      dst[dstOffset + i] = src[srcOffset + i];
   end
   --setmetatable(dst, getmetatable(src))   
   --print("at end of array copy, src is:")
   --__st(src)
   --print("at end of array copy, dst is:")
   --__st(dst)
end;

--
__clone = function(src, typ)
   local clone = typ()
   typ.copy(clone, src);
   return clone;
end;

__pointerOfStructConversion = function(obj, typ)
   if(obj.__proxies == nil) then
      obj.__proxies = {};
      obj.__proxies[obj.constructor.__str] = obj;
   end
   local proxy = obj.__proxies[typ.__str];
   if proxy == nil then
      local properties = {};
      
      local helper = function(p)
         properties[fieldProp] = {
            get= function() return obj[fieldProp]; end,
            set= function(value) obj[fieldProp] = value; end
         };
      end
      -- fields must be an array for this to work.
      for i=0,#typ.elem.fields-1 do
         helper(typ.elem.fields[i].__prop);
      end
      
      proxy = Object.create(typ.prototype, properties);
      proxy.__val = proxy;
      obj.__proxies[typ.__str] = proxy;
      proxy.__proxies = obj.__proxies;
   end
   return proxy;
end;

--


__append = function(...)
   local arguments = {...}
   local slice = arguments[1]
   return __internalAppend(slice, arguments, 1, #arguments - 1);
end;

__appendSlice = function(slice, toAppend)
   if slice == nil then 
      error("error calling __appendSlice: slice must be available")
   end
   if toAppend == nil then
      error("error calling __appendSlice: toAppend must be available")      
   end
   if type(toAppend) == "string" then
      local bytes = __stringToBytes(toAppend);
      return __internalAppend(slice, bytes, 0, #bytes);
   end
   return __internalAppend(slice, toAppend.__array, toAppend.__offset, toAppend.__length);
end;

__internalAppend = function(slice, array, offset, length)
   if length == 0 then
      return slice;
   end

   local newArray = slice.__array;
   local newOffset = slice.__offset;
   local newLength = slice.__length + length;
   --print("jea debug: __internalAppend: newLength is "..tostring(newLength))
   local newCapacity = slice.__capacity;
   local elem = slice.__constructor.elem;

   if newLength > newCapacity then
      newOffset = 0;
      local tmpCap
      if slice.__capacity < 1024 then
         tmpCap = slice.__capacity * 2
      else
         tmpCap = __truncateToInt(slice.__capacity * 5 / 4)
      end
      newCapacity = __max(newLength, tmpCap);

      newArray = {}
      local w = slice.__offset
      for i = 0,slice.__length do
         newArray[i] = slice.__array[i + w]
      end
      for i = #slice,newCapacity-1 do
         newArray[i] = elem.zero();
      end
      
   end

   --print("jea debug, __internalAppend, newOffset = ", newOffset, " and slice.__length=", slice.__length)

   __copyArray(newArray, array, newOffset + slice.__length, offset, length, elem);
   --print("jea debug, __internalAppend, after copying over array:")
   --__st(newArray)

   local newSlice ={}
   slice.__constructor.tfun(newSlice, newArray);
   newSlice.__offset = newOffset;
   newSlice.__length = newLength;
   newSlice.__capacity = newCapacity;
   return newSlice;
end;

--

__substring = function(str, low, high)
   if low < 0  or  high < low  or  high > #str then
      __throwRuntimeError("string slice bounds out of range");
   end
   return string.sub(str, low+1, high); -- high is inclusive, so no +1 needed.
end;

__sliceToArray = function(slice)
   local cp = {}
   if slice.__length > 0 then
      local k = 0
      for i = slice.__offset, slice.__offset + slice.__length -1 do
         cp[k] = slice.array[i]
         k=k+1
      end
   end
   cp.__length = k
   return cp
end;

--


--

__valueBasicMT = {
   __name = "__valueBasicMT",
   __tostring = function(self, ...)
      --print("__tostring called from __valueBasicMT")
      if type(self.__val) == "string" then
         return '"'..self.__val..'"'
      end
      if self ~= nil and self.__val ~= nil then
         --print("__valueBasicMT.__tostring called, with self.__val set.")
         if self.__val == self then
            -- not a basic value, but a pointer, array, slice, or struct.
            return "<this.__val == this; avoid inf loop>"
         end
         --return tostring(self.__val)
      end
      if getmetatable(self.__val) == __valueBasicMT then
         --print("avoid infinite loop")
         return "<avoid inf loop>"
      else
         return tostring(self.__val)
      end
   end,
}

-- use for slices and arrays
__valueSliceIpairs = function(t)
   
   --print("__ipairs called!")
   -- this makes a slice work in a for k,v in ipairs() do loop.
   local off = rawget(t, "__offset")
   local slcLen = rawget(t, "__length")
   local function stateless_iter(arr, k)
      k=k+1
      if k >= off + slcLen then
         return
      end
      return k, rawget(arr, off + k)
   end       
   -- Return an iterator function, the table, starting point
   local arr = rawget(t, "__array")
   --print("arr is "..tostring(arr))
   return stateless_iter, arr, -1
end

__valueArrayMT = {
   __name = "__valueArrayMT",

   __ipairs = __valueSliceIpairs,
   __pairs  = __valueSliceIpairs,
   
   __newindex = function(t, k, v)
      print("__valueArrayMT.__newindex called, t is:")
      __st(t)

      if k < 0 or k >= #t then
         error "write to array error: access out-of-bounds"
      end
      
      t.__val[k] = v
   end,
   
   __index = function(t, k, mmm)
      print("__valueArrayMT.__index called, k='"..tostring(k).."'; mmm="..tostring(mmm)) --  t.__val is:")
      if type(k) == "string" then
            return rawget(t,k)
      elseif type(k) == "table" then
         print("callstack:"..tostring(debug.traceback()))
         error("table as key not supported in __valueArrayMT")
      else
         --__st(t.__val)
         if k < 0 or k >= #t then
            print(debug.traceback())
            error("read from array error: access out-of-bounds; "..tostring(k).." is outside [0, "  .. tostring(#t) .. ")")
         end
         
         return t.__val[k]
      end
   end,

   __len = function(t)
      return int(__lenz(t.__val))
   end,
   
   __tostring = function(self, ...)
      print("__tostring called from __valueArrayMT")
      if type(self.__val) == "string" then
         return '"'..self.__val..'"'
      end
      if self ~= nil and self.__val ~= nil then
         --print("__valueArrayMT.__tostring called, with self.__val set.")
         if self.__val == self then
            -- not a basic value, but a pointer, array, slice, or struct.
            return "<this.__val == this; avoid inf loop>"
         end

         local len = #self.__val
         if self.__val[0] ~= nil then
            len=len+1
         end
         local s = self.__constructor.__str.."{"
         local raw = self.__val
         local beg = 0

         local quo = ""
         if len > 0 and type(raw[beg]) == "string" then
            quo = '"'
         end
         for i = 0, len-1 do
            s = s .. "["..tostring(i).."]" .. "= " ..quo.. tostring(raw[beg+i]) .. quo .. ", "
         end
         
         return s .. "}"
      end
      
      if getmetatable(self.__val) == __valueArrayMT then
         --print("avoid infinite loop")
         return "<avoid inf loop>"
      else
         return tostring(self.__val)
      end
   end,
}


__valueSliceMT = {
   __name = "__valueSliceMT",
   
   __newindex = function(t, k, v)
      --print("__valueSliceMT.__newindex called, t is:")
      --__st(t)
      local w = t.__offset + k
      if k < 0 or k >= t.__capacity then
         error "slice error: write out-of-bounds"
      end
      t.__array[w] = v
   end,
   
   __index = function(t, k)
      
      print("__valueSliceMT.__index called, k='"..tostring(k).."'");
      --__st(t.__val)
      --print("callstack:"..tostring(debug.traceback()))

      if type(k) == "string" then
         print("we have string key, doing rawget on t")
         __st(t, "t")
         return rawget(t,k)
      elseif type(k) == "table" then
         print("callstack:"..tostring(debug.traceback()))
         error("table as key not supported in __valueSliceMT")
      else
         local w = t.__offset + k
         if k < 0 or k >= t.__capacity then
            error "slice error: access out-of-bounds"
         end
         return t.__array[w]
      end
   end,

   __len = function(t)
      return t.__length
   end,
   
   __tostring = function(self, ...)
      print("__tostring called from __valueSliceMT")

      local len = self.__length
      local beg = self.__offset
      local cap = self.__capacity
      --local s = "slice <len=" .. tostring(len) .. "; beg=" .. beg .. "; cap=" .. cap ..  "> is "..self.__constructor.__str.."{"
      local s = self.__constructor.__str.."{"
      local raw = self.__array

      -- we want to skip both the _giPrivateRaw and the len
      -- when iterating, which happens automatically if we
      -- iterate on raw, the raw inside private data, and not on the proxy.
      local quo = ""
      if len > 0 and type(raw[beg]) == "string" then
         quo = '"'
      end
      for i = 0, len-1 do
         s = s .. "["..tostring(i).."]" .. "= " ..quo.. tostring(raw[beg+i]) .. quo .. ", "
      end
      
      return s .. "}"
      
   end,
   __pairs = __valueSliceIpairs,
   __ipairs = __valueSliceIpairs,
}


__tfunBasicMT = {
   __name = "__tfunBasicMT",
   __call = function(self, ...)
      --print("jea debug: __tfunBasicMT.__call() invoked") -- , self='"..tostring(self).."' with tfun = ".. tostring(self.tfun).. " and args=")
      --print(debug.traceback())
      
      --print("in __tfunBasicMT, start __st on ...")
      --__st({...}, "__tfunBasicMT.dots")
      --print("in __tfunBasicMT,   end __st on ...")

      --print("in __tfunBasicMT, start __st on self")
      --__st(self, "self")
      --print("in __tfunBasicMT,   end __st on self")

      local newInstance = {}
      if self ~= nil then
         if self.tfun ~= nil then
            --print("calling tfun! -- let constructors set metatables if they wish to. our newInstance is an empty table="..tostring(newInstance))

            -- this makes a difference as to whether or
            -- not the ctor receives a nil 'this' or not...
            -- So *don't* set metatable here, let ctor do it.
            -- setmetatable(newInstance, __valueBasicMT)
            
            -- get zero value if no args
            if #{...} == 0 and self.zero ~= nil then
               print("tfun sees no args and we have a typ.zero() method, so invoking it")
               self.tfun(newInstance, self.zero())
            else
               self.tfun(newInstance, ...)
            end
         end
      else
         setmetatable(newInstance, __valueBasicMT)

         if self ~= nil then
            --print("self.tfun was nil")
         end
      end
      return newInstance
   end,
}


function __newAnyArrayValue(elem, len)
   local array = {}
   for i =0, len -1 do
      array[i]= elem.zero();
   end
   return array;
end


__methodSynthesizers = {};
__addMethodSynthesizer = function(f)
   if __methodSynthesizers == nil then
      f();
      return;
   end
   table.insert(__methodSynthesizers, f);
end;


__synthesizeMethods = function()
   __ipairsZeroCheck(__methodSynthesizers)
   for i,f in ipairs(__methodSynthesizers) do
      f();
   end
   __methodSynthesizers = nil;
end;

__ifaceKeyFor = function(x)
   if x == __ifaceNil then
      return 'nil';
   end
   local c = x.constructor;
   return c.__str .. '__' .. c.keyFor(x.__val);
end;

__identity = function(x) return x; end;

__typeIDCounter = 0;

__idKey = function(x)
   if x.__id == nil then
      __idCounter=__idCounter+1;
      x.__id = __idCounter;
   end
   return String(x.__id);
end;

__newType = function(size, kind, str, named, pkg, exported, constructor)
   local typ ={};
   setmetatable(typ, __tfunBasicMT)

   if kind ==  __kindBool or
      kind == __kindInt or 
      kind == __kindInt8 or 
      kind == __kindInt16 or 
      kind == __kindInt32 or 
      kind == __kindInt64 or 
      kind == __kindUint or 
      kind == __kindUint8 or 
      kind == __kindUint16 or 
      kind == __kindUint32 or 
      kind == __kindUint64 or 
      kind == __kindUintptr or 
   kind == __kindUnsafePointer then

      -- jea: I observe that
      -- primitives have: this.__val ~= v; and are the types are
      -- distinguished with typ.wrapped = true; versus
      -- all table based values, that have: this.__val == this;
      -- and no .wrapped field.
      --
      typ.tfun = function(this, v)
         this.__val = v;
         setmetatable(this, __valueBasicMT)
      end;
      typ.wrapped = true;
      typ.keyFor = function(x) return tostring(x); end;

   elseif kind == __kindString then
      
      typ.tfun = function(this, v)
         --print("strings' tfun called! with v='"..tostring(v).."' and this:")
         --__st(this)
         this.__val = v;
         setmetatable(this, __valueBasicMT)
      end;
      typ.wrapped = true;
      typ.keyFor = __identity; -- function(x) return "_" .. x; end;

   elseif kind == __kindFloat32 or
   kind == __kindFloat64 then
      
      typ.tfun = function(this, v)
         this.__val = v;
         setmetatable(this, __valueBasicMT)
      end;
      typ.wrapped = true;
      typ.keyFor = function(x) return __floatKey(x); end;


   elseif kind ==  __kindComplex64 then

      typ.tfun = function(this, re, im)
         this.__val = re + im*complex(0,1);
         setmetatable(this, __valueBasicMT)
      end;
      typ.wrapped = true;
      typ.keyFor = function(x) return tostring(x); end;
      
      --    typ.tfun = function(this, real, imag)
      --      this.__real = __fround(real);
      --      this.__imag = __fround(imag);
      --      this.__val = this;
      --    end;
      --    typ.keyFor = function(x) return x.__real .. "_" .. x.__imag; end;

   elseif kind ==  __kindComplex128 then

      typ.tfun = function(this, re, im)
         this.__val = re + im*complex(0,1);
         setmetatable(this, __valueBasicMT)
      end;
      typ.wrapped = true;
      typ.keyFor = function(x) return tostring(x); end;
      
      --     typ.tfun = function(this, real, imag)
      --        this.__real = real;
      --        this.__imag = imag;
      --        this.__val = this;
      --        this.__constructor = typ
      --     end;
      --     typ.keyFor = __identity --function(x) return x.__real .. "_" .. x.__imag; end;
      --    
      
   elseif kind ==  __kindPtr then

      if constructor ~= nil then
         --print("in newType kindPtr, constructor is not-nil: "..tostring(constructor))
      end
      typ.tfun = constructor  or
         function(this, getter, setter, target)
            --print("pointer typ.tfun which is same as constructor called! getter='"..tostring(getter).."'; setter='"..tostring(setter).."; target = '"..tostring(target).."'")
            this.__get = getter;
            this.__set = setter;
            this.__target = target;
            this.__val = this; -- seems to indicate a non-primitive value.
         end;
      typ.keyFor = __idKey;
      typ.init = function(elem)
         typ.elem = elem;
         typ.wrapped = (elem.kind == __kindArray);
         typ.__nil = typ(__throwNilPointerError, __throwNilPointerError);
      end;

   elseif kind ==  __kindSlice then
      
      typ.tfun = function(this, array)
         this.__array = array;
         this.__offset = 0;
         this.__length = __lenz(array);
         this.__capacity = this.__length;
         --print("jea debug: slice tfun set __length to ", this.__length)
         --print("jea debug: slice tfun set __capacity to ", this.__capacity)
         --print("jea debug: slice tfun sees array: ")
         --for i,v in pairs(array) do
         --   print("array["..tostring(i).."] = ", v)
         --end
         
         this.__val = this;
         this.__constructor = typ
         -- TODO: come back and fix up Luar.
         -- must set these for Luar (binary Go translation) to work.
         --this[__giPrivateRaw] = array
         --this[__giPrivateSliceProps] = this
         setmetatable(this, __valueSliceMT)
      end;
      typ.init = function(elem)
         typ.elem = elem;
         typ.comparable = false;
         typ.__nil = typ({},{});
      end;
      
   elseif kind ==  __kindArray then
      typ.tfun = function(this, v)
         print("in tfun ctor function for __kindArray, this="..tostring(this).." and v="..tostring(v))
         this.__val = v;
         this.__array = v; -- like slice, to reuse ipairs method.
         this.__offset = 0; -- like slice.
         this.__constructor = typ
         this.__length = __lenz(v)
         -- TODO: come back and fix up Luar
         -- must set these keys for Luar to work:
         --this[__giPrivateRaw] = v
         --this[__giPrivateArrayProps] = this
         setmetatable(this, __valueArrayMT)
      end;
      print("in newType for array, and typ.tfun = "..tostring(typ.tfun))
      typ.wrapped = true;
      typ.ptr = __newType(4, __kindPtr, "*" .. str, false, "", false, function(this, array)
                             this.__get = function() return array; end;
                             this.__set = function(v) typ.copy(this, v); end;
                             this.__val = array;
      end);
      typ.init = function(elem, len)
         print("init() called for array.")
         typ.elem = elem;
         typ.len = len;
         typ.comparable = elem.comparable;
         typ.keyFor = function(x)
            return __mapAndJoinStrings("_", x, function(e)
                                          return string.gsub(tostring(elem.keyFor(e)), "\\", "\\\\")
            end)
         end
         typ.copy = function(dst, src)
            __copyArray(dst, src, 0, 0, #src, elem);
         end;
         typ.ptr.init(typ);

         -- TODO:
         -- jea: nilCheck allows asserting that a pointer is not nil before accessing it.
         -- jea: what seems odd is that the state of the pointer is
         -- here defined on the type itself, and not on the particular instance of the
         -- pointer. But perhaps this is javascript's prototypal inheritence in action.
         --
         -- gopherjs uses them in comma expressions. example, condensed:
         --     p$1 = new ptrType(...); sa$3.Port = (p$1.nilCheck, p$1[0])
         --
         -- Since comma expressions are not (efficiently) supported in Lua, let
         -- implement the nil check in a different manner.
         -- js: Object.defineProperty(typ.ptr.__nil, "nilCheck", { get= __throwNilPointerError end);
      end;
      -- end __kindArray

      
   elseif kind ==  __kindChan then
      
      typ.tfun = function(this, v) this.__val = v; end;
      typ.wrapped = true;
      typ.keyFor = __idKey;
      typ.init = function(elem, sendOnly, recvOnly)
         typ.elem = elem;
         typ.sendOnly = sendOnly;
         typ.recvOnly = recvOnly;
      end;
      

   elseif kind ==  __kindFunc then 

      typ.tfun = function(this, v) this.__val = v; end;
      typ.wrapped = true;
      typ.init = function(params, results, variadic)
         typ.params = params;
         typ.results = results;
         typ.variadic = variadic;
         typ.comparable = false;
      end;
      

   elseif kind ==  __kindInterface then 

      typ = { implementedBy= {}, missingMethodFor= {} };
      typ.keyFor = __ifaceKeyFor;
      typ.init = function(methods)
         print("top of init() for kindInterface, methods= ")
         __st(methods)
         print("and also at top of init() for kindInterface, typ= ")
         __st(typ)
         typ.methods = methods;
         for _, m in pairs(methods) do
            -- TODO:
            -- jea: why this? seems it would end up being a huge set?
            --print("about to index with m.__prop where m =")
            --__st(m)
            __ifaceNil[m.__prop] = __throwNilPointerError;
         end;
      end;
      
      
   elseif kind ==  __kindMap then 
      
      typ.tfun = function(this, v) this.__val = v; end;
      typ.wrapped = true;
      typ.init = function(key, elem)
         typ.key = key;
         typ.elem = elem;
         typ.comparable = false;
      end;
      
   elseif kind ==  __kindStruct then
      
      typ.tfun = function(this, v)
         --print("top of simple kindStruct tfun")
         this.__val = v;
      end;
      typ.wrapped = true;

      -- the typ.prototype will be the
      -- metatable for instances of the struct; this is
      -- equivalent to the prototype in js.
      --
      typ.prototype = {__name="methodSet for "..str, __typ = typ}
      typ.prototype.__index = typ.prototype

      local ctor = function(this, ...)
         --print("top of struct ctor, this="..tostring(this).."; typ.__constructor = "..tostring(typ.__constructor))
         local args = {...}
         --__st(args, "args to ctor")
         --__st(args[1], "args[1]")

         --print("callstack:")
         --print(debug.traceback())
         
         this.__get = function() return this; end;
         this.__set = function(v) typ.copy(this, v); end;
         if typ.__constructor ~= nil then
            -- have to skip the first empty table...
            local skipFirst = {}
            for i,v in ipairs(args) do
               if i > 1 then table.insert(skipFirst, v) end
            end
            typ.__constructor(this, unpack(skipFirst));
         end
         setmetatable(this, typ.ptr.prototype)
      end
      typ.ptr = __newType(4, __kindPtr, "*" .. str, false, pkg, exported, ctor);
      -- __newType sets typ.comparable = true

      -- pointers have their own method sets, but *T can call elem methods in Go.
      typ.ptr.elem = typ;
      typ.ptr.prototype = {__name="methodSet for "..typ.ptr.__str, __typ = typ.ptr}
      typ.ptr.prototype.__index = typ.ptr.prototype

      -- incrementally expand the method set. Full
      -- signature details are passed in det.
      
      -- a) for pointer
      typ.ptr.__addToMethods=function(det)
         print("typ.ptr.__addToMethods called, existing methods:")
         __st(typ.ptr.methods, "typ.ptr.methods")
         __st(det, "det")
         table.insert(typ.ptr.methods, det)
      end

      -- b) for struct
      typ.__addToMethods=function(det)
         print("typ.__addToMethods called, existing methods:")
         __st(typ.methods, "typ.methods")
         __st(det, "det")
         table.insert(typ.methods, det)
      end
      
      -- __kindStruct.init is here:
      typ.init = function(pkgPath, fields)
         --print("top of init() for struct, fields=")
         --for i, f in pairs(fields) do
         --__st(f, "field #"..tostring(i))
         --__st(f.__typ, "typ of field #"..tostring(i))
         --end
         
         typ.pkgPath = pkgPath;
         typ.fields = fields;
         __ipairsZeroCheck(fields)
         for i,f in ipairs(fields) do
            __st(f,"f")
            if not f.__typ.comparable then
               typ.comparable = false;
               break;
            end
         end
         typ.keyFor = function(x)
            local val = x.__val;
            return __mapAndJoinStrings("_", fields, function(f)
                                          return string.gsub(tostring(f.__typ.keyFor(val[f.__prop])), "\\", "\\\\")
            end)
         end;
         typ.copy = function(dst, src)
            --print("top of typ.copy for structs, here is dst then src:")
            --__st(dst, "dst")
            --__st(src, "src")
            --print("fields:")
            --__st(fields,"fields")
            __ipairsZeroCheck(fields)
            for _, f in ipairs(fields) do
               local sw2 = f.__typ.kind
               
               if sw2 == __kindArray or
               sw2 ==  __kindStruct then 
                  f.__typ.copy(dst[f.__prop], src[f.__prop]);
               else
                  dst[f.__prop] = src[f.__prop];
               end
            end
         end;
         --print("jea debug: on __kindStruct: set .copy on typ to .copy=", typ.copy)
         -- /* nil value */
         local properties = {};
         __ipairsZeroCheck(fields)
         for i,f in ipairs(fields) do
            properties[f.__prop] = { get= __throwNilPointerError, set= __throwNilPointerError };
         end;
         typ.ptr.__nil = {} -- Object.create(constructor.prototype,s properties);
         --if constructor ~= nil then
         --   constructor(typ.ptr.__nil)
         --end
         typ.ptr.__nil.__val = typ.ptr.__nil;
         -- /* methods for embedded fields */
         __addMethodSynthesizer(function()
               local synthesizeMethod = function(target, m, f)
                  if target.prototype[m.__prop] ~= nil then return; end
                  target.prototype[m.__prop] = function()
                     local v = this.__val[f.__prop];
                     if f.__typ == __jsObjectPtr then
                        v = __jsObjectPtr(v);
                     end
                     if v.__val == nil then
                        local w = {}
                        f.__typ(w, v);
                        v = w
                     end
                     return v[m.__prop](v, arguments);
                  end;
               end;
               for i,f in ipairs(fields) do
                  if f.anonymous then
                     for _, m in ipairs(__methodSet(f.__typ)) do
                        synthesizeMethod(typ, m, f);
                        synthesizeMethod(typ.ptr, m, f);
                     end;
                     for _, m in ipairs(__methodSet(__ptrType(f.__typ))) do
                        synthesizeMethod(typ.ptr, m, f);
                     end;
                  end
               end;
         end);
      end;
      
   else
      error("invalid kind: " .. tostring(kind));
   end
   
   -- set zero() method
   if kind == __kindBool then
      typ.zero = function() return false; end;

   elseif kind ==__kindMap then
      typ.zero = function() return nil; end;

   elseif kind == __kindInt or
      kind ==  __kindInt8 or
      kind ==  __kindInt16 or
      kind ==  __kindInt32 or
   kind ==  __kindInt64 then
      typ.zero = function() return 0LL; end;
      
   elseif kind ==  __kindUint or
      kind ==  __kindUint8  or
      kind ==  __kindUint16 or
      kind ==  __kindUint32 or
      kind ==  __kindUint64 or
      kind ==  __kindUintptr or
   kind ==  __kindUnsafePointer then
      typ.zero = function() return 0ULL; end;

   elseif   kind ==  __kindFloat32 or
   kind ==  __kindFloat64 then
      typ.zero = function() return 0; end;
      
   elseif kind ==  __kindString then
      typ.zero = function() return ""; end;

   elseif kind == __kindComplex64 or
   kind == __kindComplex128 then
      local zero = typ(0, 0);
      typ.zero = function() return zero; end;
      
   elseif kind == __kindPtr or
   kind == __kindSlice then
      
      typ.zero = function() return typ.__nil; end;
      
   elseif kind == __kindChan then
      typ.zero = function() return __chanNil; end;
      
   elseif kind == __kindFunc then
      typ.zero = function() return __throwNilPointerError; end;
      
   elseif kind == __kindInterface then
      typ.zero = function() return __ifaceNil; end;
      
   elseif kind == __kindArray then
      
      typ.zero = function()
         print("in zero() for array...")
         return __newAnyArrayValue(typ.elem, typ.len)
      end;

   elseif kind == __kindStruct then
      typ.zero = function()
         return typ.ptr();
      end;

   else
      error("invalid kind: " .. tostring(kind))
   end

   typ.id = __typeIDCounter;
   __typeIDCounter=__typeIDCounter+1;
   typ.size = size;
   typ.kind = kind;
   typ.__str = str;
   typ.named = named;
   typ.pkg = pkg;
   typ.exported = exported;
   typ.methods = typ.methods or {};
   typ.methodSetCache = nil;
   typ.comparable = true;
   return typ;
   
end

function __methodSet(typ)
   
   --if typ.methodSetCache ~= nil then
   --return typ.methodSetCache;
   --end
   local base = {};

   local isPtr = (typ.kind == __kindPtr);
   print("__methodSet called with typ=")
   __st(typ)
   print("__methodSet sees isPtr=", isPtr)
   
   if isPtr  and  typ.elem.kind == __kindInterface then
      -- jea: I assume this is because pointers to interfaces don't themselves have methods.
      typ.methodSetCache = {};
      return {};
   end

   local myTyp = typ
   if isPtr then
      myTyp = typ.elem
   end
   local current = {{__typ= myTyp, indirect= isPtr}};

   -- the Go spec says:
   -- The method set of the corresponding pointer type *T is
   -- the set of all methods declared with receiver *T or T
   -- (that is, it also contains the method set of T).
   
   local seen = {};

   print("top of while, #current is", #current)
   while #current > 0 do
      local next = {};
      local mset = {};
      
      for _,e in pairs(current) do
         print("e from pairs(current) is:")
         __st(e,"e")
         __st(e.__typ,"e.__typ")
         if seen[e.__typ.__str] then
            print("already seen "..e.__typ.__str.." so breaking out of match loop")
            break
         end
         seen[e.__typ.__str] = true;
         
         if e.__typ.named then
            print("have a named type, e.__typ.methods is:")
            __st(e.__typ.methods, "e.__typ.methods")
            for _, mthod in pairs(e.__typ.methods) do
               print("adding to mset, mthod = ", mthod)
               table.insert(mset, mthod);
            end
            if e.indirect then
               for _, mthod in pairs(__ptrType(e.__typ).methods) do
                  --print("adding to mset, mthod = ", mthod)
                  table.insert(mset, mthod)
               end
            end
         end
         
         -- switch e.__typ.kind
         local knd = e.__typ.kind
         
         if knd == __kindStruct then
            
            -- assume that e.__typ.fields must be an array!
            -- TODO: remove this assert after confirmation.
            __assertIsArray(e.__typ.fields)
            __ipairsZeroCheck(e.__typ.fields)
            for i,f in ipairs(e.__typ.fields) do
               if f.anonymous then
                  local fTyp = f.__typ;
                  local fIsPtr = (fTyp.kind == __kindPtr);
                  local ty 
                  if fIsPtr then
                     ty = fTyp.elem
                  else
                     ty = fTyp
                  end
                  table.insert(next, {__typ=ty, indirect= e.indirect or fIsPtr});
               end;
            end;
            
            
         elseif knd == __kindInterface then
            
            for _, mthod in pairs(e.__typ.methods) do
               --print("adding to mset, mthod = ", mthod)
               table.insert(mset, mthod)
            end
         end
      end;

      -- above may have made duplicates, now dedup
      --print("at dedup, #mset = " .. tostring(#mset))
      for _, m in pairs(mset) do
         if base[m.name] == nil then
            base[m.name] = m;
         end
      end;
      print("after dedup, base for typ '"..typ.__str.."' is ")
      __st(base)
      
      current = next;
   end
   
   typ.methodSetCache = {};
   table.sort(base)
   for _, detail in pairs(base) do
      table.insert(typ.methodSetCache, detail)
   end;
   return typ.methodSetCache;
end;


__type__bool    = __newType( 1, __kindBool,    "bool",     true, "", false, nil);
__type__int = __newType( 8, __kindInt,     "int",   true, "", false, nil);
__type__int8    = __newType( 1, __kindInt8,    "int8",     true, "", false, nil);
__type__int16   = __newType( 2, __kindInt16,   "int16",    true, "", false, nil);
__type__int32   = __newType( 4, __kindInt32,   "int32",    true, "", false, nil);
__type__int64   = __newType( 8, __kindInt64,   "int64",    true, "", false, nil);
__type__uint    = __newType( 8, __kindUint,    "uint",     true, "", false, nil);
__type__uint8   = __newType( 1, __kindUint8,   "uint8",    true, "", false, nil);
__type__uint16  = __newType( 2, __kindUint16,  "uint16",   true, "", false, nil);
__type__uint32  = __newType( 4, __kindUint32,  "uint32",   true, "", false, nil);
__type__uint64  = __newType( 8, __kindUint64,  "uint64",   true, "", false, nil);
__type__uintptr = __newType( 8, __kindUintptr,    "uintptr",  true, "", false, nil);
__type__float32 = __newType( 8, __kindFloat32,    "float32",  true, "", false, nil);
__type__float64 = __newType( 8, __kindFloat64,    "float64",  true, "", false, nil);
__type__complex64  = __newType( 8, __kindComplex64,  "complex64",   true, "", false, nil);
__type__complex128 = __newType(16, __kindComplex128, "complex128",  true, "", false, nil);
__type__string  = __newType(16, __kindString,  "string",   true, "", false, nil);
--__type__unsafePointer = __newType( 8, __kindUnsafePointer, "unsafe.Pointer", true, "", false, nil);

__ptrType = function(elem)
   local typ = elem.ptr;
   if typ == nil then
      typ = __newType(4, __kindPtr, "*" .. elem.__str, false, "", elem.exported, nil);
      elem.ptr = typ;
      typ.init(elem);
   end
   return typ;
end;

__newDataPointer = function(data, constructor)
   if constructor.elem.kind == __kindStruct then
      return data;
   end
   return constructor(function() return data; end, function(v) data = v; end);
end;

__indexPtr = function(array, index, constructor)
   array.__ptr = array.__ptr  or  {};
   local a = array.__ptr[index]
   if a ~= nil then
      return a
   end
   a = constructor(function() return array[index]; end, function(v) array[index] = v; end);
   array.__ptr[index] = a
   return a
end;


__arrayTypes = {};
__arrayType = function(elem, len)
   local typeKey = elem.id .. "_" .. len;
   local typ = __arrayTypes[typeKey];
   if typ == nil then
      typ = __newType(24, __kindArray, "[" .. len .. "]" .. elem.__str, false, "", false, nil);
      __arrayTypes[typeKey] = typ;
      typ.init(elem, len);
   end
   return typ;
end;


__chanType = function(elem, sendOnly, recvOnly)
   
   local str
   local field
   if recvOnly then
      str = "<-chan " .. elem.__str
      field = "RecvChan"
   elseif sendOnly then
      str = "chan<- " .. elem.__str
      field = "SendChan"
   else
      str = "chan " .. elem.__str
      field = "Chan"
   end
   local typ = elem[field];
   if typ == nil then
      typ = __newType(4, __kindChan, str, false, "", false, nil);
      elem[field] = typ;
      typ.init(elem, sendOnly, recvOnly);
   end
   return typ;
end;

function __Chan(elem, capacity)
   local this = {}
   if capacity < 0  or  capacity > 2147483647 then
      __throwRuntimeError("makechan: size out of range");
   end
   this.elem = elem;
   this.__capacity = capacity;
   this.__buffer = {};
   this.__sendQueue = {};
   this.__recvQueue = {};
   this.__closed = false;
   return this
end;
__chanNil = __Chan(nil, 0);
__chanNil.__recvQueue = { length= 0, push= function()end, shift= function() return nil; end, indexOf= function() return -1; end; };
__chanNil.__sendQueue = __chanNil.__recvQueue


__funcTypes = {};
__funcType = function(params, results, variadic)
   __st(results, "results")
   local typeKey = "parm_" .. __mapAndJoinStrings(",", params, function(p)
                                          if p.id == nil then
                                             error("no id for p=",p);
                                          end;
                                          return p.id;
   end) .. "__results_" .. __mapAndJoinStrings(",", results, function(r)
                                                 if r.id == nil then
                                                    error("no id for r=",r);
                                                 end;
                                                 return r.id;
                                             end) .. "__variadic_" .. tostring(variadic);
   print("typeKey is '"..typeKey.."'")
   local typ = __funcTypes[typeKey];
   if typ == nil then
      local paramTypes = __mapArray(params, function(p) return p.__str; end);
      if variadic then
         paramTypes[#paramTypes - 1] = "..." .. paramTypes[#paramTypes - 1].substr(2);
      end
      local str = "func(" .. table.concat(paramTypes, ", ") .. ")";
      if #results == 1 then
         str = str .. " " .. results[1].__str;
   end else if #results > 1 then
            str = str .. " (" .. __mapAndJoinStrings(", ", results, function(r) return r.__str; end) .. ")";
            end
         typ = __newType(4, __kindFunc, str, false, "", false, nil);
         __funcTypes[typeKey] = typ;
         typ.init(params, results, variadic);
   end
   return typ;
end;

--- interface types here

function __interfaceStrHelper(m)
   local s = ""
   if m.pkg ~= "" then
      s = m.pkg .. "."
   end
   return s .. m.name .. string.sub(m.__typ.__str, 6) -- sub for removing "__kind"
end

__interfaceTypes = {};
__interfaceType = function(methods)
   
   local typeKey = __mapAndJoinStrings("_", methods, function(m)
                                          return m.pkg .. "," .. m.name .. "," .. m.__typ.id;
   end)
   local typ = __interfaceTypes[typeKey];
   if typ == nil then
      local str = "interface {}";
      if #methods ~= 0 then
         str = "interface { " .. __mapAndJoinStrings("; ", methods, __interfaceStrHelper) .. " }"
      end
      typ = __newType(8, __kindInterface, str, false, "", false, nil);
      __interfaceTypes[typeKey] = typ;
      typ.init(methods);
   end
   return typ;
end;
__type__emptyInterface = __interfaceType({});
__ifaceNil = {};
__error = __newType(8, __kindInterface, "error", true, "", false, nil);
__error.init({{__prop= "Error", __name= "Error", __pkg= "", __typ= __funcType({}, {__String}, false) }});

__mapTypes = {};
__mapType = function(key, elem)
   local typeKey = key.id .. "_" .. elem.id;
   local typ = __mapTypes[typeKey];
   if typ == nil then
      typ = __newType(8, __kindMap, "map[" .. key.__str .. "]" .. elem.__str, false, "", false, nil);
      __mapTypes[typeKey] = typ;
      typ.init(key, elem);
   end
   return typ;
end;

__makeMap = function(keyForFunc, entries, keyType, elemType, mapType)
   local m={};
   for k, e in pairs(entries) do
      local key = keyForFunc(k)
      --print("using key ", key, " for k=", k)
      m[key] = e;
   end
   local mp = _gi_NewMap(keyType, elemType, m);
   --setmetatable(mp, mapType)
   return mp
end;


-- __basicValue2kind: identify type of basic value
--   or return __kindUnknown if we don't recognize it.
function __basicValue2kind(v)

   local ty = type(v)
   if ty == "cdata" then
      local cty = __ffi.typeof(v)
      if cty == int64 then
         return __kindInt
      elseif cty == int8 then
         return __kindInt8
      elseif cty == int16 then
         return __kindInt16
      elseif cty == int32 then
         return __kindInt32
      elseif cty == int64 then
         return __kindInt64
      elseif cty == uint then
         return __kindUint
      elseif cty == uint8 then
         return __kindUint8
      elseif cty == uint16 then
         return __kindUint16
      elseif cty == uint32 then
         return __kindUint32
      elseif cty == uint64 then
         return __kindUint64
      elseif cty == float32 then
         return __kindFloat32
      elseif cty == float64 then
         return __kindFloat64         
      else
         return __kindUnknown;
         --error("__basicValue2kind: unhandled cdata cty: '"..tostring(cty).."'")
      end      
   elseif ty == "boolean" then
      return __kindBool;
   elseif ty == "number" then
      return __kindFloat64
   elseif ty == "string" then
      return __kindString
   end
   
   return __kindUnknown;
   --error("__basicValue2kind: unhandled ty: '"..ty.."'")   
end

__sliceType = function(elem)
   print("__sliceType called with elem = ", elem)
   local typ = elem.slice;
   if typ == nil then
      typ = __newType(24, __kindSlice, "[]" .. elem.__str, false, "", false, nil);
      elem.slice = typ;
      typ.init(elem);
   end
   return typ;
end;

__makeSlice = function(typ, length, capacity)
   length = tonumber(length)
   if capacity == nil then
      capacity = length
   else
      capacity = tonumber(capacity)
   end
   if length < 0  or  length > 9007199254740992 then -- 2^53
      __throwRuntimeError("makeslice: len out of range");
   end
   if capacity < 0  or  capacity < length  or  capacity > 9007199254740992 then
      __throwRuntimeError("makeslice: cap out of range");
   end
   local array = __newAnyArrayValue(typ.elem, capacity)
   local slice = typ(array);
   slice.__length = length;
   return slice;
end;




function field2strHelper(f)
   local tag = ""
   if f.tag ~= "" then
      tag = string.gsub(f.tag, "\\", "\\\\")
      tag = string.gsub(tag, "\"", "\\\"")
   end
   return f.name .. " " .. f.__typ.__str .. tag
end

function typeKeyHelper(f)
   return f.name .. "," .. f.__typ.id .. "," .. f.tag;
end

__structTypes = {};
__structType = function(pkgPath, fields)
   local typeKey = __mapAndJoinStrings("_", fields, typeKeyHelper)

   local typ = __structTypes[typeKey];
   if typ == nil then
      local str
      if #fields == 0 then
         str = "struct {}";
      else
         str = "struct { " .. __mapAndJoinStrings("; ", fields, field2strHelper) .. " }";
      end
      
      typ = __newType(0, __kindStruct, str, false, "", false, function()
                         local this = {}
                         this.__val = this;
                         for i = 0, #fields-1 do
                            local f = fields[i];
                            local arg = arguments[i];
                            if arg ~= nil then
                               this[f.__prop] = arg
                            else
                               this[f.__prop] = f.__typ.zero();
                            end
                         end
                         return this
      end);
      __structTypes[typeKey] = typ;
      typ.init(pkgPath, fields);
   end
   return typ;
end;


__equal = function(a, b, typ)
   if typ == __jsObjectPtr then
      return a == b;
   end

   local sw = typ.kind
   if sw == __kindComplex64 or
   sw == __kindComplex128 then
      return a.__real == b.__real  and  a.__imag == b.__imag;
      
   elseif sw == __kindInt64 or
   sw == __kindUint64 then 
      return a.__high == b.__high  and  a.__low == b.__low;
      
   elseif sw == __kindArray then 
      if #a ~= #b then
         return false;
      end
      for i=0,#a-1 do
         if  not __equal(a[i], b[i], typ.elem) then
            return false;
         end
      end
      return true;
      
   elseif sw == __kindStruct then
      
      for i = 0,#(typ.fields)-1 do
         local f = typ.fields[i];
         if  not __equal(a[f.__prop], b[f.__prop], f.__typ) then
            return false;
         end
      end
      return true;
   elseif sw == __kindInterface then 
      return __interfaceIsEqual(a, b);
   else
      return a == b;
   end
end;

__interfaceIsEqual = function(a, b)
   print("top of __interfaceIsEqual! a is:")
   __st(a,"a")
   print("top of __interfaceIsEqual! b is:")   
   __st(b,"b")
   if a == nil or b == nil then
      print("one or both is nil")
      if a == nil and b == nil then
         print("both are nil")
         return true
      else
         print("one is nil, one is not")
         return false
      end
   end
   if a == __ifaceNil  or  b == __ifaceNil then
      print("one or both is __ifaceNil")
      return a == b;
   end
   if a.constructor ~= b.constructor then
      return false;
   end
   if a.constructor == __jsObjectPtr then
      return a.object == b.object;
   end
   if  not a.constructor.comparable then
      __throwRuntimeError("comparing uncomparable type "  ..  a.constructor.__str);
   end
   return __equal(a.__val, b.__val, a.constructor);
end;


__assertType = function(value, typ, returnTuple)

   local isInterface = (typ.kind == __kindInterface)
   local ok
   local missingMethod = "";
   if value == __ifaceNil then
      ok = false;
   elseif  not isInterface then
      ok = value.__typ == typ;
   else
      local valueTypeString = value.__typ.__str;

      -- this caching doesn't get updated as methods
      -- are added, so disable it until fixed, possibly, in the future.
      --ok = typ.implementedBy[valueTypeString];
      ok = nil
      if ok == nil then
         ok = true;
         local valueMethodSet = __methodSet(value.__typ);
         local interfaceMethods = typ.methods;
         print("valueMethodSet is")
         __st(valueMethodSet)
         print("interfaceMethods is")
         __st(interfaceMethods)

         __ipairsZeroCheck(interfaceMethods)
         __ipairsZeroCheck(valueMethodSet)
         for _, tm in ipairs(interfaceMethods) do            
            local found = false;
            for _, vm in ipairs(valueMethodSet) do
               print("checking vm against tm, where tm=")
               __st(tm)
               print("and vm=")
               __st(vm)
               
               if vm.name == tm.name  and  vm.pkg == tm.pkg  and  vm.__typ == tm.__typ then
                  print("match found against vm and tm.")
                  found = true;
                  break;
               end
            end
            if  not found then
               print("match *not* found for tm.name = '"..tm.__name.."'")
               ok = false;
               typ.missingMethodFor[valueTypeString] = tm.name;
               break;
            end
         end
         typ.implementedBy[valueTypeString] = ok;
      end
      if not ok then
         missingMethod = typ.missingMethodFor[valueTypeString];
      end
   end
   --print("__assertType: after matching loop, ok = ", ok)
   
   if not ok then
      if returnTuple then
         return typ.zero(), false
      end
      local msg = ""
      if value ~= __ifaceNil then
         msg = value.__typ.__str
      end
      --__panic(__packages["runtime"].TypeAssertionError.ptr("", msg, typ.__str, missingMethod));
      error("type-assertion-error: could not '"..msg.."' -> '"..typ.__str.."', missing method '"..missingMethod.."'")
   end
   
   if not isInterface then
      value = value.__val;
   end
   if typ == __jsObjectPtr then
      value = value.object;
   end
   if returnTuple then
      return value, true
   end
   return value
end;

__stackDepthOffset = 0;
__getStackDepth = function()
   local err = Error(); -- new
   if err.stack == nil then
      return nil;
   end
   return __stackDepthOffset + #err.stack.split("\n");
end;

-- possible replacement for ipairs.
-- starts at a[0] if it is present.
function __zipairs(a)
   local n = 0
   local s = #a
   if a[0] ~= nil then
      n = -1
   end
   return function()
      n = n + 1
      if n <= s then return n,a[n] end
   end
end

--helper, get rid of 0, shift everything up in the returned.
function __elim0(t)
   if type(t) ~= 'table' then
      return t
   end

   if t == nil then
      return
   end
   local n = tonumber(#t)
   --print("n is "..tostring(n))
   --__st(n, "n")
   if n == 0 then
      return
   end
   local r = {}
   local z = t[0]
   local off = 0
   if z ~= nil then
      off = 1
   end
   
   for i=1,n do
      table.insert(r, t[i-off])
   end
   return r
end

function __unpack0(t)
   if type(t) ~= 'table' then
      return t
   end
   if raw == nil then
      return
   end
   return unpack(__elim0(t))
end