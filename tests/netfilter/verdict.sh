#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests what a netfilter hook's callback returns. One LOCAL_OUT hook per mark,
# each answering with one case, and one marked ping to 127.0.0.1 per case: a
# callback that returns nothing, a value that is not a number, a verdict spelled
# as a string, a number outside the verdicts, above or below them, even one a
# cast to a C int would read as DROP, or that raises, lets the packet through, as
# ACCEPT does; DROP drops it; and a mark returned beside the verdict is stored in
# the packet, which a later hook matching that mark then drops. Each case also
# reads back the line its callback printed, so a ping that went through proves
# an answer and not a hook that never ran.
#
# Usage: sudo bash tests/netfilter/verdict.sh

SCRIPT="tests/netfilter/verdict"
MODULE="luanetfilter"
PREFIX="netfilter verdict: "
RAISED="${PREFIX}raised"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
}
trap cleanup EXIT
cleanup

# ping <mark>: one marked echo request to the loopback
ping_marked() {
	ping -c 1 -W 1 -m "$1" 127.0.0.1 > /dev/null 2>&1
}

# expect <mark> <case> <passes|drops> <description>
expect() {
	local mark="$1" case="$2" outcome="$3" desc="$4" status

	mark_dmesg
	ping_marked "$mark"
	status=$?
	dmesg_since | grep -qE "${PREFIX}${case}\$" || fail "$desc: the callback did not run"
	if [ "$outcome" = passes ]; then
		[ $status -eq 0 ] || fail "$desc: the packet was dropped"
	else
		[ $status -ne 0 ] || fail "$desc: the packet went through"
	fi
	check_dmesg || { ktap_totals; exit 1; }
	ktap_pass "$desc"
}

ktap_header
ktap_plan 11

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}

mark_dmesg

run_script --context=softirq "$SCRIPT"

expect 211 none passes "a callback that returns nothing accepts the packet"
expect 212 boolean passes "a callback that returns a value that is not a number accepts the packet"
expect 213 string passes "a callback that returns a verdict as a string accepts the packet"
expect 214 range passes "a callback that returns a number outside the verdicts accepts the packet"
expect 220 wrap passes "a callback that returns a number past what a C int holds accepts the packet"
expect 221 negative passes "a callback that returns a negative number accepts the packet"

expect 215 raise passes "a callback that raises accepts the packet"
dmesg_since | grep -qF "$RAISED" || fail "the raise was not logged"
ktap_pass "a callback that raises logs its error"

expect 216 drop drops "a callback that returns DROP drops the packet"
expect 217 accept passes "a callback that returns ACCEPT accepts the packet"

mark_dmesg
ping_marked 218 && fail "a returned mark was not stored in the packet: it went through"
dmesg_since | grep -qE "${PREFIX}remarked\$" || fail "the hook on the returned mark did not run"
ktap_pass "a mark returned beside the verdict is stored in the packet"

lunatik stop "$SCRIPT" 2>/dev/null
check_dmesg || { ktap_totals; exit 1; }
ktap_totals

