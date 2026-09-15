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
# asserts is that probe.new still succeeds and arms one kprobe; every row checks
# that kprobe, armed on load and gone on stop.
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
KPROBES="/sys/kernel/debug/kprobes/list"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$PRE" > /dev/null 2>&1
	lunatik stop "$POST" > /dev/null 2>&1
	lunatik stop "$BOTH" > /dev/null 2>&1
	lunatik stop "$NONE" > /dev/null 2>&1
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
ktap_plan 4

command -v setarch > /dev/null 2>&1 || {
	echo "# SKIP: setarch not available"
	ktap_skip "a table with only a pre handler runs it, and runs nothing on the post hit"
	ktap_skip "a table with only a post handler runs it, and runs nothing on the pre hit"
	ktap_skip "a table with both handlers runs each of them once"
	ktap_skip "an empty handlers table arms a kprobe that runs nothing"
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

ktap_totals

