#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Code lives and installs where it runs (AGENTS.md, "Layout"): what runs in the kernel comes from lib/,
# examples/, tests/, autogen/ and the root files the table lists, and installs under /lib/modules/lua/,
# where the kernel's require reads; what runs in the CLI installs where the host's Lua finds it. The luaebpf
# compiler, which runs only in the CLI's Lua, reached review after review at the root of the tree,
# installing into the kernel's script tree.
# Names a top-level directory of the tree the Layout table of AGENTS.md does not list, and a file the
# Makefile installs into SCRIPTS_INSTALL_PATH, or into a variable it defines over it, from outside the trees
# that run in the kernel; exits 1 when it names one. Run from the top of the tree.
#
# Usage: bash tools/checks/layout.sh

agents=AGENTS.md
makefile=Makefile
kernel='^(lib|examples|tests|autogen)/'
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

# the kernel's script tree and every variable the Makefile defines over it
trees='\$\{SCRIPTS_INSTALL_PATH\}'
for var in $(sed -nE 's/^([A-Za-z_]+)[[:space:]]*:?=[[:space:]]*\$\{SCRIPTS_INSTALL_PATH\}.*/\1/p' "$makefile"); do
	trees="$trees|\\\$\\{$var\\}"
done

# the sources of each install into those trees, a token with no variable in it to read
sources() {
	sed -nE 's/.*INSTALL_LUA,([^,]*),.*/\1/p' <<< "$1"
	grep -q 'INSTALL_LUA' <<< "$1" && return
	sed -E 's/.*\$\{INSTALL\}//' <<< "$1" | tr ' \t' '\n\n' | grep -vE '^(-.*|[0-9]+|)$' | sed '$d'
}

while IFS=: read -r line text; do
	for source in $(sources "$text"); do
		case "$source" in
		\$*) continue ;;
		esac
		grep -qE "$kernel" <<< "$source" && continue
		printf '%s\n' "$listed" | grep -qxF "$source" && continue
		echo "$makefile:$line: installs $source into the kernel's script tree, from outside the trees that run in the kernel"
		status=1
	done
done < <(grep -nE '\$\{INSTALL\}|INSTALL_LUA,' "$makefile" | grep -E "$trees")

exit $status

