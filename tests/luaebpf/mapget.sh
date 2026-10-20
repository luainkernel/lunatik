#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests declaring and reading a map a program file declares. The object carries the map as a
# BTF-defined one, so `bpftool prog loadall ... pinmaps` creates and pins it, as the type its
# constructor names, and the shell reads and writes it from outside, as a kernel script does
# through the pin.
#   - every program is run twice, against the empty maps and against maps the case seeded with
#     `bpftool map update`; the program file's body writes what each owes either way, from the
#     same constants and the same key and value specs the programs were compiled against
#   - a key present in a hash and in an LRU hash, a key absent from it, a key the program
#     computed from the packet rather than one the compiler folded in, an array index in range,
#     where a lookup answers a pointer to zeros and Lua reads 0 as true, one past the array's
#     entries, where it answers NULL, a lookup whose own pointer is spilled to the frame,
#     which is where the verifier has to narrow it, and a register nil on the path that skips
#     the lookup, which the test narrows as it narrows the lookup, run on a frame that takes the
#     lookup and on one that skips it, where the nil answers as a miss does
#   - a key the program computes outside what its spec packs, unsigned and signed, takes the
#     default verdict, where the kernel's bpf.map raises in string.pack: each one's low bytes are
#     a seeded key, so a key stored truncated answers the seeded value instead; and a negative
#     key a signed spec packs finds what the shell seeded under it
#   - a lookup used as a number with no test, a lookup keyed by a string, and a method call on
#     a lookup, which no map value carries, are refused with their messages and lines
#   - a register two lookups in different maps merge into is refused where it is tested, whether
#     the paths meet at a branch or through a loop's back edge, which arrives after the test is
#     walked: a join keeps the type and drops the map the paths disagree on, and the spec the
#     value is read with is the map's
#   - a declaration the object cannot carry is refused at its line: a key spec that packs more
#     than one value or pads its integer, a value spec Lua can size but not read back, one that
#     reads a float, a width no eBPF load covers, a count of entries max_entries cannot hold, a
#     name BTF cannot spell, an array keyed by anything but four bytes, a byte order no eBPF load
#     takes, a name declared twice, and a constructor called without a name
#
# Usage: sudo bash tests/luaebpf/mapget.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 19

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
for map in flows:hash hits:array recent:lru_hash; do
	bpftool map show pinned "$LUAEBPF_MAPS/${map%%:*}" | grep -q "^[0-9]*: ${map#*:} " \
		|| fail "luaebpf: ${map%%:*} is not pinned as the ${map#*:} it was declared"
done
ktap_pass "luaebpf: every map row verifies, and its map is created and pinned as the type it was declared"

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

# the same two maps meeting through a loop's back edge, which reaches the test after it was walked
cat > "$LUAEBPF_WORK/backedge.bpf.lua" <<'LUA'
local map = require("bpf.map")
local xdp = require("bpf.xdp")

local wide = map.hash("wide", {key = "I4", value = "I8", entries = 8})
local thin = map.hash("thin", {key = "I4", value = "I1", entries = 8})

return xdp.program(function(_)
	local v = wide[1]
	for _ = 1, 3 do
		if v then
			return v
		end
		v = thin[1]
	end
	return 0
end)
LUA
output=$(luaebpf_refuses backedge "backedge.bpf.lua:10: a map value here comes from more than one map") \
	|| { comment "$output"; fail "luaebpf: a value a back edge merges from two maps is not refused"; }
ktap_pass "luaebpf: a value a back edge merges from two maps is refused with its line"

# every row is one program file whose body declares a map, so only that declaration differs
declared() {
	local name="$1" line="$2" message="$3" body="$4"
	{
		echo 'local map = require("bpf.map")'
		echo 'local xdp = require("bpf.xdp")'
		echo ''
		echo "$body"
		echo ''
		echo 'return xdp.program(function(_)'
		echo '	return 0'
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

spec='{key = "I4", value = "I4", entries = 4}'
declared widekey 4 "a map key spec packs one value" \
	'local wide = map.hash("wide", {key = "I4I4", value = "I4", entries = 4})'
declared paddedkey 4 "a map key spec packs one value" \
	'local padded = map.hash("padded", {key = "I2xx", value = "I4", entries = 4})'
declared widevalue 4 "a map value spec packs one value" \
	'local wide = map.hash("wide", {key = "I4", value = "I16", entries = 4})'
declared floatvalue 4 "a map value spec packs one value" \
	'local real = map.hash("real", {key = "I4", value = "d", entries = 4})'
declared narrow 4 "a map reads 1, 2, 4 or 8 bytes at a time, not 3" \
	'local odd = map.hash("odd", {key = "I4", value = "I3", entries = 4})'
declared noentries 4 "a map holds between 1 and 4294967295 entries, not 0" \
	'local empty = map.hash("empty", {key = "I4", value = "I4", entries = 0})'
declared badname 4 "a map name is a C identifier, not '9flows'" \
	"local digit = map.hash(\"9flows\", $spec)"
declared arraykey 4 "an array map is keyed by 4 bytes, not 8" \
	'local counts = map.array("counts", {key = "I8", value = "I4", entries = 4})'
declared byteorder 4 "a map is read in the host's byte order, not '>I4'" \
	'local wire = map.hash("wire", {key = ">I4", value = "I4", entries = 4})'
declared twice 5 "'flows' is declared twice" \
	"local a = map.hash(\"flows\", $spec)"$'\n'"local b = map.hash(\"flows\", $spec)"
declared noname 4 "map.hash takes a name and a spec" "local anonymous = map.hash($spec)"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

