#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A netfilter hook's stop takes its callback off, its __close is that stop, and
# a stopped hook lets its packets through without a word in the kernel log.
#
# stop.lua registers four LOCAL_OUT hooks, each selecting by a mark of its own
# that the host's traffic does not carry, and reporting the mark of each packet
# its callback sees: one stopped while the body loads, twice; one held by a
# to-be-closed variable that goes out of scope, whose metatable holds one
# function under __close and stop; one kept; and one whose callback stops its
# own hook on its first packet, from softirq. One ping per mark, and a second
# one for the hook that stops itself: every ping goes through, the kept hook
# and the first ping of the self-stopping one are reported, and the stopped,
# the closed and the second ping of the self-stopping one are not. The stop
# leaves the hook registered until the runtime closes, so each packet of a
# stopped hook still reaches the binding, which finds no callback and logs
# nothing: no line of the module's appears in the kernel log. The cases run on
# a plain softirq runtime, and again on a percpu set, whose runtimes share each
# hook and stop each their own callback; the pings leave from CPU 0, so the
# self-stopping hook's two reach the one runtime that stopped it. A third ping
# for that hook leaves from the last CPU: the plain runtime, whose stop took the
# callback off for every CPU, does not report it, and the percpu set hands it to
# that CPU's runtime, whose callback still runs and reports it, on a machine
# with more than one CPU.
#
# Usage: sudo bash tests/netfilter/stop.sh

SCRIPT="tests/netfilter/stop"
MODULE="luanetfilter"
PREFIX="netfilter stop: "
TARGET="127.0.0.226"
STOPPED=226
CLOSED=227
KEPT=228
ONCE=229
LAST=$(sed 's/.*[-,]//' /sys/devices/system/cpu/online)

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
}
trap cleanup EXIT
cleanup

skip() { ktap_header; ktap_plan 1; ktap_skip "$1"; ktap_totals; exit 0; }

# reported <mark>: how many pings carrying that mark a callback saw
reported() {
	dmesg_since | grep -cE "${PREFIX}$1\$"
}

# ping_marked <cpu> <mark>: a percpu set hands the ping to the runtime of the CPU it leaves from
ping_marked() {
	taskset -c "$1" ping -c 1 -W 1 -m "$2" $TARGET > /dev/null 2>&1 || fail "the ping marked $2 did not go through"
}

# stops <runtime options> <label> <reports>: the cases, on the script run with those options, where
# the self-stopping hook reports <reports> of its pings
stops() {
	mark_dmesg
	run_script --context=softirq $1 "$SCRIPT"
	for mark in $STOPPED $CLOSED $KEPT $ONCE $ONCE; do
		ping_marked 0 $mark
	done
	ping_marked $LAST $ONCE
	lunatik stop "$SCRIPT" 2>/dev/null

	[ "$(reported $KEPT)" -ge 1 ] || fail "$2: a hook left running did not see its packet"
	ktap_pass "$2: a hook left running sees its packet"

	[ "$(reported $STOPPED)" = 0 ] || fail "$2: a stopped hook saw a packet"
	ktap_pass "$2: a hook stopped twice sees no packet, and its packets go through"

	[ "$(reported $CLOSED)" = 0 ] || fail "$2: a to-be-closed hook saw a packet after its scope"
	ktap_pass "$2: a to-be-closed variable stops a hook, through the stop it holds as __close"

	[ "$(reported $ONCE)" = "$3" ] || fail "$2: a hook that stopped itself saw $(reported $ONCE) packets"
	ktap_pass "$2: a callback stops its own hook in its own runtime, and the next packet there does not reach it"

	dmesg_since | grep -qF "$MODULE: " && fail "$2: a stopped hook logged: $(dmesg_since | grep -F "$MODULE: " | head -1)"
	ktap_pass "$2: a stopped hook logs nothing"

	check_dmesg && ktap_pass "$2: no Lua errors, kernel warnings or oopses"
}

[ -e /sys/module/$MODULE ] || skip "netfilter/stop: $MODULE not loaded"
command -v taskset > /dev/null 2>&1 || skip "netfilter/stop: taskset not available"

ktap_header
ktap_plan 12

stops "" "plain" 1
stops --percpu "percpu" $((LAST > 0 ? 2 : 1))

ktap_totals

