#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests what `lunatik run` leaves behind for a script whose compiled program sits beside it.
#   - the map the program file declares is pinned under the script's root, the runtime is
#     registered, the link is pinned, and the program the device carries is the one the pinned
#     link holds. The kernel script opens the map by its pin path, which it can only do if the
#     map was pinned before the runtime started, so its line is the order the run promises
#   - a script with an object and no kernel script runs the program alone: the link is pinned and
#     no runtime is registered, and its stop, with no runtime to stop, exits 0 and takes the program
#     and the root down
#
# Usage: sudo bash tests/luaebpf/load.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

LUAEBPF_RUNS="loader alone"
trap cleanup EXIT

luaebpf_start 2
luaebpf_device || fail "luaebpf: the case could not create $LUAEBPF_DEV"

output=$(luaebpf_stage loader) || { comment "$output"; fail "luaebpf: loader.bpf.lua did not compile"; }
mark_dmesg
output=$(lunatik run --dev="$LUAEBPF_DEV" tests/luaebpf/loader 2>&1)
status=$?
pinned=$(ls "$LUAEBPF_ROOT/loader" 2>/dev/null | tr '\n' ' ')
listed=$(lunatik list)
opened=$(dmesg_since | grep -c "luaebpf loader test pass")
linked=$(bpftool -j link show pinned "$LUAEBPF_ROOT/loader/loader-link" 2>/dev/null | grep -oP '"prog_id":\K[0-9]+')
attached=$(luaebpf_attached)
lunatik stop tests/luaebpf/loader > /dev/null 2>&1

[ "$status" -eq 0 ] && [ -z "$output" ] || { comment "$output"; fail "luaebpf: the run exited $status"; }
[ "$pinned" = "counts loader-link " ] || fail "luaebpf: the script's root holds '$pinned'"
grep -qxF tests/luaebpf/loader <<< "$listed" || fail "luaebpf: lunatik list says '$listed'"
[ "$opened" -eq 1 ] || fail "luaebpf: the kernel script did not open the map by its pin path"
[ -n "$linked" ] && [ "$linked" = "$attached" ] ||
	fail "luaebpf: $LUAEBPF_DEV carries program '$attached', the pinned link holds '$linked'"
ktap_pass "luaebpf: a run pins the maps, starts the runtime and pins the link it attached"

output=$(luaebpf_stage alone) || { comment "$output"; fail "luaebpf: alone.bpf.lua did not compile"; }
output=$(lunatik run --dev="$LUAEBPF_DEV" tests/luaebpf/alone 2>&1)
status=$?
pinned=$(ls "$LUAEBPF_ROOT/alone" 2>/dev/null | tr '\n' ' ')
listed=$(lunatik list)
attached=$(luaebpf_attached)
stopped=$(lunatik stop tests/luaebpf/alone 2>&1)
halted=$?
left=$(ls -d "$LUAEBPF_ROOT/alone" 2>/dev/null)
detached=$(luaebpf_attached)

[ "$status" -eq 0 ] && [ -z "$output" ] || { comment "$output"; fail "luaebpf: the run of alone exited $status"; }
[ "$pinned" = "alone-link " ] || fail "luaebpf: the root of a program with no kernel script holds '$pinned'"
[ -n "$attached" ] || fail "luaebpf: $LUAEBPF_DEV carries no program"
grep -qxF tests/luaebpf/alone <<< "$listed" && fail "luaebpf: a program with no kernel script registered a runtime"
[ "$halted" -eq 0 ] && [ -z "$left" ] && [ -z "$detached" ] ||
	{ comment "$stopped"; fail "luaebpf: the stop of alone exited $halted, leaving '$left' and program '$detached'"; }
ktap_pass "luaebpf: a script with a program and no kernel script runs and stops the program alone"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

