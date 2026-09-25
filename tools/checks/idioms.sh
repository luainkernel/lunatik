#!/usr/bin/env bash
# Names the idioms a C diff is read for and a review round passed over on #850: a raise
# the tree spells with one call, a guard repeated across methods, a version a feature
# needs named as one release, a kernel version guard whose first arm is the older
# kernel's, which raising the floor would have to rewrite rather than delete, and a pid
# cast from luaL_checkinteger, which #1140's linux.netns truncated. Takes file
# paths; silent on files that carry none, and on the Lua fork under lua/, whose guards
# keep upstream first. The report is read, not obeyed: a check-then-throw that releases
# something first is not lunatik_try's, and the line between the two is what the reader
# looks at.

for file in "$@"; do
	case "$file" in */lua/*|lua/*) continue ;; *.c|*.h) ;; *) continue ;; esac
	awk -v f="$file" '
	function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
	{
		line = trim($0)
		if (line ~ /^#[ \t]*if/) {
			depth++
			inverted[depth] = (line ~ /LINUX_VERSION_CODE[ \t]*<=?[ \t]*KERNEL_VERSION/) ? NR : 0
		}
		else if (line ~ /^#[ \t]*else/ && inverted[depth])
			printf "%s:%d: version guard from line %d puts the older kernel first: current kernel in the if arm, fallback in else\n", f, NR, inverted[depth]
		else if (line ~ /^#[ \t]*endif/)
			depth--
		if (prev ~ /^if \(.*\)$/ && line ~ /^return luaL_argerror\(/)
			printf "%s:%d: luaL_argerror as the body of an if: a wrong value at an index is luaL_argcheck\n", f, NR
		if (prev ~ /^if \(\(ret = [a-z_]+\(.*\)\) (!=|<) 0\)$/ && line ~ /^lunatik_throw\(L, ret\);$/)
			printf "%s:%d: a check followed by lunatik_throw and nothing between: lunatik_try(L, op, ...) when nothing is held\n", f, NR
		if (line ~ /^luaL_argcheck\(/) {
			key = line
			gsub(/, (ix|idx|[0-9]+),/, ", N,", key)
			gsub(/[ \t]+/, " ", key)
			if (key in seen)
				printf "%s:%d: luaL_argcheck repeats line %d: one helper\n", f, NR, seen[key]
			else
				seen[key] = NR
		}
		if (line ~ /needs an? [0-9]+\.[0-9]+ kernel/)
			printf "%s:%d: a version a feature needs reads as that one release: \"kernel X.Y or later\"\n", f, NR
		if (line ~ /\(pid_t\)[ \t]*luaL_(check|opt)integer\(/)
			printf "%s:%d: a pid cast from luaL_checkinteger truncates before the kernel sees it: lunatik_checkinteger(L, ix, 1, PID_MAX_LIMIT), as socket.new bounds it\n", f, NR
		prev = line
	}' "$file"
done

