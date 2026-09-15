#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the compiler host: the state lunatikc stands up for a program file's body.
#   - the body requires bpf.xdp, linux.xdp, string, io and debug, and uses them
#   - luaebpf.proto.read hands back the prototype of a known function: its numparams,
#     maxstacksize, first opcode, first line, source and argument mode are asserted in the body
#   - a host that preloaded no luaebpf.proto makes compile raise a message naming it
# The body asserts and raises, so the case reads what lunatikc printed and its exit status.
#
# Usage: sudo bash tests/luaebpf/host.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 2

output=$(luaebpf_compile host)
if [ $? -ne 0 ]; then
	comment "$output"
	fail "luaebpf: the host state does not carry what a program file's body needs"
fi
ktap_pass "luaebpf: the body runs with the standard libraries and the prototype accessor"

[ -s "$LUAEBPF_WORK/host.bpf.o" ] || fail "luaebpf: no object was written"
ktap_pass "luaebpf: lunatikc bpf writes the object beside its -o"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

