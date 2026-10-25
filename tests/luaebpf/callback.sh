#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests a compiled program's call into the kernel Lua runtime, whose answer the program returns.
# callback.bpf.lua declares four XDP programs over one runtime, and callback.lua is that runtime,
# run in softirq: its callback answers PASS for no argument, DROP for MAGIC alone or for WRONG then
# MAGIC, and ABORTED for anything else, and each program returns TX where the call answered nil,
# a verdict the callback never returns. The object is loaded with bpftool, so the runtime is the
# only thing `lunatik run` starts.
#   - the name the program spelled reaches the callback, which read all eight bytes of the
#     argument: MAGIC's low 32 bits are not MAGIC
#   - a call with no argument hands the callback an empty argument
#   - another argument reaches the callback's rejection, so a DROP above is the argument's
#   - two arguments arrive as two words, in the order the call wrote them
#   - the answer read before a test, as a number, compared by '==' with a number and by '<',
#     returned, negated, copied by 'or' and tested where a join met it with another value; an argument
#     that is not a number, a call from a function the program calls, a call from a program that
#     declares no context, a runtime declared with no name and one whose name the frame cannot hold
#     are refused with their messages and lines
#   - one runtime called from an XDP and a TC program names each program type's kfunc in the
#     object: the kfunc a call lowers to is the program's
#   - the key the call stores reads back as the runtime's name from an object of either byte order,
#     as llvm-objdump disassembles it for that order; skipped where llvm-objdump is not installed
# The runtime cases skip where the kernel publishes no BTF for luaxdp.
#
# Usage: sudo bash tests/luaebpf/callback.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

LUAEBPF_RUNS="callback"
trap cleanup EXIT

SCRIPT=tests/luaebpf/callback
ABORTED=0
DROP=1
PASS=2
CALLS=4
REFUSALS=12

luaebpf_start $((CALLS + 1 + REFUSALS + 2))

# every row of a refusal is one program over one runtime, so only the body and the parameter list
# the program declares differ
row() {
	local name="$1" line="$2" message="$3" body="$4" params="${5-ctx}" runtime="${6-\"$SCRIPT\"}" output
	{
		echo 'local xdp = require("bpf.xdp")'
		echo ''
		echo "local lua = xdp.runtime($runtime)"
		echo ''
		echo 'local function helper(n)'
		echo $'\tlocal v = lua(n)\n\tif v then\n\t\treturn v\n\tend\n\treturn 0'
		echo 'end'
		echo ''
		echo "return xdp.program(function($params)"
		echo "$body"
		echo 'end)'
	} > "$LUAEBPF_WORK/$name.bpf.lua"
	output=$(luaebpf_refuses "$name" "$name.bpf.lua:$line: $message")
	if [ $? -ne 0 ]; then
		comment "$output"
		ktap_fail "luaebpf: $name"
	else
		ktap_pass "luaebpf: $name is refused with its message and line"
	fi
}

# the runtime's name as each key the object stores reads in <order>, one a line
keys() {
	local triple=bpfel
	[ "$1" = big ] && triple=bpfeb
	llvm-objdump --triple="$triple" -d --no-show-raw-insn "$LUAEBPF_WORK/$1/callback.bpf.o" \
		| grep -oP 'r1 = \K-?[0-9]+' | ORDER="$1" lua5.5 -e '
			local order = os.getenv("ORDER") == "big" and ">i8" or "<i8"
			local words = {}
			for word in io.lines() do
				table.insert(words, string.pack(order, tonumber(word)))
			end
			for key in table.concat(words):gmatch("[^%z]+") do
				print(key)
			end'
}

reason=$(luaebpf_kfunc luaxdp)
if [ -n "$reason" ]; then
	for i in $(seq $((CALLS + 1))); do ktap_skip "luaebpf: $reason"; done
else
	output=$(luaebpf_compile callback) || { comment "$output"; fail "luaebpf: callback.bpf.lua did not compile"; }
	output=$(luaebpf_loadall callback) || { comment "$output"; fail "luaebpf: a call into the runtime did not verify"; }
	ktap_pass "luaebpf: every program calling the runtime verifies"

	output=$(lunatik run --context=softirq "$SCRIPT" 2>&1)
	[ -z "$output" ] || { comment "$output"; fail "luaebpf: the runtime did not start"; }
	answer=$(luaebpf_verdict answer)
	noargs=$(luaebpf_verdict noargs)
	wrong=$(luaebpf_verdict wrong)
	pair=$(luaebpf_verdict pair)
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	rm -rf "$LUAEBPF_PINS"

	[ "$answer" = "$DROP" ] || fail "luaebpf: the call with MAGIC answered '$answer', not DROP"
	ktap_pass "luaebpf: the name the program spelled reaches the callback, which read all eight argument bytes"
	[ "$noargs" = "$PASS" ] || fail "luaebpf: the call with no argument answered '$noargs', not PASS"
	ktap_pass "luaebpf: a call with no argument hands the callback an empty argument"
	[ "$wrong" = "$ABORTED" ] || fail "luaebpf: the call with WRONG answered '$wrong', not ABORTED"
	ktap_pass "luaebpf: the callback tells another argument from the one it accepts"
	[ "$pair" = "$DROP" ] || fail "luaebpf: the call with WRONG and MAGIC answered '$pair', not DROP"
	ktap_pass "luaebpf: two arguments reach the callback as two words, in order"
