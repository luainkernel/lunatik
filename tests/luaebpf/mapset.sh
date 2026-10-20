#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests writing a map a program file declares. The programs run first and the shell reads the
# pinned maps afterwards, so what is asserted is what the kernel kept, not what the program
# thought it wrote.
#   - an update under a key the compiler folded in and one the program computed from the packet,
#     a delete of an entry the case seeded, a delete of a key that was never there, which Lua
#     makes a no-op of, and an update of an array entry. The program file's body writes the key
#     to seed, the programs to run with the verdict each owes, and the bytes to expect, from the
#     same constants and the same specs the programs were compiled against
#   - a value the program computes past its unsigned spec or its signed one, and a key past its
#     spec, written and deleted, take the default verdict, where the kernel's bpf.map raises in
#     string.pack: each one's low bytes name an entry the case then finds untouched, which a
#     store that truncated would have written or removed; and a negative value a signed spec
#     packs is kept as its two bytes
#   - a write the map refuses takes the default verdict, where the kernel's bpf.map raises: an
#     update at an index past the array's entries, a second key in a hash of one entry, whose
#     first entry is kept, and a delete from an array, whose entry is kept
#   - a value that is not a number is refused with its line
#
# Usage: sudo bash tests/luaebpf/mapset.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 4

ROWS=

# what the map holds under one key, as bpftool prints it, or "absent"
held() {
	local out
	out=$(bpftool map lookup pinned "$LUAEBPF_MAPS/$1" key $2 2>&1) || { echo absent; return; }
	echo "$out" | grep -oP 'value: \K.*' | sed 's/ *$//'
}

output=$(luaebpf_compile mapset) || { comment "$output"; fail "luaebpf: mapset.bpf.lua did not compile"; }
ROWS="$LUAEBPF_WORK/rows.txt"

output=$(luaebpf_loadall mapset) || { comment "$output"; fail "luaebpf: the map writes did not verify"; }
ktap_pass "luaebpf: every map write verifies"

ran=$(while IFS=$'\t' read -r kind a b c; do
	case "$kind" in
	seed) bpftool map update pinned "$LUAEBPF_MAPS/$a" key $b value $c \
		|| echo "the shell could not seed $a" ;;
	run) echo "$a $(luaebpf_verdict "$a" frame)" ;;
	esac
done < "$ROWS")

kept=$(while IFS=$'\t' read -r kind a b c; do
	[ "$kind" = check ] && echo "$a $b: $(held "$a" "$b")"
done < "$ROWS")
rm -rf "$LUAEBPF_PINS"

owed=$(awk -F'\t' '$1 == "run" {print $2, $3}' "$ROWS")
diff <(echo "$ran") <(echo "$owed") > "$LUAEBPF_WORK/ran.diff"
[ -s "$LUAEBPF_WORK/ran.diff" ] && { comment "$(cat "$LUAEBPF_WORK/ran.diff")";
	fail "luaebpf: a map write answered another verdict than the one it owes"; }
ktap_pass "luaebpf: a write past its spec takes the default verdict, and the rest answer theirs"

owed=$(awk -F'\t' '$1 == "check" {print $2, $3 ": " $4}' "$ROWS")
diff <(echo "$kept") <(echo "$owed") > "$LUAEBPF_WORK/kept.diff"
[ -s "$LUAEBPF_WORK/kept.diff" ] && { comment "$(cat "$LUAEBPF_WORK/kept.diff")";
	fail "luaebpf: a map does not hold what the programs wrote into it"; }
ktap_pass "luaebpf: an update and a delete from a compiled program are what the map keeps"

cat > "$LUAEBPF_WORK/boolvalue.bpf.lua" <<'LUA'
local map = require("bpf.map")
local xdp = require("bpf.xdp")

local flows = map.hash("flows", {key = "I4", value = "I4", entries = 4})

return xdp.program(function(ctx)
	flows[1] = true
	return 0
end)
LUA
output=$(luaebpf_refuses boolvalue "boolvalue.bpf.lua:7: a map value is a number here") \
	|| { comment "$output"; fail "luaebpf: a boolean map value is not refused"; }
ktap_pass "luaebpf: a map value that is not a number is refused with its line"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

