#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the verdict a program returns, held to the actions of its type: linux.xdp.action, 0 to 4,
# and linux.tc.action, -1 to 8, the range luakfunc_action holds a kernel callback to.
#   - a verdict the program computes at either end of its type's actions is returned as it is:
#     XDP_ABORTED and XDP_REDIRECT, TC_ACT_UNSPEC, which prog run reads as 4294967295, and
#     TC_ACT_TRAP; so is TC_ACT_UNSPEC where the compiler holds it
#   - one the program computes past either end, one whose low 32 bits are an action and whose high
#     ones are not, and one a called function computes, which a callee's return is not held to,
#     take the default verdict, which these programs set to XDP_DROP and TC_ACT_SHOT
#   - a verdict the compiler holds outside the actions, a boolean, and a value a boolean on one
#     path, are refused with their messages and lines, and so is a default verdict outside them
#   - with LUAEBPF_DROP=action the test is gone, the verifier still takes the object, since it
#     reads no XDP or TC return value, and prog run returns the low 32 bits of each value, which
#     is what proves the test is emitted
#
# Usage: sudo bash tests/luaebpf/verdict.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 15

# check <title> <name>[:<context>]=<verdict>...: prog run of each program, over the context named or
# the fourteen bytes common.sh writes, returns the verdict it owes
check() {
	local title="$1" row name context want got wrong=
	shift
	for row in "$@"; do
		name=${row%%=*}; want=${row#*=}
		context=${name#*:}; [ "$context" = "$name" ] && context=
		got=$(luaebpf_verdict "${name%%:*}" "$context")
		[ "$got" = "$want" ] || wrong="$wrong ${name%%:*} returned '$got', not '$want';"
	done
	if [ -n "$wrong" ]; then
		comment "$wrong"
		ktap_fail "luaebpf: $title"
	else
		ktap_pass "luaebpf: $title"
	fi
}

output=$(luaebpf_compile verdict) || { comment "$output"; fail "luaebpf: verdict.bpf.lua did not compile"; }
output=$(luaebpf_loadall verdict) || { comment "$output"; fail "luaebpf: the verdict programs did not verify"; }
ktap_pass "luaebpf: every verdict program verifies"

check "an XDP verdict the program computes at either end of the actions is returned" \
	xdpfirst=0 xdplast=4
check "an XDP verdict computed outside the actions, past 32 bits or by a callee takes the default" \
	xdpabove=1 xdpbelow=1 xdphigh=1 xdpcalled=1
check "a TC verdict the program computes or holds at either end of the actions is returned" \
	tcfirst:tcframe=4294967295 tclast:tcframe=8 tcunspec:tcframe=4294967295
check "a TC verdict computed outside the actions, past 32 bits or by a callee takes the default" \
	tcabove:tcframe=2 tcbelow:tcframe=2 tchigh:tcframe=2 tccalled:tcframe=2

# every row is one program of the type its module declares, so only the module and the return differ
row() {
	local name="$1" module="$2" message="$3" body="$4" opts="${5:-}"
	{
		echo "local bpf = require(\"bpf.$module\")"
		echo ''
		echo 'return bpf.program(function(ctx)'
		echo "$body"
		echo "end$opts)"
	} > "$LUAEBPF_WORK/$name.bpf.lua"
	local output
	output=$(luaebpf_refuses "$name" "$name.bpf.lua:$message")
	if [ $? -ne 0 ]; then
		comment "$output"
		ktap_fail "luaebpf: $name"
	else
		ktap_pass "luaebpf: $name is refused with its message and line"
	fi
}

row xdpknown xdp "4: the verdict 11 is not an XDP action" $'\treturn 11'
row xdpnegative xdp "4: the verdict -1 is not an XDP action" $'\treturn -1'
row tcknown tc "4: the verdict 9 is not a TC action" $'\treturn 9'
row tcnegative tc "4: the verdict -2 is not a TC action" $'\treturn -2'
row boolean xdp "5: the verdict may be a boolean here; return an action" \
	$'\tlocal p = ctx:packet()\n\treturn p:getbyte(12) == 8'
row joined xdp "9: the verdict may be a boolean here; return an action" \
	$'\tlocal p = ctx:packet()\n\tlocal v = 2\n\tif p:getbyte(12) == 8 then\n\t\tv = true\n\tend\n\treturn v'
row tcboolean tc "5: the verdict may be a boolean here; return an action" \
	$'\tlocal p = ctx:data()\n\treturn p:getbyte(7) == 17'
row xdpdefault xdp "3: xdp.program's default verdict is not an XDP action" $'\treturn 2' ', {default = 5}'
row tcdefault tc "3: tc.program's default verdict is not a TC action" $'\treturn 0' ', {default = 9}'

rm -rf "$LUAEBPF_PINS"; mkdir -p "$LUAEBPF_PINS"
output=$(luaebpf_compile verdict action) || { comment "$output"; fail "luaebpf: the dropped build failed"; }
output=$(luaebpf_loadall verdict) || { comment "$output"; fail "luaebpf: the verifier refused the verdicts unchecked"; }
check "without the range test the verifier takes the object and the raw values come through" \
	xdpabove=5 xdpbelow=4294967295 xdphigh=2 xdpcalled=5 tcabove:tcframe=9 tcbelow:tcframe=4294967294 \
	tchigh:tcframe=0 tccalled:tcframe=14

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

