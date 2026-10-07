#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Names the idioms a C diff is read for and a review round passed over on #850: a raise
# the tree spells with one call, a guard repeated across methods, a version a feature
# needs named as one release, a kernel version guard whose first arm is the older
# kernel's, which raising the floor would have to rewrite rather than delete, and a pid
# cast from luaL_checkinteger, which #1140's linux.netns truncated. A static inline
# is or has predicate whose body is one return is a macro, and an if whose two arms
# call one function is a ternary: #1358 and #1383 passed their reviews in those shapes,
# and the maintainer asked for both. A predicate macro spelled with ?: reads as two rules,
# and a loop header a file spells twice is a foreach macro: #1504 and #1539 carried those.
# A value a function computes before a check that raises and does not read it decides before
# validating, and is computed after the checks: #1584's fifo:push spelled `bool fits` above
# its lunatik_checkbounds until the maintainer asked why. A condition of three tests or more,
# or one that runs onto the next line, is a predicate the file names: #1705's checksum() spelled
# two until the maintainer asked for luaskb_iswhole4 and luaskb_iswhole6. A load of one mode
# refuses what require and load take, and darken.run loaded text only, with no reason written,
# from its first commit until a stripped chunk had to ship encrypted (#1767).
# Takes file paths; silent on files that carry none, and on the Lua fork under lua/, whose
# guards keep upstream first. The report is read, not obeyed: a check-then-throw that releases
# something first is not lunatik_try's, and the line between the two is what the reader
# looks at.

for file in "$@"; do
	case "$file" in */lua/*|lua/*) continue ;; *.c|*.h) ;; *) continue ;; esac
	awk -v f="$file" '
	function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
	function reads(s, name) { return match(s, "(^|[^A-Za-z0-9_])" name "([^A-Za-z0-9_]|$)") }
	# the name a declaration computes into, "" for one that only copies, casts or names a constant
	# or that calls with the Lua state, which validates rather than computes
	function computed(s,   lhs, init) {
		if (s !~ /^(const |struct |unsigned |signed )*[A-Za-z_][A-Za-z0-9_]*[ \t*]+[A-Za-z_*][A-Za-z0-9_]*[ \t]*=[ \t]*[^=].*;$/)
			return ""
		lhs = trim(substr(s, 1, index(s, "=") - 1))
		init = trim(substr(s, index(s, "=") + 1)); sub(/;$/, "", init)
		if (init ~ /\(L[,)]/ || init ~ /^(\([^()]*\))?[ \t]*&?[A-Za-z_][A-Za-z0-9_]*$/ || init ~ /^(-?[0-9]+|0x[0-9a-fA-F]+|\{.*\})$/)
			return ""
		match(lhs, /[A-Za-z_][A-Za-z0-9_]*$/)
		return substr(lhs, RSTART, RLENGTH)
	}
	# the function a statement of one call calls, "" for any other statement
	function callee(s) {
		sub(/^return /, "", s)
		return s ~ /^[A-Za-z_][A-Za-z0-9_]*\(.*\);$/ ? substr(s, 1, index(s, "(") - 1) : ""
	}
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
		if (line ~ /(luaL_loadbufferx|luaL_loadfilex|lua_load)[ \t]*\(.*,[ \t]*"[tb]"[ \t]*\)/)
			printf "%s:%d: a load of one mode refuses what require and load take: say beside it what the refusal protects\n", f, NR
		if (line ~ /\(pid_t\)[ \t]*luaL_(check|opt)integer\(/)
			printf "%s:%d: a pid cast from luaL_checkinteger truncates before the kernel sees it: lunatik_checkinteger(L, ix, 1, PID_MAX_LIMIT), as socket.new bounds it\n", f, NR
		if (line ~ /^(else )?(if|while) \(/) {
			cond = line
			joins = gsub(/\|\||&&/, "&", cond)
			if (joins >= 2 || line ~ /(\|\||&&)[ \t]*\\?$/)
				printf "%s:%d: a condition of three tests or more, or one that runs onto the next line, is a predicate: name it, in the is or has family\n", f, NR
		}
		if ($0 ~ /^static inline bool [a-z0-9_]*_(is|has)[a-z0-9_]*\(/) {
			pred = NR
			body = ""
		}
		else if (pred && $0 ~ /^\}/) {
			if (body ~ /^return [^;{]*;$/)
				printf "%s:%d: a predicate of one expression is a macro, in the lunatik_isirq family'"'"'s shape\n", f, pred
			pred = 0
		}
		else if (pred && line != "{")
			body = body (body == "" ? "" : " ") line
		if ($0 ~ /^#define [a-z0-9_]*_(is|has)[a-z0-9_]*\(/) {
			macro = NR
			definition = ""
		}
		if (macro) {
			definition = definition $0
			if ($0 !~ /\\$/) {
				if (definition ~ /\?/)
					printf "%s:%d: a predicate spelled with ?: reads as two rules: an || of the exception and the rule, or an && of the conditions\n", f, macro
				macro = 0
			}
		}
		if (line ~ /^for \(/) {
			loop = line
			sub(/[ \t]*\{$/, "", loop)
			gsub(/[ \t]+/, " ", loop)
			if (loop in loops)
				printf "%s:%d: the loop of line %d again: a foreach macro names a walk over one domain, as lunatik_foreachruntime does\n", f, NR, loops[loop]
			else
				loops[loop] = NR
		}
		if ($0 ~ /^[{}]/)
			split("", pending)
		else {
			if (line ~ /^(lunatik_checkbounds|luaL_argcheck|luaL_argerror|luaL_check[a-z]*|lunatik_check[a-z]*|lunatik_argcheck[a-z]*)\(/)
				for (name in pending)
					if (!reads(line, name)) {
						printf "%s:%d: %s is computed before the check of line %d, which does not read it: compute it after the checks\n", f, pending[name], name, NR
						delete pending[name]
					}
			for (name in pending)
				if (reads(line, name))
					delete pending[name]
			if ((name = computed(line)) != "")
				pending[name] = NR
		}
		arm[NR] = line
		if (NR > 3 && arm[NR - 1] == "else" && arm[NR - 3] ~ /^if \(.*\)([ \t]*\/\*.*\*\/)?$/ && callee(arm[NR - 2]) != "" &&
		    callee(arm[NR - 2]) == callee(line) && arm[NR - 4] != "else")
			printf "%s:%d: both arms call %s: two short exclusive calls are a ternary\n", f, NR - 3, callee(line)
		prev = line
	}' "$file"
done

