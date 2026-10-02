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
# - a pre handler that raises on its first hit and a post handler that raises on
#   its second: each error is logged once, followed by the handler's name, and the
#   regs the post kept on the raising hit, the last handler the runtime runs, no
#   longer reach the registers once no handler runs, so they are cleared on the
#   path that raised too. A finalizer reads them at the stop, before the close
#   finalizes them, through argument(-1), which checks the object before the
#   index, so a build that stopped clearing them raises out of bounds and is
#   reported without reading a pt_regs that is gone;
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
	ktap_skip "a pre or post handler that raises is logged with its name, and its regs are cleared"
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
[ "$dropped" = 1 ] || fail "the regs kept from the raising hit were reported cleared $dropped times, expected 1"
ktap_pass "a pre or post handler that raises is logged with its name, and its regs are cleared"

logged=$(reported "$MODULE: ${PREFIX}lookup: pre")
[ "$logged" = 1 ] || fail "the lookup's raise was logged $logged times with the handler's name, expected 1"
answered=$(reported "${PREFIX}answered")
[ "$answered" = 1 ] || fail "the hit after the raising lookup ran its handler $answered times, expected 1"
ktap_pass "a handler lookup that raises is logged with the handler's name, and the next hit runs it"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

