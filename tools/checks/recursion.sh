#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Names a recursion in the Lua the kernel links that counts no C level, so the C stack budget never
# reads it, and that the ledger below does not bound. #1669 priced a C level in bytes, read where
# LUAI_MAXCCALLS is compared and measured the stack at every check, and a recursion that compares
# nothing was invisible to both: lundump's loadFunction recursed once per nested function of a chunk,
# and lunatic compiled one nested 98 deep from valid source, past the guard page (#1775).
#
# The objects Kbuild links from lua/ are compiled with the host compiler and the configuration lunatic
# takes, and GCC's call graph (-fcallgraph-info=su) is read for its cycles, which are the recursions
# left after inlining, each with the frame of its functions on the host; a cycle with no call to
# luaE_checkcstack or luaE_incCstack counts nothing. A ledger entry says what bounds a recursion's
# depth, read in its source: one that gains no entry is bounded where it recurses or named here, and
# the review reads the bound.
#
# Runs when a path given names lua/, lunatik_conf.h or lunatik_aux.c, where the budget and what it
# counts live; needs GCC 10 or later, gawk and the lua/ submodule, and says which is missing.
#
# Usage: bash tools/checks/recursion.sh <file>...

declare -A bounded=(
	[auxsort]="recurses into the smaller half, so its depth is the log of the table's length"
	[dumpFunction]="the nesting of a function the kernel loaded, which its parser or lunatic bounded"
	[findfield]="pushglobalfuncname searches two levels"
	[lexerror]="the lexer's error path, which raises"
	[loadFunction]="the nesting of a chunk, which lunatic bounds to what the kernel undumps (#1779)"
	[match]="lstrlib's MAXCCALLS, 32 in the kernel (#1662)"
	[reallymarkobject]="an upvalue's content or a userdata's metatable, which goes on the gray list"
	[save]="the lexer's error path, which raises"
	[singlevaraux]="the functions enclosing the one parsed, whose levels the parser counted"
)

root=$(git rev-parse --show-toplevel 2> /dev/null) || exit 0
applies=false
for file in "$@"; do
	case "$file" in lua|lua/*|*/lua/*|lunatik_conf.h|lunatik_aux.c) applies=true ;; esac
done
$applies || exit 0

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
missing=""
gcc -fcallgraph-info=su -x c -c -o /dev/null -dumpbase "$tmp/probe" /dev/null 2> /dev/null ||
	missing="$missing GCC 10 or later"
command -v gawk > /dev/null || missing="$missing gawk"
[ -f "$root/lua/lundump.c" ] || missing="$missing the lua/ submodule"
if [ -n "$missing" ]; then
	echo "recursion: not run, it needs$missing"
	exit 0
fi

for object in $(grep -o 'lua/[a-z]*\.o' "$root/Kbuild"); do
	unit=$(basename "$object" .o)
	(cd "$root" && gcc -std=gnu99 -O2 -w -D_KERNEL -DLUA_USE_LINUX -I. -Ilua -fcallgraph-info=su \
		-c "lua/$unit.c" -o "$tmp/$unit.o" -dumpbase "$tmp/$unit") 2> "$tmp/$unit.err" ||
		{ echo "recursion: lua/$unit.c did not compile on the host: $(head -1 "$tmp/$unit.err")"; exit 1; }
done

ledger=$(for name in "${!bounded[@]}"; do echo "$name"; done)
cat "$tmp"/*.ci | gawk -v ledger="$ledger" '
	/^node:/ {
		match($0, /title: "([^"]*)"/, t)
		match($0, /label: "([^"]*)"/, l)
		split(l[1], parts, /\\n/)
		name[t[1]] = parts[1]
		sub(/\.(part|isra|constprop|cold)\..*$/, "", name[t[1]])
		where[t[1]] = parts[2]
		size[t[1]] = match(l[1], /([0-9]+) bytes/, b) ? b[1] : 0
		nodes[t[1]] = 1
	}
	/^edge:/ {
		match($0, /sourcename: "([^"]*)"/, s)
		match($0, /targetname: "([^"]*)"/, d)
		edges[s[1]] = edges[s[1]] " " d[1]
		nodes[d[1]] = 1
		if (s[1] == d[1])
			self[s[1]] = 1
	}
	# Tarjan: each strongly connected component with a cycle is one recursion
	function visit(v,   ws, n, i, w, members, bytes, counted, unbounded, first) {
		order[v] = low[v] = ++serial
		stack[++top] = v
		onstack[v] = 1
		n = split(edges[v], ws, " ")
		for (i = 1; i <= n; i++) {
			w = ws[i]
			if (!(w in order)) {
				visit(w)
				low[v] = low[w] < low[v] ? low[w] : low[v]
			}
			else if (onstack[w])
				low[v] = order[w] < low[v] ? order[w] : low[v]
		}
		if (low[v] != order[v])
			return
		members = ""; bytes = 0; counted = 0; unbounded = 0; i = 0
		do {
			w = stack[top--]
			onstack[w] = 0
			i++
			members = members (members == "" ? "" : ", ") name[w]
			bytes += size[w]
			if (edges[w] ~ /(^| )(luaE_checkcstack|luaE_incCstack)( |$)/)
				counted = 1
			if (!(name[w] in known))
				unbounded = 1
			first = w
		} while (w != v)
		if ((i > 1 || self[v]) && !counted && unbounded)
			printf "%s: %s recurses, %d bytes a level on the host, and nothing on its cycle counts a C level: bound it where it recurses, or name its bound in the ledger of tools/checks/recursion.sh\n", where[v], members, bytes
	}
	END {
		split(ledger, names, "\n")
		for (i in names)
			known[names[i]] = 1
		for (v in nodes)
			if (!(v in order))
				visit(v)
	}' | sort | tee "$tmp/found"
[ ! -s "$tmp/found" ]

