#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Each open of a device has a state of its own, which every callback of that
# open receives, from its open to its release.
#
# file.lua creates lunatik_files, whose open numbers the file, whose write keeps
# what it got on the file and whose read hands it back once, and whose release
# records the file's number, which lunatik_closed reads with a callback written
# without the file:
#
# - two files open at once each read what they wrote;
# - a file that wrote nothing reads nothing;
# - release receives the file its open numbered, which a callback written without
#   the file reads back, as held.lua's callbacks read and write without it.
#
# Usage: sudo bash tests/device/file.sh

SCRIPT="tests/device/file"
FILES="lunatik_files"
CLOSED="lunatik_closed"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	exec 3<&- 4<&- 5<&-
	lunatik stop "$SCRIPT" 2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 4

mark_dmesg
run_script "$SCRIPT"
[ -c "/dev/$FILES" ] && [ -c "/dev/$CLOSED" ] || fail "the script's devices did not appear"

exec 3<> "/dev/$FILES" 4<> "/dev/$FILES" 5<> "/dev/$FILES"
printf one >&3
printf two >&4
second=$(cat <&4)
first=$(cat <&3)
[ "$first" = one ] && [ "$second" = two ] || fail "two files open at once read '$first' and '$second', not what each wrote"
ktap_pass "two files open at once each read what they wrote"

[ -z "$(cat <&5)" ] || fail "a file that wrote nothing read something"
ktap_pass "a file that wrote nothing reads nothing"

exec 3<&-
released=$(cat "/dev/$CLOSED")
[ "$released" = 1 ] || fail "the release of the file numbered 1 recorded '$released'"
exec 5<&-
exec 4<&-
released=$(cat "/dev/$CLOSED")
[ "$released" = 1,3,2 ] || fail "the releases of the files numbered 1, 3 and 2 recorded '$released'"
ktap_pass "release receives the file its open numbered, read back by a callback written without the file"

lunatik stop "$SCRIPT" > /dev/null
check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"

ktap_totals

