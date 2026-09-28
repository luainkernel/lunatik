#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# device.new reads the driver's optional mode into the node it creates.
#
# mode.lua creates lunatik_mode_default without a mode and lunatik_mode_read
# with linux.stat's IRUGO, and asks for lunatik_mode_refused with a mode that
# holds a string, a numeric one included, and a boolean:
#
# - each refused mode raises an error naming the field and the type it got;
# - the device without a mode gets devtmpfs's default, 0600;
# - the device with IRUGO gets a node every user reads, 0444;
# - a refused mode registers nothing: /proc/devices, where alloc_chrdev_region
#   lists a region by the device's name, does not list lunatik_mode_refused,
#   while the script's collector, stopped, keeps every refused object alive.
#
# Usage: sudo bash tests/device/mode.sh

SCRIPT="tests/device/mode"
DEFAULT="lunatik_mode_default"
READABLE="lunatik_mode_read"
REFUSED="lunatik_mode_refused"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() { lunatik stop "$SCRIPT" 2>/dev/null; }
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 5

run_test "$SCRIPT" || fail "device.new accepted a mode that is not a number, or raised something else"
ktap_pass "a mode that is not a number is refused, naming the field"

mode=$(stat -c %a "/dev/$DEFAULT" 2>/dev/null)
[ "$mode" = 600 ] || fail "the device without a mode has a node of mode '$mode', not 600"
ktap_pass "a device without a mode gets devtmpfs's default"

mode=$(stat -c %a "/dev/$READABLE" 2>/dev/null)
[ "$mode" = 444 ] || fail "the device with IRUGO has a node of mode '$mode', not 444"
ktap_pass "a device's mode reaches its node"

grep -qw "$REFUSED" /proc/devices && fail "a refused mode left a region registered under $REFUSED"
ktap_pass "a refused mode registers nothing"

lunatik stop "$SCRIPT" > /dev/null
check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"

ktap_totals

