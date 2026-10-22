#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Code lives and installs where it runs (AGENTS.md, "Layout"): what runs in the kernel comes from lib/,
# examples/, tests/, autogen/ and the root files the table lists, and installs under /lib/modules/lua/,
# where the kernel's require reads; what runs in the CLI installs where the host's Lua finds it; what both
# run comes from common/ and installs on both sides. The luaebpf compiler, which runs only in the CLI's
# Lua, reached review after review at the root of the tree, installing into the kernel's script tree, and
# once in bin/ it required class from lib/ through a copy make install put in its own root, from a package
# at bin/luaebpf/luaebpf/.
# Names a top-level directory of the tree the Layout table of AGENTS.md does not list, a tracked directory
# named as the directory that holds it, a file the Makefile installs into SCRIPTS_INSTALL_PATH, or into a
# variable it defines over it, from outside the trees that run in the kernel, and a file it installs or
# links into the host's Lua path, LUA_PATH, LUA_CPATH or a variable it defines over them, from a tree that
# runs only in the kernel; exits 1 when it names one. Run from the top of the tree.
#
# Usage: bash tools/checks/layout.sh

agents=AGENTS.md
makefile=Makefile
kernel='^(lib|examples|tests|autogen|common)/'
kernelonly='^(lib|examples|tests)/'
status=0
set -f # a source is read as the Makefile spells it, a glob included

# the paths the first column of the Layout table lists
listed=$(awk -F'|' '/^## Layout/ {on = 1; next} on && /^## / {exit} on {print $2}' "$agents" |
	grep -o '`[^`]*`' | tr -d '`')

for dir in $(git ls-files | cut -d/ -f1 | sort -u); do
	[ -d "$dir" ] || continue
	printf '%s\n' "$listed" | grep -q "^$dir/" && continue
	echo "$dir/: a top-level directory the Layout table of $agents does not list; give it a row that says what lives there and where it runs"
	status=1
done

for dir in $(git ls-files | awk -F/ '{p = $1; for (i = 2; i < NF; i++) {p = p "/" $i; if ($i == $(i - 1)) print p "/"}}' | sort -u); do
	echo "$dir: a directory named as the directory that holds it; name it for what it holds"
	status=1
done

# a pattern matching each variable given and every variable the Makefile defines over one of them
trees() {
	local re var
	re=$(printf '|\\$\\{%s\\}' "$@")
	re=${re#|}
	for var in $(sed -nE "s/^([A-Za-z_]+)[[:space:]]*:?=[[:space:]]*($re).*/\1/p" "$makefile"); do
		re="$re|\\\$\\{$var\\}"
	done
	echo "$re"
}

# the sources of an install or a link, a token with no variable in it to read
sources() {
	sed -nE 's/.*INSTALL_LUA,([^,]*),.*/\1/p' <<< "$1"
	grep -q 'INSTALL_LUA' <<< "$1" && return
	sed -E 's/.*\$\{(INSTALL|LN)\}//' <<< "$1" | tr ' \t' '\n\n' | grep -vE '^(-.*|[0-9]+|)$' | sed '$d'
}

# the line and each source of every install or link into the trees <pattern> matches
installs() {
	local line text source
	grep -nE '\$\{(INSTALL|LN)\}|INSTALL_LUA,' "$makefile" | grep -E "$1" | while IFS=: read -r line text; do
		for source in $(sources "$text"); do
			case "$source" in
			\$*) continue ;;
			esac
			echo "$line $source"
		done
	done
}

while read -r line source; do
	grep -qE "$kernel" <<< "$source" && continue
	printf '%s\n' "$listed" | grep -qxF "$source" && continue
	echo "$makefile:$line: installs $source into the kernel's script tree, from outside the trees that run in the kernel"
	status=1
done < <(installs "$(trees SCRIPTS_INSTALL_PATH)")

while read -r line source; do
	grep -qE "$kernelonly" <<< "$source" || continue
	echo "$makefile:$line: puts $source in the host's Lua path, from a tree that runs only in the kernel; what both sides run lives in common/"
	status=1
done < <(installs "$(trees LUA_PATH LUA_CPATH)")

exit $status

