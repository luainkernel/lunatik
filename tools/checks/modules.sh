#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Sourced by examples-touched.sh and consumers.sh, which name the scripts a change reaches: the Lua
# modules a changed file defines, and those a script reaches them through without requiring them, a
# library that requires one, as netlink reaches netlink.rt.route, and a binding that hands its objects
# to a callback, as netfilter and tc hand an skb (#1264). Run from the top of the tree.

CHECK_BASE=${CHECK_BASE:-origin/master}

# <file> as the change leaves it, or as the base has it when the change deletes it
head_or_base() {
	if [ -f "$1" ]; then cat "$1"; else git show "$CHECK_BASE:$1" 2>/dev/null; fi
}

# the linux.* tables autogen builds from the specs a change to autogen/specs.lua touches, or from
# every spec when the change is to the generator, autogen.lua
linux_tables() {
	local changed=""
	[ "$1" = autogen/specs.lua ] && changed=$(git diff -U0 "$CHECK_BASE" -- "$1" 2>/dev/null |
		sed -nE 's/^@@ -[0-9,]+ \+([0-9]+)(,([0-9]+))? @@.*/\1:\3/p' | paste -sd' ')
	head_or_base autogen/specs.lua | awk -v changed="$changed" -v every="$([ "$1" = autogen.lua ] && echo 1)" '
	BEGIN {
		n = split(changed, hunks, " ")
		for (i = 1; i <= n; i++) {
			split(hunks[i], h, ":")
			for (l = h[1]; l < h[1] + (h[2] == "" || h[2] == 0 ? 1 : h[2]); l++)
				hit[l] = 1
		}
	}
	/^\t\{/ { spec++ }
	match($0, /module = "[^".]+/) { table[spec] = substr($0, RSTART + 10, RLENGTH - 10) }
	hit[NR] { touched[spec] = 1 }
	END {
		for (s = 1; s <= spec; s++)
			if ((every || touched[s]) && table[s] != "")
				print "linux." table[s]
	}'
}

# the modules <file> defines, one a line: a binding by its LUNATIK_NEWLIB name, with the dot require
# spells for its underscore, a library by its path, the core's files by lunatik
defined_modules() {
	case "$1" in
		lib/luacrypto_*.c) echo crypto ;;
		lib/lua*.c) head_or_base "$1" | sed -nE 's/^(LUNATIK|LUAKFUNC)_NEWLIB\(([a-z0-9_]+),.*/\2/p;
			s/^LUNATIK_OPENER\(([a-z0-9_]+)\);.*/\1/p' | head -1 | tr _ . ;;
		lib/*.lua) local m=${1#lib/}; m=${m%.lua}; echo "${m//\//.}" ;;
		lunatik.h|lunatik_*.[ch]) echo lunatik ;;
		autogen.lua|autogen/specs.lua) linux_tables "$1" ;;
	esac
}

# queues <file> for reaching_modules unless it is already seen, through that caller's own locals
reach() {
	case "$seen" in *" $1 "*) return ;; esac
	seen="$seen$1 "
	queue+=("$1")
}

# the modules a script reaches what <file> defines through, those included, one a line
reaching_modules() {
	local queue=("$1") seen=" $1 " file mod next
	while [ ${#queue[@]} -gt 0 ]; do
		file=${queue[0]}
		queue=("${queue[@]:1}")
		for mod in $(defined_modules "$file"); do
			echo "$mod"
			for next in $(grep -rlE "require\(\"${mod//./\\.}\"\)" lib --include='*.lua' 2>/dev/null); do
				reach "$next"
			done
		done
		case "$file" in lib/lua*.c) ;; *) continue ;; esac
		for next in $(grep -lwE "$(basename "$file" .c)_(new|attach)" lib/lua*.c 2>/dev/null); do
			reach "$next"
		done
	done | sort -u
}