fi

row untested 15 "'lua' may be nil here; test it first" $'\tlocal v = lua(1)\n\treturn v + 1'
row compared 14 "'lua' may be nil here; test it first" \
	$'\tif lua(1) == 0 then\n\t\treturn 1\n\tend\n\treturn 2'
row ordered 14 "attempt to compare a runtime answer with a number" \
	$'\tif lua(1) < 5 then\n\t\treturn 1\n\tend\n\treturn 2'
row returned 15 "'lua' may be nil here; test it first" $'\tlocal v = lua(1)\n\treturn v'
row copied 15 "'lua' may be nil here; test it first" $'\tlocal v = lua(1)\n\tlocal w = v or 2\n\treturn w'
row joined 18 "a runtime answer joined another value here, whose nil is 0 and not -1; test it before" \
	$'\tlocal v\n\tif ctx:ingress() == 1 then\n\t\tv = lua(1)\n\tend\n\tif v then\n\t\treturn v\n\tend\n\treturn 2'
row boolean 14 "argument #1 is a boolean, and a call into the runtime passes numbers" \
	$'\tlocal v = lua(true)\n\tif v then\n\t\treturn v\n\tend\n\treturn 0'
row subprogram 6 "'lua' can only be called from the program's own function" $'\tlocal n = helper(1)\n\treturn n'
row noctx 14 "a call into the runtime passes the context, which the program's parameter does not hold" \
	$'\tlocal v = lua(1)\n\tif v then\n\t\treturn v\n\tend\n\treturn 0' ''
row noname 3 "xdp.runtime takes a name" $'\treturn 0' ctx ''
row negated 14 "'lua' may be nil here; test it first" $'\tlocal b = not lua(1)\n\tif b then\n\t\treturn 1\n\tend\n\treturn 0'
row longname 14 "the function needs 528 bytes of stack, over the 512 eBPF allows" \
	$'\tlocal v = lua(1)\n\tif v then\n\t\treturn v\n\tend\n\treturn 0' ctx 'string.rep("x", 480)'

# one runtime, two program types: a kfunc read off the runtime's namespace names bpf_luaxdp_run
# alone, and the TC program would call the XDP module's kfunc
cat > "$LUAEBPF_WORK/shared.bpf.lua" <<LUA
local xdp = require("bpf.xdp")
local tc  = require("bpf.tc")

local lua = xdp.runtime("$SCRIPT")

local function ingress(_)
	local verdict = lua(1)
	if verdict then
		return verdict
	end
	return 2
end

local function classify(_)
	local verdict = lua(1)
	if verdict then
		return verdict
	end
	return 0
end

xdp.program(ingress, {name = "ingress"})
tc.program(classify, {name = "classify"})
LUA
output=$(cd "$LUAEBPF_WORK" && lunatik bpf -o "$LUAEBPF_WORK/shared.bpf.o" "$LUAEBPF_WORK/shared.bpf.lua" 2>&1) \
	|| { comment "$output"; fail "luaebpf: shared.bpf.lua did not compile"; }
dump=$(bpftool btf dump file "$LUAEBPF_WORK/shared.bpf.o" format raw 2>&1)
missing=
for kfunc in bpf_luaxdp_run bpf_luatc_run; do
	grep -q "FUNC '$kfunc' .*linkage=extern" <<< "$dump" || missing="$missing $kfunc"
done
[ -z "$missing" ] || { comment "$dump"; fail "luaebpf: the object names no extern for$missing"; }
ktap_pass "luaebpf: a runtime called from both program types lowers to each program's own kfunc"

if ! command -v llvm-objdump >/dev/null; then
	ktap_skip "luaebpf: llvm-objdump is not installed"
else
	for order in little big; do
		output=$(luaebpf_ordered $order callback) \
			|| { comment "$output"; fail "luaebpf: callback.bpf.lua did not compile $order-endian"; }
		stored=$(keys $order | sort -u)
		[ "$stored" = "$SCRIPT" ] || { comment "$stored"; fail "luaebpf: the $order-endian object stores another key"; }
	done
	ktap_pass "luaebpf: the key a call stores reads as the runtime's name in either byte order"
fi

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

