#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# device.new uses the driver's name as given, never as a format, and refuses a
# name that is empty as a C string, which the kernel's kobject_add_internal
# refuses with a WARN once device_create reaches it.
#
# name.lua asks for a device named "" and for one named "\0x", whose Lua length
# is 2 but which reaches the kernel as "", with its collector stopped, so a
# region a refused name took stays registered until the runtime stops. It then
# creates lunatik%%device, whose '%%' a format turns into one '%' without
# reading an argument, so a build that formats the name lists lunatik%device
# and fails the case rather than crash:
#
# - each empty name raises "bad field 'name' (empty)";
# - a refused name registers nothing: /proc/devices, where alloc_chrdev_region
#   lists a region by the device's name, lists no major with an empty name;
# - /sys/class/luadevice/ lists the device under its name, byte for byte;
# - devtmpfs creates the node /dev/<name> under the same name.
#
# No case names a device with a directive that takes an argument, which such a
# build reads from no argument.
#
# Usage: sudo bash tests/device/name.sh

SCRIPT="tests/device/name"
NAME="lunatik%%device"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() { lunatik stop "$SCRIPT" 2>/dev/null; }
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 5

mark_dmesg
run_script "$SCRIPT"
ktap_pass "a name empty as a C string is refused, naming the field"

grep -qE '^ *[0-9]+ $' /proc/devices && fail "a refused name left a region registered with an empty name"
ktap_pass "a refused name registers nothing"

[ -e "/sys/class/luadevice/$NAME" ] ||
	fail "/sys/class/luadevice/ lists '$(ls /sys/class/luadevice/ | tr '\n' ' ')', not $NAME"
ktap_pass "sysfs lists the device under its name as given"

[ -c "/dev/$NAME" ] || fail "no character node /dev/$NAME"
ktap_pass "the node takes the device's name as given"

lunatik stop "$SCRIPT" > /dev/null
check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"

ktap_totals

