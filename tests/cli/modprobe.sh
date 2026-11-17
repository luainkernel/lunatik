#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A loader other than lunatik load, modprobe here, makes /dev/lunatik from
# lunatik, luarcu, luadevice and lunatik_run alone, and starts no runner:
#
# - list starts the runner, though luathread, which lunatik.runner requires, is
#   not loaded, and exits 0 with nothing printed;
# - unload with no runner started exits 0 with nothing printed and leaves no
#   Lunatik module loaded.
#
# Usage: sudo bash tests/cli/modprobe.sh

DRIVER="lunatik luadevice lunatik_run"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik load 2>/dev/null
}
trap cleanup EXIT
cleanup

# from no Lunatik module loaded, modprobe makes /dev/lunatik with the driver's modules and not luathread
driver() {
	lunatik unload || fail "the modules did not unload"
	modprobe -a $DRIVER || fail "modprobe did not load $DRIVER"
	[ -c /dev/lunatik ] && [ ! -d /sys/module/luathread ] ||
		fail "modprobe of $DRIVER made no /dev/lunatik or loaded luathread"
}

ktap_header
ktap_plan 3

mark_dmesg

driver
cli list
[ "$status" -eq 0 ] && [ -z "$out" ] && [ -z "$err" ] ||
	fail "list with luathread not loaded exited $status with '$out' on stdout and '$err' on stderr"
ktap_pass "list with luathread not loaded starts the runner and exits 0"

driver
cli unload
[ "$status" -eq 0 ] && [ -z "$out" ] && [ -z "$err" ] && [ ! -d /sys/module/lunatik ] ||
	fail "unload with no runner started exited $status with '$err' on stderr, or left the core loaded"
ktap_pass "unload with no runner started exits 0 and leaves no module loaded"

check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"

ktap_totals

