#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A monitored method leaves the calling runtime's collector as it found it.
#
# lunatik_monitor stops the collector around a method, so no finalizer runs under the
# object's lock, and restarts it after the method only if it was running: a script that
# ran collectgarbage("stop") keeps it stopped until it restarts it. collector.lua stops
# its collector and calls a fifo's push, which returns, and its pop past the capacity,
# which raises, then restarts the collector and calls pop again both ways, and after
# each call reads collectgarbage("isrunning"): stopped after the calls made while
# stopped, running after the others.
#
# Usage: sudo bash tests/monitor/collector.sh

SCRIPT="tests/monitor/collector"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() { lunatik stop "$SCRIPT" 2>/dev/null; }
trap cleanup EXIT
cleanup

# passed <case>: tests.lib reports PASS and the name of each case that passed
passed() { dmesg_since | grep -qE "PASS[[:space:]]$1\$"; }

ktap_header
ktap_plan 5

mark_dmesg
run_script "$SCRIPT"
lunatik stop "$SCRIPT" > /dev/null

for case in \
	"a monitored method that returns leaves a stopped collector stopped" \
	"a monitored method that raises leaves a stopped collector stopped" \
	"a monitored method that returns leaves a running collector running" \
	"a monitored method that raises leaves a running collector running"; do
	passed "$case" || fail "$case: $(dmesg_since | grep -F "$case")"
	ktap_pass "$case"
done

check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"

ktap_totals

