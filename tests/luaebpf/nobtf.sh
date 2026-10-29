#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests what a load says when libbpf cannot resolve the kfunc a call into the kernel Lua runtime
# names. The failure never reaches the kernel, so there is no verifier log, only libbpf's own
# warning, which names the kfunc. The case takes the mechanism away rather than the host's module
# BTF: `LUAEBPF_DROP=ksyms` leaves the kfunc out of the object's `.ksyms` DATASEC, where libbpf
# looks an extern up, and the open then fails with `failed to find BTF for extern
# 'bpf_luaxdp_run'`, where a host without the module's BTF fails the load with `not found in
# kernel or module BTFs`.
#   - bpftool's load fails naming the kfunc
#   - `lunatik run` names it too, exits 1 and leaves no pin root, no runtime and nothing on the
#     device
#   - the same drop over a program file with no call into Lua leaves the object loadable
#   - the program compiled whole deploys through `lunatik run`, whose libbpf resolves the kfunc in
#     the module's BTF, and the program on the device answers its nil branch, since no runtime of
#     its name runs; skipped where the kernel publishes no BTF for luaxdp
#
# Usage: sudo bash tests/luaebpf/nobtf.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

LUAEBPF_RUNS="nobtf"
trap cleanup EXIT

KFUNC=bpf_luaxdp_run
PASS=2

luaebpf_start 4
luaebpf_device || fail "luaebpf: the case could not create $LUAEBPF_DEV"

output=$(luaebpf_compile nobtf ksyms) || { comment "$output"; fail "luaebpf: nobtf.bpf.lua did not compile"; }
output=$(luaebpf_loadall nobtf)
status=$?
rm -rf "$LUAEBPF_PINS"
[ "$status" -ne 0 ] || { comment "$output"; fail "luaebpf: an object whose kfunc libbpf cannot resolve loaded"; }
grep -qF "'$KFUNC'" <<< "$output" || { comment "$output"; fail "luaebpf: the failure does not name $KFUNC"; }
ktap_pass "luaebpf: a load that cannot resolve the kfunc names it"

output=$(luaebpf_stage nobtf ksyms) || { comment "$output"; fail "luaebpf: nobtf.bpf.lua did not compile"; }
luaebpf_undone "a run that cannot resolve the kfunc names it and undoes itself" nobtf 1 "'$KFUNC'" \
	--dev="$LUAEBPF_DEV"

output=$(luaebpf_compile pass ksyms) || { comment "$output"; fail "luaebpf: pass.bpf.lua did not compile"; }
output=$(luaebpf_loadall pass)
status=$?
rm -rf "$LUAEBPF_PINS"
[ "$status" -eq 0 ] || { comment "$output"; fail "luaebpf: a program with no call into Lua did not load"; }
ktap_pass "luaebpf: the drop reaches the call into Lua and leaves a program without one loadable"

reason=$(luaebpf_kfunc luaxdp)
if [ -n "$reason" ]; then
	ktap_skip "luaebpf: $reason"
else
	output=$(luaebpf_stage nobtf) || { comment "$output"; fail "luaebpf: nobtf.bpf.lua did not compile whole"; }
	output=$(lunatik run --dev="$LUAEBPF_DEV" tests/luaebpf/nobtf 2>&1)
	status=$?
	id=$(luaebpf_attached)
	verdict=
	[ -n "$id" ] && verdict=$(bpftool prog run id "$id" data_in "$LUAEBPF_WORK/packet.bin" 2>&1 \
		| grep -oP 'Return value: \K[0-9]+')
	lunatik stop tests/luaebpf/nobtf > /dev/null 2>&1
	[ "$status" -eq 0 ] && [ -n "$id" ] || { comment "$output"; fail "luaebpf: the program compiled whole did not deploy"; }
	[ "$verdict" = "$PASS" ] || fail "luaebpf: the deployed program answered '$verdict', not its nil branch's PASS"
	ktap_pass "luaebpf: compiled whole, the program deploys through lunatik run, which resolves its kfunc"
fi

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

