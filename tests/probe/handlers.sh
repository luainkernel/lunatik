#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Covers which handler a hit runs, over the four handlers tables probe.new takes:
# only pre, only post, both, and neither. Each script probes the personality
# syscall, which nothing else on an idle host calls, and one setarch calls it
# exactly once, so the count is exact: the handler the table defines runs once, and
# the one it does not never runs. The empty table has nothing to print, so what it
# asserts is that probe.new still succeeds and arms one kprobe; each of those rows
# checks that kprobe, armed on load and gone on stop.
#
# probe.new reads the table once, when it registers, to decide whether the kernel
# installs a post handler. So a fifth row adds a post to the table after probe.new
# and asserts it does not fire, and a sixth runs a percpu script whose runtimes
# disagree about one and asserts that the set is refused, leaving no kprobe armed,
# rather than letting the first registration decide for the others. The sixth needs
# a second runtime, so it skips where one CPU is possible.
#
# Only pre was covered before: nothing in the tree registered a post handler, so
# the post half of every hit was untested. What these rows hold is the behaviour
# around the handler lookup, not its cost: whether a hit builds the closures before
# it knows there is a handler to pass them to is not observable from Lua, and none
# of the cases below measures it. A build that ran the handler the table does not
# have, or stopped running the one it does, is what they catch.
#
# Usage: sudo bash tests/probe/handlers.sh

PRE="tests/probe/handlers_pre"
POST="tests/probe/handlers_post"
BOTH="tests/probe/handlers_both"
NONE="tests/probe/handlers_none"
LATE="tests/probe/handlers_late"
SET="tests/probe/handlers_set"
KPROBES="/sys/kernel/debug/kprobes/list"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$PRE" > /dev/null 2>&1
	lunatik stop "$POST" > /dev/null 2>&1
	lunatik stop "$BOTH" > /dev/null 2>&1
	lunatik stop "$NONE" > /dev/null 2>&1
	lunatik stop "$LATE" > /dev/null 2>&1
	lunatik stop "$SET" > /dev/null 2>&1
}

# how many kprobes the kernel holds; nothing where debugfs does not say
kprobes()
{
	[ -r "$KPROBES" ] && grep -c "" "$KPROBES"
}

# runs one script over a single call to the probed syscall, and reports what each
# handler printed and what the kprobe list held on the way
row()
{
	mark_dmesg
	idle=$(kprobes)
	run_script "$1" hardirq
	armed=$(kprobes)
	setarch "$(uname -m)" -R true > /dev/null 2>&1
	sleep 1
	lunatik stop "$1" > /dev/null 2>&1
	stopped=$(kprobes)
	check_dmesg || { ktap_totals; exit 1; }
	pre_hits=$(dmesg_since | grep -cF "probe handlers: pre")
	post_hits=$(dmesg_since | grep -cF "probe handlers: post")
}

armed_one()
{
	[ -n "$idle" ] || return 0
	[ "$armed" = "$((idle + 1))" ] || fail "$1 armed $((armed - idle)) kprobes"
	[ "$stopped" = "$idle" ] || fail "$1 left $((stopped - idle)) kprobes armed"
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 6

command -v setarch > /dev/null 2>&1 || {
	echo "# SKIP: setarch not available"
	ktap_skip "a table with only a pre handler runs it, and runs nothing on the post hit"
	ktap_skip "a table with only a post handler runs it, and runs nothing on the pre hit"
	ktap_skip "a table with both handlers runs each of them once"
	ktap_skip "an empty handlers table arms a kprobe that runs nothing"
	ktap_skip "a post handler added to the table after probe.new does not fire"
	ktap_skip "a set whose runtimes disagree on the post handler is refused, leaving none armed"
	ktap_totals
	exit 0
}

row "$PRE"
[ "$pre_hits" = "1" ] || fail "the pre handler ran $pre_hits times on one call"
[ "$post_hits" = "0" ] || fail "a table with no post handler ran one $post_hits times"
armed_one "the pre handler"
ktap_pass "a table with only a pre handler runs it, and runs nothing on the post hit"

row "$POST"
[ "$post_hits" = "1" ] || fail "the post handler ran $post_hits times on one call"
[ "$pre_hits" = "0" ] || fail "a table with no pre handler ran one $pre_hits times"
armed_one "the post handler"
ktap_pass "a table with only a post handler runs it, and runs nothing on the pre hit"

row "$BOTH"
[ "$pre_hits" = "1" ] || fail "the pre handler ran $pre_hits times on one call"
[ "$post_hits" = "1" ] || fail "the post handler ran $post_hits times on one call"
armed_one "both handlers"
ktap_pass "a table with both handlers runs each of them once"

row "$NONE"
[ "$pre_hits" = "0" ] || fail "an empty handlers table ran a pre handler $pre_hits times"
[ "$post_hits" = "0" ] || fail "an empty handlers table ran a post handler $post_hits times"
armed_one "the empty table"
ktap_pass "an empty handlers table arms a kprobe that runs nothing"

row "$LATE"
[ "$pre_hits" = "1" ] || fail "the pre handler ran $pre_hits times on one call"
[ "$post_hits" = "0" ] || fail "a post handler added after probe.new ran $post_hits times"
armed_one "the late post handler"
ktap_pass "a post handler added to the table after probe.new does not fire"

if [ "$(sed 's/.*[-,]//' /sys/devices/system/cpu/possible)" = "0" ]; then
	echo "# SKIP: one possible CPU, so a set has one runtime and nothing to disagree about"
	ktap_skip "a set whose runtimes disagree on the post handler is refused, leaving none armed"
else
	mark_dmesg
	idle=$(kprobes)
	output=$(lunatik run "$SET" hardirq percpu 2>&1)
	echo "$output" | grep -q "probe registered with a different post handler" || \
		fail "the set was not refused: $output"
	check_dmesg || { ktap_totals; exit 1; }
	rolled=$(kprobes)
	listed=$(lunatik list)
	case "$listed" in
		*"$SET"*) fail "the refused run left the script registered: $listed" ;;
	esac
	if [ -n "$idle" ]; then
		[ "$rolled" = "$idle" ] || fail "the refused run left $((rolled - idle)) kprobes armed"
	fi
	ktap_pass "a set whose runtimes disagree on the post handler is refused, leaving none armed"
fi

ktap_totals

