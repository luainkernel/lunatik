#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test for the id_table hid.register() allocates before it walks the
# table the script handed it. lua_geti() and the field reads behind
# lunatik_optinteger() both honour __index, so a metamethod written in Lua can
# raise from inside the walk; the longjmp then skipped the free and the block
# stayed allocated for the rest of the boot. The fix hands the table to the
# driver before the walk, so the object's release frees it.
#
# LUAHID_MAXIDS entries is past the largest kmalloc cache but well short of what
# one leak would show in a counter, so the script repeats the refusal until what
# a leak holds is tens of MiB and the harness reads SUnreclaim. Each refusal
# asserts that it came from the walk, so a refusal at the length bound fails the
# case instead of passing it with nothing to leak; a block this host cannot serve
# is the host and not the code, and the script says so and stops for a skip.
#
# The script then holds as many live buffers of the same size. That probe is what
# tells the two zero deltas apart: it is allocated the same way, so if the counter
# does not move for it either, this kernel does not account an allocation of this
# size where the test reads and there is nothing to measure - skip, never pass.
#
# Usage: sudo bash tests/hid/idtable_leak.sh

SCRIPT="tests/hid/idtable_leak"
LEAK_MIB=32
SKIP="hid/idtable_leak: the kernel could not serve a block of this size" # printed by the script

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() { lunatik stop "$SCRIPT" > /dev/null 2>&1; }
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

slab_mib() { echo $(( $(grep SUnreclaim /proc/meminfo | awk '{print $2}') / 1024 )); }

mark_dmesg

before=$(slab_mib)
run_script "$SCRIPT"
alive=$(slab_mib)
lunatik stop "$SCRIPT" > /dev/null 2>&1
after=$(slab_mib)

probe=$((alive - after))
leaked=$((after - before))

if ! check_dmesg; then
	ktap_totals
	exit 1
elif dmesg_since | grep -qF "$SKIP"; then
	ktap_skip "$SKIP"
elif [ "$probe" -lt "$LEAK_MIB" ]; then
	ktap_skip "hid/idtable_leak: SUnreclaim does not account an id_table of this size (probe ${probe}MiB)"
elif [ "$leaked" -ge "$LEAK_MIB" ]; then
	ktap_fail "hid/idtable_leak: the id_table leaked ${leaked}MiB when the walk raised"
else
	ktap_pass "hid/idtable_leak"
fi

ktap_totals
[ $KTAP_FAIL -eq 0 ]

