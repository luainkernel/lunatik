#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests what an unresolved kfunc says. A program that calls into the kernel runtime needs the
# module's own BTF to load, and when libbpf cannot find the extern there the failure never
# reaches the kernel: there is no verifier log, only what libbpf itself said, and the user must
# read the kfunc's name in it rather than a bare errno.
#
# The mechanism is dropped rather than the environment changed: `LUAEBPF_DROP=ksyms` leaves the
# extern out of the object's `.ksyms` DATASEC, so libbpf cannot resolve it for the same reason a
# missing module BTF cannot. The host cannot be stripped of its module BTF from inside a case,
# and unloading the module to fake it would hand the next case a different machine. The case
# needs no kfunc gate: the load fails either way, and what it asserts is the message.
#   - `bpftool prog loadall`, whose stderr carries libbpf's own warning, names the kfunc
#   - `lunatik run` names it too, exits non-zero, and leaves no pin root, no runtime and nothing
#     on the device
#   - the same drop over a program file with no call into Lua still loads, which is what says
#     the drop reaches the escape hatch and nothing else
#
# Usage: sudo bash tests/luaebpf/nobtf.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

KFUNC=bpf_luaxdp_run

luaebpf_start 3
luaebpf_device || fail "luaebpf: the case could not create $LUAEBPF_DEV"

output=$(luaebpf_compile nobtf ksyms) || { comment "$output"; fail "luaebpf: nobtf.bpf.lua did not compile"; }

output=$(luaebpf_loadall nobtf)
status=$?
[ "$status" -ne 0 ] || { comment "$output"; fail "luaebpf: an object naming an unresolved kfunc loaded"; }
echo "$output" | grep -qF "$KFUNC" || { comment "$output"; fail "luaebpf: the failure does not name $KFUNC"; }
ktap_pass "luaebpf: a load that cannot resolve the kfunc says which kfunc"

output=$(luaebpf_install nobtf ksyms) || { comment "$output"; fail "luaebpf: nobtf.bpf.lua did not stage"; }
luaebpf_undone "a run that cannot resolve the kfunc names it and undoes itself" nobtf "$KFUNC" \
	dev="$LUAEBPF_DEV"

output=$(luaebpf_compile pass ksyms) || { comment "$output"; fail "luaebpf: pass.bpf.lua did not compile"; }
output=$(luaebpf_loadall pass) || { comment "$output"; fail "luaebpf: a program with no call into Lua did not load"; }
ktap_pass "luaebpf: the drop reaches the escape hatch and leaves a program without one alone"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

