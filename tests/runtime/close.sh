#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A device, a notifier, an fsnotify watch and a probe each offer __close equal
# to their stop, and a to-be-closed variable holding one stops it at the end of
# its scope.
#
# close.lua finds one function under __close and stop in each handle's
# metatable, lets a to-be-closed variable holding the handle go out of scope,
# and reads it stopped: a device of the same name is created again, which a
# device left in place refuses; a watch refuses a mark with "closed object"; a
# notifier, whose stop only takes the callback off, takes a second stop as it
# takes any. A probe needs a hardirq runtime, and its stop sleeps, so
# close_probe.lua does the same while its body loads, and its kprobe refuses an
# enable with "closed object"; an assertion it fails raises from the runtime
# close.lua creates. A build without the __close fails at the to-be-closed
# variable, which Lua refuses for a value with no __close.
#
# Usage: sudo bash tests/runtime/close.sh

SCRIPT="tests/runtime/close"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() { lunatik stop "$SCRIPT" > /dev/null 2>&1; }
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

if ! modinfo luafsnotify > /dev/null 2>&1 || ! modinfo luaprobe > /dev/null 2>&1; then
	ktap_skip "runtime/close: luafsnotify or luaprobe not installed"
elif run_test "$SCRIPT"; then
	ktap_pass "runtime/close"
else
	ktap_fail "runtime/close"
fi

ktap_totals

