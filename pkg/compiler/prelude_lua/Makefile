all:
	echo "package prelude\n\nconst Prelude = \`\n" > prelude.go
	for i in `ls -1 ../*.lua|grep -v test|grep -v tutil.lua`; do echo "-------- $$i -------"; cat $$i; echo "-----------------------"; done >> prelude.go
	echo "\n\`\n" >> prelude.go
