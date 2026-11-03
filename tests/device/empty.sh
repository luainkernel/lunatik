#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# device.new refuses a name that is empty as a C string, which the kernel's
# kobject_add_internal refuses with a WARN once device_create reaches it.
#
# empty.lua asks for a device named "" and for one named "\0x", whose Lua
# length is 2 but which reaches the kernel as "", with its collector stopped,
# so a region a refused name took stays registered until the runtime stops:
#
# - each name raises "bad field 'name' (empty)";
# - a refused name registers nothing: /proc/devices, where alloc_chrdev_region
#   lists a region by the device's name, lists no major with an empty name;
# - the kernel logs no WARNING.
#
# A build without the refusal WARNs on the first name, which panics a host
# booted with panic_on_warn, so the test skips there.
#
# Usage: sudo bash tests/device/empty.sh

SCRIPT="tests/device/empty"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

skip_all() { ktap_header; ktap_plan 1; ktap_skip "$1"; ktap_totals; exit 0; }

cleanup() { lunatik stop "$SCRIPT" 2>/dev/null; }
trap cleanup EXIT
cleanup

[ "$(cat /proc/sys/kernel/panic_on_warn 2>/dev/null || echo 0)" = 0 ] ||
	skip_all "panic_on_warn is set: a build without the refusal would panic on its WARN"

ktap_header
ktap_plan 3

run_test "$SCRIPT" || fail "device.new accepted an empty name, or raised something else"
ktap_pass "a name empty as a C string is refused, naming the field"

grep -qE '^ *[0-9]+ $' /proc/devices && fail "a refused name left a region registered with an empty name"
ktap_pass "a refused name registers nothing"

lunatik stop "$SCRIPT" > /dev/null
check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"

ktap_totals

