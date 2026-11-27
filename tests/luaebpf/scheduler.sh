#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests `lunatik run` on a compiled sched_ext scheduler, the struct_ops path the
# C schedulers of tests/scx do not reach: they register an object clang built,
# this one the object luaebpf wrote. The program file declares the minimal
# scheduler bpf.scx writes, a name and an init callback that returns 0.
#   - the scheduler compiles, and a run with no device registers it: the link
#     register pins sits under the script's root, sched_ext reports the scheduler
#     enabled, and, with no kernel script beside it, no runtime is registered;
#     the stop unregisters it, sched_ext reports it disabled again, and the root
#     is gone
#   - a run with --dev is refused naming the option, before anything is created,
#     the way a program that needs a device is refused a missing one (notarget.sh)
#
# These skip on a kernel without sched_ext (its kset is /sys/kernel/sched_ext),
# where the compiler's read of the kernel's `sched_ext_ops` has nothing to read
# so the program file cannot compile, and while another sched_ext scheduler is
# enabled.
#
# Usage: sudo bash tests/luaebpf/scheduler.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

LUAEBPF_RUNS="scheduler"
SCHED=/sys/kernel/sched_ext
# the struct_ops map takes the scheduler's name, and the link register pins is named for it
LINK=luaebpfmin-link
trap cleanup EXIT

luaebpf_start 2

# the scheduler's state, which register and the stop reach on another task
sched_is() { [ "$(cat "$SCHED/state" 2>/dev/null)" = "$1" ]; }

[ -d "$SCHED" ] || skip_script "luaebpf: the kernel has no sched_ext"
sched_is disabled || skip_script "luaebpf: another sched_ext scheduler is enabled"

output=$(luaebpf_stage scheduler) || { comment "$output"; fail "luaebpf: scheduler.bpf.lua did not compile"; }

# the register path: no device, a link pinned, the scheduler enabled, and no runtime
mark_dmesg
output=$(lunatik run tests/luaebpf/scheduler 2>&1)
status=$?
awaited sched_is enabled
state=$(cat "$SCHED/state" 2>/dev/null)
pinned=$(ls "$LUAEBPF_ROOT/scheduler" 2>/dev/null | tr '\n' ' ')
listed=$(lunatik list)
stopped=$(lunatik stop tests/luaebpf/scheduler 2>&1)
halted=$?
awaited sched_is disabled
after=$(cat "$SCHED/state" 2>/dev/null)
left=$(ls -d "$LUAEBPF_ROOT/scheduler" 2>/dev/null)

[ "$status" -eq 0 ] && [ -z "$output" ] || { comment "$output"; fail "luaebpf: the run of scheduler exited $status"; }
[ "$pinned" = "$LINK " ] || fail "luaebpf: the scheduler's root holds '$pinned'"
[ "$state" = enabled ] || { comment "$(dmesg_since | grep -F sched_ext | tail -5)"; fail "luaebpf: sched_ext reports '$state', not enabled"; }
grep -qxF tests/luaebpf/scheduler <<< "$listed" && fail "luaebpf: a scheduler with no kernel script registered a runtime"
[ "$halted" -eq 0 ] && [ -z "$left" ] || { comment "$stopped"; fail "luaebpf: the stop exited $halted, leaving '$left'"; }
[ "$after" = disabled ] || fail "luaebpf: the stop left sched_ext '$after', not disabled"
ktap_pass "luaebpf: a scheduler compiles and registers with no device, and the stop unregisters it"

# the refusal path: a scheduler takes no device, so a --dev is refused before anything is created
luaebpf_undone "a scheduler with --dev is refused naming the option" \
	scheduler 2 'is a scheduler and takes no device' --dev="$LUAEBPF_DEV"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

