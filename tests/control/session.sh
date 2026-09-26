#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Each open of /dev/lunatik is a session: a chunk written on it is answered on
# it, with the status before the values, and the answer is read whole.
#
# The cases write chunks to the device through descriptors of their own, as the
# CLI does, and force the order a race would take rather than wait for one:
#
# - two sessions whose requests interleave, each written before either is read,
#   each read their own reply;
# - a reply longer than one read of cat arrives whole;
# - a session that wrote nothing reads nothing;
# - a chunk that returns replies true and its values, tab-separated; one that
#   raises, and one that does not load, reply false and the message.
#
# Usage: sudo bash tests/control/session.sh

DEVICE="/dev/lunatik"
LONG=200000
TAB=$'\t'

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	exec 3<&- 4<&- 5<&-
}
trap cleanup EXIT
cleanup

skip_all() { ktap_header; ktap_plan 1; ktap_skip "$1"; ktap_totals; exit 0; }

[ -c "$DEVICE" ] || skip_all "$DEVICE not loaded"

ktap_header
ktap_plan 5

mark_dmesg
exec 3<> "$DEVICE" 4<> "$DEVICE" 5<> "$DEVICE"

printf 'return "one"' >&3
printf 'return "two"' >&4
second=$(cat <&4)
first=$(cat <&3)
[ "$first" = "true${TAB}one" ] && [ "$second" = "true${TAB}two" ] ||
	fail "two interleaved sessions read '$first' and '$second', not their own replies"
ktap_pass "two sessions whose requests interleave each read their own reply"

printf 'return string.rep("x", %d)' "$LONG" >&3
reply=$(cat <&3)
[ "${#reply}" -eq $((LONG + 5)) ] || fail "a reply of $((LONG + 5)) bytes arrived as ${#reply}"
ktap_pass "a reply longer than one read arrives whole"

[ -z "$(cat <&5)" ] || fail "a session that wrote nothing read something"
ktap_pass "a session that wrote nothing reads nothing"

printf 'return 1, "a"' >&3
values=$(cat <&3)
printf 'error("boom", 0)' >&3
raised=$(cat <&3)
printf 'return (' >&3
unloaded=$(cat <&3)
[ "$values" = "true${TAB}1${TAB}a" ] || fail "a chunk returning 1 and 'a' replied '$values'"
[ "$raised" = "false${TAB}boom" ] || fail "a chunk raising 'boom' replied '$raised'"
[[ "$unloaded" == "false${TAB}"* ]] || fail "a chunk that does not load replied '$unloaded'"
ktap_pass "a reply carries the status before the values: true and the values, or false and the message"

cleanup
check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"

ktap_totals

