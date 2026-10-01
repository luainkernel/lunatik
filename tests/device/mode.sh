#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# device.new reads the driver's optional mode into the node it creates.
#
# mode.lua creates lunatik_mode_default without a mode, lunatik_mode_read
# with linux.stat's IRUGO and lunatik_mode_special with IRUGO and the setuid,
# setgid and sticky bits, which S_IALLUGO adds to the permissions, and asks for
# lunatik_mode_refused with a mode that holds a string, a numeric one included,
# and a boolean, and with one past S_IALLUGO: IFDIR over IRUGO, which devtmpfs
# would OR with S_IFCHR into a block node, the bit above S_IALLUGO, and -1:
#
# - each refused mode raises an error naming the field and the type it got, or
#   naming the field out of bounds;
# - the device without a mode gets devtmpfs's default, 0600;
# - the device with IRUGO gets a node every user reads, 0444, and the one with
#   the special bits a node that carries them, 7444, as a character device;
# - a refused mode registers nothing: /proc/devices, where alloc_chrdev_region
#   lists a region by the device's name, does not list lunatik_mode_refused,
#   and /dev has no node by that name, while the script's collector, stopped,
#   keeps every refused object alive.
#
# Usage: sudo bash tests/device/mode.sh

SCRIPT="tests/device/mode"
DEFAULT="lunatik_mode_default"
READABLE="lunatik_mode_read"
SPECIAL="lunatik_mode_special"
REFUSED="lunatik_mode_refused"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

# a build that takes a file type makes a block node devtmpfs does not remove with its device
cleanup() { lunatik stop "$SCRIPT" 2>/dev/null; rm -f "/dev/$REFUSED"; }
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 6

run_test "$SCRIPT" || fail "device.new accepted a mode that is not a number or past S_IALLUGO, or raised something else"
ktap_pass "a mode that is not a number or past S_IALLUGO is refused, naming the field"

mode=$(stat -c %a "/dev/$DEFAULT" 2>/dev/null)
[ "$mode" = 600 ] || fail "the device without a mode has a node of mode '$mode', not 600"
ktap_pass "a device without a mode gets devtmpfs's default"

mode=$(stat -c %a "/dev/$READABLE" 2>/dev/null)
[ "$mode" = 444 ] || fail "the device with IRUGO has a node of mode '$mode', not 444"
ktap_pass "a device's mode reaches its node"

mode=$(stat -c %a:%F "/dev/$SPECIAL" 2>/dev/null)
[ "$mode" = "7444:character special file" ] || fail "the device with the special bits has a node '$mode', not 7444"
ktap_pass "the setuid, setgid and sticky bits reach a character node"

grep -qw "$REFUSED" /proc/devices && fail "a refused mode left a region registered under $REFUSED"
[ -e "/dev/$REFUSED" ] && fail "a refused mode left a node under /dev/$REFUSED"
ktap_pass "a refused mode registers nothing"

lunatik stop "$SCRIPT" > /dev/null
check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"

ktap_totals

