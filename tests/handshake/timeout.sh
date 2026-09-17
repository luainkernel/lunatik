#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the only path that reaches a queued request: the submit succeeding, the
# completion wait, the timeout and tls_handshake_cancel. Everywhere else on a
# host with no agent the submit answers ESRCH, because handshake_genl_notify
# asks genl_has_listeners whether anyone subscribes to the handshake family's
# tlshd multicast group before it builds the message.
#
# The stimulus this host cannot otherwise supply is that subscriber, and the
# script builds one out of the tree's own modules: a netlink.genl session that
# resolves the group id out of a CTRL_CMD_GETFAMILY reply and joins the group
# with NETLINK_ADD_MEMBERSHIP. Nothing ever accepts the request, so the wait
# runs out and the binding cancels it.
#
# The cancel takes the request off the pending list but leaves it keyed on the
# socket until the socket is destroyed, so the hello that follows on the same
# socket answers EBUSY: that is what the second case pins, and why the last one
# needs a socket of its own.
#
# This is the complement of upcall.sh's first case: the same call on the same
# kind of socket, a different errno, keyed on nothing but whether a subscriber
# exists. Closing the session and repeating the call on a fresh socket brings
# ESRCH back, which is what says the subscriber was the variable.
#
# Skipped whole where tlshd is installed or running: a real agent would accept
# the request instead of leaving it to time out.
#
# Usage: sudo bash tests/handshake/timeout.sh

SCRIPT="tests/handshake/timeout"
MODULE="luahandshake"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 4

skip_all()
{
	echo "# SKIP: $1"
	ktap_skip "timeout: a queued request times out"
	ktap_skip "timeout: a second hello on the timed-out socket is refused"
	ktap_skip "timeout: the socket closes after the timeout"
	ktap_skip "timeout: the subscriber decides between the wait and ESRCH"
	ktap_totals
	exit 0
}

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || skip_all "$MODULE not loaded"
command -v tlshd > /dev/null 2>&1 && skip_all "tlshd is installed, so an agent may answer"
pgrep -x tlshd > /dev/null 2>&1 && skip_all "a tlshd process is running"

mark_dmesg
run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }

dmesg_since | grep -q "handshake timeout: a queued request times out" ||
	fail "a queued request did not time out"
ktap_pass "timeout: a queued request times out"

dmesg_since | grep -q "handshake timeout: a second hello on the timed-out socket is refused" ||
	fail "a second hello on the timed-out socket was not refused"
ktap_pass "timeout: a second hello on the timed-out socket is refused"

dmesg_since | grep -q "handshake timeout: the socket closes after the timeout" ||
	fail "the socket did not close after the timeout"
ktap_pass "timeout: the socket closes after the timeout"

dmesg_since | grep -q "handshake timeout: the subscriber alone decides between the wait and ESRCH" ||
	fail "the hello did not go back to ESRCH once the subscriber was gone"
ktap_pass "timeout: the subscriber decides between the wait and ESRCH"

ktap_totals

