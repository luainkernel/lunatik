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
#     to seed, the programs to run and the bytes to expect, from the same constants and the same
#     specs the programs were compiled against
#   - a key spec that packs more than one value, one Lua can size but not read back, one whose
#     width no eBPF load covers, one in a byte order no eBPF load takes, a count of entries the
#     object cannot carry, a name BTF cannot spell, an array keyed by anything but four bytes, a
#     map declared under a name already taken, a constructor called without a name, and a value
#     that is not a number, are refused
#
# Usage: sudo bash tests/luaebpf/mapset.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 12

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

while IFS=$'\t' read -r kind a b c; do
	case "$kind" in
	seed) bpftool map update pinned "$LUAEBPF_MAPS/$a" key $b value $c \
		|| fail "luaebpf: the shell could not seed $a" ;;
	run) luaebpf_verdict "$a" frame > /dev/null ;;
	esac
done < "$ROWS"

kept=$(while IFS=$'\t' read -r kind a b c; do
	[ "$kind" = check ] && echo "$a $b: $(held "$a" "$b")"
done < "$ROWS")
rm -rf "$LUAEBPF_PINS"

owed=$(awk -F'\t' '$1 == "check" {print $2, $3 ": " $4}' "$ROWS")
diff <(echo "$kept") <(echo "$owed") > "$LUAEBPF_WORK/kept.diff"
[ -s "$LUAEBPF_WORK/kept.diff" ] && { comment "$(cat "$LUAEBPF_WORK/kept.diff")";
	fail "luaebpf: a map does not hold what the programs wrote into it"; }
ktap_pass "luaebpf: an update and a delete from a compiled program are what the map keeps"

# every row is one program file whose body declares a map, so only that declaration differs
row() {
	local name="$1" message="$2" body="$3"
	{
		echo 'local map = require("bpf.map")'
		echo 'local xdp = require("bpf.xdp")'
		echo ''
		echo "$body"
		echo ''
		echo 'return xdp.program(function(ctx)'
		echo '	return 0'
		echo 'end)'
	} > "$LUAEBPF_WORK/$name.bpf.lua"
	local output
	output=$(luaebpf_refuses "$name" "$message")
	if [ $? -ne 0 ]; then
		comment "$output"
		ktap_fail "luaebpf: $name"
	else
		ktap_pass "luaebpf: $name is refused with its message"
	fi
}

row widekey "a map key spec packs one value" \
	'local wide = map.hash("wide", {key = "I4I4", value = "I4", entries = 4})'
spec='{key = "I4", value = "I4", entries = 4}'
row twice "'flows' is declared twice" \
	"local a = map.hash(\"flows\", $spec)"$'\n'"local b = map.hash(\"flows\", $spec)"
row noname "map.hash takes a name and a spec" \
	'local anonymous = map.hash({key = "I4", value = "I4", entries = 4})'
row widevalue "a map value spec packs one value or is a struct codec" \
	'local wide = map.hash("wide", {key = "I4", value = "I16", entries = 4})'
row narrow "a map reads 1, 2, 4 or 8 bytes at a time, not 3" \
	'local odd = map.hash("odd", {key = "I4", value = "I3", entries = 4})'
row noentries "a map holds between 1 and 4294967295 entries, not 0" \
	'local empty = map.hash("empty", {key = "I4", value = "I4", entries = 0})'
row badname "a map name is a C identifier, not '9flows'" \
	'local digit = map.hash("9flows", {key = "I4", value = "I4", entries = 4})'
row arraykey "an array map is keyed by 4 bytes, not 8" \
	'local counts = map.array("counts", {key = "I8", value = "I4", entries = 4})'
row byteorder "a map is read in the host's byte order, not '>I4'" \
	'local wire = map.hash("wire", {key = ">I4", value = "I4", entries = 4})'

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

