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
#     spec, written and deleted, return XDP_ABORTED, where the kernel's bpf.map raises in
#     string.pack: each one's low bytes name an entry the case then finds untouched, which a
#     store that truncated would have written or removed; and a negative value a signed spec
#     packs is kept as its two bytes
#   - a write the map refuses returns XDP_ABORTED, where the kernel's bpf.map raises: an
#     update at an index past the array's entries, a second key in a hash of one entry, whose
#     first entry is kept, and a delete from an array, whose entry is kept
#   - one run of each of those stops, in the object loaded again, whose maps and rate limit start
#     anew, writes into the trace ring at the write's file and line, once and alone,
#     string.pack's "unsigned overflow" or "integer overflow" for a value or a key past its spec,
#     and "the map '<name>' refused the update" or "the delete" for a write the map refuses, whose
#     errno only the kernel knows
#   - a value that is not a number is refused with its line
#
# Usage: sudo bash tests/luaebpf/mapset.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 5

UNSIGNED="unsigned overflow" # string.pack, lua/lstrlib.c
SIGNED="integer overflow"
UPDATE="refused the update"
DELETE="refused the delete"
ROWS=

# the line each write that stops logs, in the object loaded again
writes() {
	rm -rf "$LUAEBPF_PINS"; mkdir -p "$LUAEBPF_PINS"
	luaebpf_loadall mapset > /dev/null || { echo "the map writes did not verify again"; return; }
	luaebpf_logs widevalue "$(luaebpf_logline mapset "flows[WIDE] = p:getbyte(0)" "$UNSIGNED")" frame
	luaebpf_logs widekey "$(luaebpf_logline mapset "flows[p:getbyte(0) << WORD | WIDE]" "$UNSIGNED")" frame
	luaebpf_logs widedelete "$(luaebpf_logline mapset "flows[p:getbyte(0) << WORD | KEPT]" "$UNSIGNED")" frame
	luaebpf_logs narrowvalue "$(luaebpf_logline mapset "levels[2] = -p:getbyte(0) - SPAN" "$SIGNED")" frame
	luaebpf_logs overflow "$(luaebpf_logline mapset "hits[p:getbyte(0)] = COUNT" "the map 'hits' $UPDATE")" frame
	luaebpf_logs full "$(luaebpf_logline mapset "one[DELETED] = STORED" "the map 'one' $UPDATE")" frame
	luaebpf_logs arraydelete "$(luaebpf_logline mapset "hits[INDEX] = nil" "the map 'hits' $DELETE")" frame
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
	[ "$kind" = check ] && echo "$a $b: $(luaebpf_lookup "$a" "$b")"
done < "$ROWS")
rm -rf "$LUAEBPF_PINS"

owed=$(awk -F'\t' '$1 == "run" {print $2, $3}' "$ROWS")
diff <(echo "$ran") <(echo "$owed") > "$LUAEBPF_WORK/ran.diff"
[ -s "$LUAEBPF_WORK/ran.diff" ] && { comment "$(cat "$LUAEBPF_WORK/ran.diff")";
	fail "luaebpf: a map write answered another verdict than the one it owes"; }
ktap_pass "luaebpf: a write past its spec returns XDP_ABORTED, and the rest answer theirs"

owed=$(awk -F'\t' '$1 == "check" {print $2, $3 ": " $4}' "$ROWS")
diff <(echo "$kept") <(echo "$owed") > "$LUAEBPF_WORK/kept.diff"
[ -s "$LUAEBPF_WORK/kept.diff" ] && { comment "$(cat "$LUAEBPF_WORK/kept.diff")";
	fail "luaebpf: a map does not hold what the programs wrote into it"; }
ktap_pass "luaebpf: an update and a delete from a compiled program are what the map keeps"

luaebpf_logcase "a map write that stops logs the error at its file and line, once" writes

cat > "$LUAEBPF_WORK/boolvalue.bpf.lua" <<'LUA'
local map = require("bpf.map")
local xdp = require("bpf.xdp")
local action = require("linux.xdp").action

local flows = map.hash("flows", {key = "I4", value = "I4", entries = 4})

return xdp.program(function(ctx)
	flows[1] = true
	return 0
end, {default = action.PASS})
LUA
output=$(luaebpf_refuses boolvalue "boolvalue.bpf.lua:8: a map value is a number here") \
	|| { comment "$output"; fail "luaebpf: a boolean map value is not refused"; }
ktap_pass "luaebpf: a map value that is not a number is refused with its line"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

