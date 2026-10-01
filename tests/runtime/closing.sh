#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A finalizer that runs as its runtime closes registers nothing.
#
# A runtime closes through a stop, which clears its private before lua_close,
# or through the drop of its last reference, which closes it at a zero count.
# closing_netfilter, run in softirq context, closing_fsnotify and closing_thread,
# in process context, register a hook, a watch and a kernel thread from a
# sentinel as `lunatik stop` closes them, and report the refusal. A build
# without it registers from the closing state, and the hook or the watch
# outlives the runtime that would dispatch it into its module's unload, so
# those two cases skip unless the loaded module is the installed one and that
# file carries the message: the check is inline, so no symbol of its own is in
# /proc/kallsyms. closing_thread calls thread.run with no arguments, which
# raises before it creates anything on any build. closing.lua then creates
# closing_thread and collects it, and its sentinel is refused at the last put
# too.
#
# Usage: sudo bash tests/runtime/closing.sh

SCRIPT="tests/runtime/closing"
REGISTER="tests/runtime/closing_"
REFUSAL="not allowed while the runtime closes"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	lunatik stop "${REGISTER}netfilter" > /dev/null 2>&1
	lunatik stop "${REGISTER}fsnotify" > /dev/null 2>&1
	lunatik stop "${REGISTER}thread" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 5

reported()
{
	dmesg_since | grep -cF "closing test: $1"
}

carries()
{
	local module="lua$1" loaded="/sys/module/lua$1/srcversion"

	{ [ ! -e "$loaded" ] || [ "$(cat "$loaded")" = "$(modinfo -F srcversion "$module" 2> /dev/null)" ]; } &&
		grep -qaF "$REFUSAL" "$(modinfo -n "$module" 2> /dev/null)" 2> /dev/null
}

refused()
{
	local name=$1 context=$2

	run_script --context="$context" "$REGISTER$name"
	lunatik stop "$REGISTER$name" > /dev/null 2>&1
	[ "$(reported "$name $REFUSAL")" = 1 ] || {
		comment "$(dmesg_since | grep -F "closing test: $name")"
		fail "a $name a finalizer made while its $context runtime stopped was not refused"
	}
	ktap_pass "a $name a finalizer makes while its $context runtime stops is refused"
}

guarded()
{
	if carries "$1"; then
		refused "$@"
	else
		ktap_skip "the loaded lua$1 does not carry the refusal: a $1 made as the runtime closes would outlive it"
	fi
}

mark_dmesg
guarded netfilter softirq
guarded fsnotify process
refused thread process

run_script "$SCRIPT"
lunatik stop "$SCRIPT" > /dev/null 2>&1

[ "$(reported "thread $REFUSAL")" = 2 ] || {
	comment "$(dmesg_since | grep -F "closing test: thread")"
	fail "a thread a finalizer made while the collector closed its runtime was not refused"
}
ktap_pass "a thread a finalizer makes while the collector closes its runtime is refused"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

