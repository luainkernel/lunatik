#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the escape hatch: a compiled program calls the kernel Lua runtime, which answers the
# verdict the program returns. One program file declares four programs over two runtime proxies,
# and callback.lua is the runtime they call: it answers PASS for an empty argument, DROP for the
# magic and ABORTED for anything else. Every program returns TX where the kfunc answered -1, a
# verdict the callback never sets, so a row tells "no runtime was dispatched" from "the callback
# refused the argument".
#   - the object is loaded with bpftool rather than staged beside the script: `lunatik run` over
#     a staged object goes down the loader's path and asks for a device, and what this case wants
#     is the runtime alone
#   - `xdp.runtime()` with no name reaches the callback, which is what says the key the compiler
#     derived is the one `lunatik run tests/luaebpf/callback` registered, and that all eight
#     bytes of the argument arrived: the magic's low 32 bits are not the magic
#   - the same key spelled out reaches the same callback, which is what makes the row above a
#     statement about the default rather than about the kfunc
#   - a call with no argument hands the kfunc a null pointer and a zero size, and the callback
#     reads `#ctx:argument()` as zero
#   - a call carrying another constant is told apart, which is what makes the DROP rows mean
#     something: the callback's rejection is reachable
#   - the answer used as a number without a test, compared with a number by '==' and by '<',
#     called from a function other than the program's own, handed something that is not a number,
#     and made from a program declared without the context are refused with their messages and
#     lines
#   - one proxy declared through `xdp.runtime` and called from both program types names both
#     kfuncs in the object: the kfunc a call lowers to is the program's, not the namespace's.
#     The row only compiles, so the object's own BTF is what it reads
#
# Usage: sudo bash tests/luaebpf/callback.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

SCRIPT=tests/luaebpf/callback
ROWS=12

luaebpf_start $ROWS

gate=$(luaebpf_kfunc luaxdp bpf_luaxdp_run)
if [ -n "$gate" ]; then
	for i in $(seq $ROWS); do ktap_skip "luaebpf: $gate"; done
	ktap_totals
	exit 0
fi

output=$(luaebpf_compile callback) || { comment "$output"; fail "luaebpf: callback.bpf.lua did not compile"; }
output=$(luaebpf_loadall callback) || { comment "$output"; fail "luaebpf: a call into the runtime did not verify"; }
ktap_pass "luaebpf: every program calling the runtime verifies"

mark_dmesg
output=$(lunatik run "$SCRIPT" softirq 2>&1)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: the runtime did not start"; }

# every verdict is read while the runtime is up, and the runtime goes down before the checks, so
# a failing row leaves nothing registered for the next case
answer=$(luaebpf_verdict answer)
named=$(luaebpf_verdict named)
noargs=$(luaebpf_verdict noargs)
wrong=$(luaebpf_verdict wrong)
lunatik stop "$SCRIPT" > /dev/null 2>&1

[ "$answer" = 1 ] || fail "luaebpf: the default key answered '$answer', not DROP"
ktap_pass "luaebpf: the derived key reaches the callback, which read all eight argument bytes"

[ "$named" = 1 ] || fail "luaebpf: the key spelled out answered '$named', not DROP"
ktap_pass "luaebpf: the same key spelled out reaches the same callback"

[ "$noargs" = 2 ] || fail "luaebpf: a call with no argument answered '$noargs', not PASS"
ktap_pass "luaebpf: a call with no argument hands the callback an empty argument"

[ "$wrong" = 0 ] || fail "luaebpf: another constant answered '$wrong', not ABORTED"
ktap_pass "luaebpf: the callback tells the argument it was handed from another one"

# every row is one compiled function over one runtime proxy, so only the body and the parameter
# list the program declares differ
row() {
	local name="$1" line="$2" message="$3" body="$4" params="${5-ctx}"
	{
		echo 'local xdp = require("bpf.xdp")'
		echo ''
		echo 'local lua = xdp.runtime("tests/luaebpf/callback")'
		echo ''
		echo 'local function helper(n)'
		echo $'\tlocal v = lua(n)\n\tif v then\n\t\treturn v\n\tend\n\treturn 0'
		echo 'end'
		echo ''
		echo "return xdp.program(function($params)"
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

row untested 15 "'lua' may be nil here; test it first" $'\tlocal v = lua(1)\n\treturn v + 1'
row compared 14 "'lua' may be nil here; test it first" \
	$'\tif lua(1) == 0 then\n\t\treturn 1\n\tend\n\treturn 2'
row ordered 14 "'lua' may be nil here; test it first" \
	$'\tif lua(1) < 5 then\n\t\treturn 1\n\tend\n\treturn 2'
row subprogram 6 "'lua' can only be called from the program's own function" \
	$'\tlocal n = helper(1)\n\treturn n'
row boolarg 14 "argument #1 is a boolean, and a call into the runtime passes numbers" \
	$'\tlocal v = lua(true)\n\tif v then\n\t\treturn v\n\tend\n\treturn 0'

# the one row whose program declares no context: without the guard the emitter reads a register
# the prologue never set, and the verifier's 'R6 !read_ok' names no line of Lua
row noctx 14 "a call into the runtime takes the context, which this program does not" \
	$'\tlocal v = lua(1)\n\tif v then\n\t\treturn v\n\tend\n\treturn 0' ''

# one runtime, two program types: an object whose extern is read off the proxy's namespace would
# name bpf_luaxdp_run alone, and the TC program would call the XDP module's kfunc
cat > "$LUAEBPF_WORK/shared.bpf.lua" <<'LUA'
local xdp = require("bpf.xdp")
local tc  = require("bpf.tc")

local lua = xdp.runtime("tests/luaebpf/callback")

local function ingress(ctx)
	local verdict = lua(1)
	if verdict then
		return verdict
	end
	return 2
end

local function classify(skb)
	local verdict = lua(1)
	if verdict then
		return verdict
	end
	return 0
end

xdp.program(ingress, {name = "ingress"})
tc.program(classify, {name = "classify"})
LUA
output=$(cd "$LUAEBPF_WORK" && lunatikc bpf -o "$LUAEBPF_WORK/shared.bpf.o" \
	"$LUAEBPF_WORK/shared.bpf.lua" 2>&1) \
	|| { comment "$output"; fail "luaebpf: shared.bpf.lua did not compile"; }
dump=$(bpftool btf dump file "$LUAEBPF_WORK/shared.bpf.o" format raw 2>&1)
missing=
for kfunc in bpf_luaxdp_run bpf_luatc_run; do
	echo "$dump" | grep -q "FUNC '$kfunc' .*linkage=extern" || missing="$missing $kfunc"
done
[ -z "$missing" ] || { comment "$dump"; fail "luaebpf: the object names no extern for$missing"; }
ktap_pass "luaebpf: each program type's own kfunc is what a shared runtime lowers to"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

