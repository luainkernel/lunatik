#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A hit looks its handler up, pushes the handler's arguments and runs it in one
# protected call, so a raise anywhere in it is logged with the handler's name
# and the runtime answers the next hit.
#
# raise.lua registers two probes on the personality syscall, which nothing else
# on an idle host calls, and two setarch call it once each:
#
# - a pre and a post handler that each raise on their first hit, the pre keeping
#   the dump closure it was handed: each error is logged once, followed by the
#   handler's name, and on the second hit the kept closure no longer reaches the
#   registers, so they are dropped on the path that raised too. dump is read
#   through debug.getupvalue rather than called, so a build that stopped
#   clearing it is reported instead of running show_regs on a pt_regs that is
#   gone;
# - a handlers table whose __index raises when the first hit looks up pre: the
#   error is logged once, followed by the handler's name, and the second hit
#   finds the handler and runs it.
#
# A build that looks the handler up outside a protected call raises with no
# handler, which is a BUG in hardirq, so the test skips unless the loaded
# luaprobe lists luaprobe_dohandler, the protected half of a hit, in
# /proc/kallsyms.
#
# Usage: sudo bash tests/probe/raise.sh

SCRIPT="tests/probe/raise"
MODULE="luaprobe"
DISPATCH="luaprobe_dohandler"
PREFIX="probe raise test: "

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() { lunatik stop "$SCRIPT" > /dev/null 2>&1; }
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 3

skip_all()
{
	echo "# SKIP: $1"
	ktap_skip "a pre or post handler that raises is logged with its name, and its closures are dropped"
	ktap_skip "a handler lookup that raises is logged with the handler's name, and the next hit runs it"
	ktap_skip "no Lua errors in kernel"
	ktap_totals
	exit 0
}

command -v setarch > /dev/null 2>&1 || skip_all "setarch not available"
grep -Eq " $DISPATCH[[:space:]]\[$MODULE\]$" /proc/kallsyms 2> /dev/null ||
	skip_all "no $DISPATCH in the loaded $MODULE: a raising lookup would have no handler"

# how many lines of the kernel log since the mark carry this
reported() { dmesg_since | grep -cF "$1"; }

mark_dmesg
run_script --context=hardirq "$SCRIPT"
setarch "$(uname -m)" -R true > /dev/null 2>&1
setarch "$(uname -m)" -R true > /dev/null 2>&1
sleep 1
lunatik stop "$SCRIPT" > /dev/null 2>&1

for handler in pre post; do
	logged=$(reported "$MODULE: ${PREFIX}raised: $handler")
	[ "$logged" = 1 ] || fail "the $handler handler's raise was logged $logged times with its name, expected 1"
done
dropped=$(reported "${PREFIX}dropped")
[ "$dropped" = 1 ] || fail "the closure kept from the raising hit was reported dropped $dropped times, expected 1"
ktap_pass "a pre or post handler that raises is logged with its name, and its closures are dropped"

logged=$(reported "$MODULE: ${PREFIX}lookup: pre")
[ "$logged" = 1 ] || fail "the lookup's raise was logged $logged times with the handler's name, expected 1"
answered=$(reported "${PREFIX}answered")
[ "$answered" = 1 ] || fail "the hit after the raising lookup ran its handler $answered times, expected 1"
ktap_pass "a handler lookup that raises is logged with the handler's name, and the next hit runs it"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

