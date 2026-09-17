#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests a map whose value spec is a struct codec, which a compiled function reads a field at a
# time rather than as one number.
#   - one field of every width and signedness, with a gap the codec reads as padding: the case
#     seeds the value with `bpftool map update` and each program returns one field, so a wrong
#     offset, width or sign extension changes the number
#   - a layout `luaebpf.vmlinux` read out of the running kernel's BTF as the value spec, seeded
#     with an IPv4 header: that ties the reader to the map path, since a field read at a wrong
#     offset answers a different byte of the same twenty
#   - a write to a field, and an assignment of the whole value, are refused as the read-only
#     thing a struct value is in this phase; a field the codec does not carry, a field whose
#     width no eBPF load covers, and a value spec that is neither a format nor a codec, are
#     refused too
#   - a field read through a register two struct maps merge into is refused: a join drops the
#     map, and the layout the field would be read at is that map's
# The body computes what each program owes with the same codec it declared the map with, so the
# numbers in the oracle are the codec's reading of the bytes the case seeded.
#
# Usage: sudo bash tests/luaebpf/struct.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 8

ROWS=

output=$(luaebpf_compile struct) || { comment "$output"; fail "luaebpf: struct.bpf.lua did not compile"; }
ROWS="$LUAEBPF_WORK/rows.txt"

output=$(luaebpf_loadall struct) || { comment "$output"; fail "luaebpf: the field reads did not verify"; }
ktap_pass "luaebpf: every struct field row verifies"

while IFS=$'\t' read -r kind name key value; do
	[ "$kind" = seed ] || continue
	bpftool map update pinned "$LUAEBPF_MAPS/$name" key $key value $value \
		|| fail "luaebpf: the shell could not seed $name"
done < "$ROWS"

read=$(while IFS=$'\t' read -r kind name value; do
	[ "$kind" = expect ] && echo "$name $(luaebpf_verdict "$name" frame)"
done < "$ROWS")
rm -rf "$LUAEBPF_PINS"

owed=$(awk -F'\t' '$1 == "expect" {print $2, $3}' "$ROWS")
diff <(echo "$read") <(echo "$owed") > "$LUAEBPF_WORK/read.diff"
[ -s "$LUAEBPF_WORK/read.diff" ] && { comment "$(cat "$LUAEBPF_WORK/read.diff")";
	fail "luaebpf: a struct field answered something other than the codec's reading of it"; }
ktap_pass "luaebpf: every field of a struct value reads what its codec reads off the same bytes"

# every row is one program file declaring a map with a struct value, so only the body differs
row() {
	local name="$1" line="$2" message="$3" body="$4"
	{
		echo 'local map = require("bpf.map")'
		echo 'local struct = require("struct")'
		echo 'local xdp = require("bpf.xdp")'
		echo ''
		echo 'local codec = struct{size = 4, fields = {{name = "n", offset = 0, size = 4, signed = false}}}'
		echo 'local records = map.hash("records", {key = "I4", value = codec, entries = 8})'
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

row fieldwrite 11 "a struct map value is read-only in a compiled function" \
	$'\tlocal v = records[1]\n\tif v then\n\t\tv.n = 1\n\tend\n\treturn 0'
row valuewrite 9 "a struct map value is read-only in a compiled function" \
	$'\trecords[1] = 5\n\treturn 0'
row nofield 11 "a map value has no field 'missing'" \
	$'\tlocal v = records[1]\n\tif v then\n\t\treturn v.missing\n\tend\n\treturn 0'

cat > "$LUAEBPF_WORK/oddfield.bpf.lua" <<'LUA'
local map = require("bpf.map")
local struct = require("struct")
local xdp = require("bpf.xdp")

local codec = struct{size = 4, fields = {{name = "n", offset = 0, size = 3, signed = false}}}
local records = map.hash("records", {key = "I4", value = codec, entries = 8})

return xdp.program(function(ctx)
	return 0
end)
LUA
output=$(luaebpf_refuses oddfield "a map reads 1, 2, 4 or 8 bytes at a time, not 3") \
	|| { comment "$output"; fail "luaebpf: a field no eBPF load covers is not refused"; }
ktap_pass "luaebpf: a struct field no eBPF load covers is refused"

cat > "$LUAEBPF_WORK/badvalue.bpf.lua" <<'LUA'
local map = require("bpf.map")
local xdp = require("bpf.xdp")

local records = map.hash("records", {key = "I4", value = {}, entries = 8})

return xdp.program(function(ctx)
	return 0
end)
LUA
output=$(luaebpf_refuses badvalue "a map value spec packs one value or is a struct codec") \
	|| { comment "$output"; fail "luaebpf: a value spec that is neither a format nor a codec is not refused"; }
ktap_pass "luaebpf: a value spec that is neither a format nor a codec is refused"

# each lookup is narrowed inside its own arm, so what merges is two struct values rather than
# two lookups, and the refusal comes from the field read
cat > "$LUAEBPF_WORK/twocodecs.bpf.lua" <<'LUA'
local map = require("bpf.map")
local struct = require("struct")
local xdp = require("bpf.xdp")

local first = struct{size = 4, fields = {{name = "n", offset = 0, size = 4, signed = false}}}
local second = struct{size = 4, fields = {{name = "m", offset = 0, size = 4, signed = false}}}
local ones = map.hash("ones", {key = "I4", value = first, entries = 8})
local twos = map.hash("twos", {key = "I4", value = second, entries = 8})

return xdp.program(function(ctx)
	local p = ctx:packet()
	local v
	if p:getbyte(0) == 255 then
		local a = ones[1]
		if a then v = a else return 0 end
	else
		local b = twos[1]
		if b then v = b else return 0 end
	end
	return v.n
end)
LUA
output=$(luaebpf_refuses twocodecs "twocodecs.bpf.lua:20: a map value here comes from more than one map") \
	|| { comment "$output"; fail "luaebpf: a field of a value two struct maps merge into is not refused"; }
ktap_pass "luaebpf: a field read through a value two struct maps merge into is refused with its line"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

