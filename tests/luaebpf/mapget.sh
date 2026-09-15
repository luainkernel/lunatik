#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests reading a map a program file declares. The object carries the map as a BTF-defined one,
# so `bpftool prog loadall ... pinmaps` creates and pins it and the shell reads and writes it
# from outside, which is what the loader and a kernel script will do later.
#   - every program is run twice, against the empty maps and against maps the case seeded with
#     `bpftool map update`; the program file's body writes what each owes either way, from the
#     same constants and the same key and value specs the programs were compiled against
#   - a key present in a hash, a key absent from it, a key the program computed from the packet
#     rather than one the compiler folded in, an array index in range, where a lookup answers a
#     pointer to zeros and Lua reads 0 as true, one past the array's entries, where it answers
#     NULL, and a lookup whose own pointer is spilled to the frame, which is where the verifier
#     has to narrow it
#   - a lookup used as a number with no test, a lookup keyed by a string, and a method call on
#     a lookup, which no map value carries, are refused with their messages and lines
#   - a register two lookups in different maps merge into is refused where it is tested: a join
#     keeps the type and drops the map, and the spec the value is read with is the map's
#
# Usage: sudo bash tests/luaebpf/mapget.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 7

ROWS=

# what every program answered, one "name value" line per row
answers() {
	local name before after
	while IFS=$'\t' read -r kind name before after; do
		[ "$kind" = expect ] || continue
		echo "$name $(luaebpf_verdict "$name" frame)"
	done < "$ROWS"
}

# what the body says they owe, with the empty maps or the seeded ones
owed() {
	awk -v column="$1" '$1 == "expect" {print $2, $column}' "$ROWS"
}

output=$(luaebpf_compile mapget) || { comment "$output"; fail "luaebpf: mapget.bpf.lua did not compile"; }
ROWS="$LUAEBPF_WORK/rows.txt"

output=$(luaebpf_loadall mapget) || { comment "$output"; fail "luaebpf: the map reads did not verify"; }
ktap_pass "luaebpf: every map row verifies, and its map is created and pinned"

empty=$(answers)
while IFS=$'\t' read -r kind name key value; do
	[ "$kind" = seed ] || continue
	bpftool map update pinned "$LUAEBPF_MAPS/$name" key $key value $value \
		|| fail "luaebpf: the shell could not seed $name"
done < "$ROWS"
seeded=$(answers)
rm -rf "$LUAEBPF_PINS"

diff <(echo "$empty") <(owed 3) > "$LUAEBPF_WORK/empty.diff"
[ -s "$LUAEBPF_WORK/empty.diff" ] && { comment "$(cat "$LUAEBPF_WORK/empty.diff")";
	fail "luaebpf: a lookup in an empty map answered the wrong number"; }
ktap_pass "luaebpf: a lookup in an empty map takes the branch the program wrote for it"

diff <(echo "$seeded") <(owed 4) > "$LUAEBPF_WORK/seeded.diff"
[ -s "$LUAEBPF_WORK/seeded.diff" ] && { comment "$(cat "$LUAEBPF_WORK/seeded.diff")";
	fail "luaebpf: a lookup answered something other than what the shell seeded"; }
ktap_pass "luaebpf: a lookup answers the value the shell wrote into the map"

# every row is one compiled function over the same map, so only the body differs
row() {
	local name="$1" line="$2" message="$3" body="$4"
	{
		echo 'local map = require("bpf.map")'
		echo 'local xdp = require("bpf.xdp")'
		echo ''
		echo 'local flows = map.hash("flows", {key = "I4", value = "I4", entries = 8})'
		echo ''
		echo 'return xdp.program(function(ctx)'
		echo "$body"
		echo 'end)'
	} > "$LUAEBPF_WORK/$name.bpf.lua"
	local output
	output=$(luaebpf_refuses "$name" "$name.bpf.lua:$line: $message")
	if [ $? -ne 0 ]; then
		comment "$output"
		ktap_fail "luaebpf: $name"
	else
		ktap_pass "luaebpf: $name is refused with its message and line"
	fi
}

row untested 8 "'flows' may be nil here; test it first" $'\tlocal v = flows[1]\n\treturn v + 1'
row stringkey 7 "a map key is a number here" $'\tlocal v = flows.first\n\treturn v'
row valuemethod 8 "the map value has no method 'foo'" $'\tlocal v = flows[1]\n\tlocal n = v:foo()\n\treturn n'

# two maps of different value widths, so the spec the merged value would be read with decides
# how many bytes the load takes
cat > "$LUAEBPF_WORK/twomaps.bpf.lua" <<'LUA'
local map = require("bpf.map")
local xdp = require("bpf.xdp")

local wide = map.hash("wide", {key = "I4", value = "I8", entries = 8})
local thin = map.hash("thin", {key = "I4", value = "I1", entries = 8})

return xdp.program(function(ctx)
	local p = ctx:packet()
	local v
	if p:getbyte(0) == 255 then
		v = wide[1]
	else
		v = thin[1]
	end
	if v then
		return v
	end
	return 0
end)
LUA
output=$(luaebpf_refuses twomaps "twomaps.bpf.lua:15: a map value here comes from more than one map") \
	|| { comment "$output"; fail "luaebpf: a value two maps merge into is not refused"; }
ktap_pass "luaebpf: a value two maps merge into is refused with its line"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

