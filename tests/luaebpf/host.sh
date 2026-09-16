#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the compiler host: the state lunatikc stands up for a program file's body.
#   - the body requires bpf.xdp, linux.xdp, string, io and debug, and uses them
#   - luaebpf.proto.read hands back the prototype of a known function: its numparams,
#     maxstacksize, first opcode, first line, source and argument mode are asserted in the body
#   - luaebpf.probe.maygoto answers the instruction, and where it answers at all it agrees with
#     the release the kernel reports
#   - a host that preloaded no luaebpf.proto, and one that preloaded no luaebpf.probe, make
#     compile raise a message naming what is missing
#   - an unprivileged compile cannot load the probe's own program: it falls back to that release
#     rather than to "no may_goto", and still compiles a loop the compiler cannot bound, a row
#     that skips on a kernel bounding no loop at any privilege
# The body asserts and raises, so the case reads what lunatikc printed and its exit status.
#
# Usage: sudo bash tests/luaebpf/host.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 3

output=$(luaebpf_compile host)
if [ $? -ne 0 ]; then
	comment "$output"
	fail "luaebpf: the host state does not carry what a program file's body needs"
fi
ktap_pass "luaebpf: the body runs with the standard libraries, the prototype accessor and the probe"

[ -s "$LUAEBPF_WORK/host.bpf.o" ] || fail "luaebpf: no object was written"
ktap_pass "luaebpf: lunatikc bpf writes the object beside its -o"

# nobody must be able to reach the program file, and the object goes where anyone may write
cat > "$LUAEBPF_WORK/unbounded.bpf.lua" <<'LUA'
local xdp = require("bpf.xdp")

return xdp.program(function(ctx)
	local s = 0
	for i = 1, ctx.ingress_ifindex do
		s = s + i
	end
	return s
end)
LUA
chmod 0755 "$LUAEBPF_WORK"
chmod 0644 "$LUAEBPF_WORK/unbounded.bpf.lua"
# a kernel offering the compiler no loop form refuses this program at every privilege, so what
# the row reads there is that refusal and not the fallback
if lunatikc bpf -o /dev/null "$LUAEBPF_WORK/unbounded.bpf.lua" > /dev/null 2>&1; then
	output=$(setpriv --reuid=65534 --regid=65534 --clear-groups \
		lunatikc bpf -o /dev/null "$LUAEBPF_WORK/unbounded.bpf.lua" 2>&1) \
		|| { comment "$output"; fail "luaebpf: an unprivileged compile did not fall back to the release"; }
	ktap_pass "luaebpf: a probe that needs a privilege falls back to the release the kernel reports"
else
	ktap_skip "luaebpf: the compiler bounds no loop on this kernel"
fi

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

