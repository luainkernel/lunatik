#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests socket:setsockopt(): sets an integer option (SO_RCVBUF) and a packed
# struct option (SO_RCVTIMEO_NEW as a struct __kernel_sock_timeval built with
# the timeval layout codec); with the receive timeout set, a receive with no
# data must return (raise) instead of blocking forever.
#
# Then the two refusals, both on the AF_NETLINK socket the script already
# holds: a level its protocol handler does not own, and an option name that
# handler does not know. Each must raise ENOPROTOOPT rather than pass silently.
#
# Usage: sudo bash tests/socket/setsockopt.sh

SCRIPT="tests/socket/setsockopt"
MODULE="luasocket"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

ktap_header
ktap_plan 4

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}

mark_dmesg
run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }

dmesg_since | grep -q "socket setsockopt: integer option set" || fail "integer option failed"
ktap_pass "setsockopt: integer value sets an int option (SO_RCVBUF)"

dmesg_since | grep -q "socket setsockopt: bounded receive returned" || fail "receive did not time out"
ktap_pass "setsockopt: packed struct value bounds a blocking receive (SO_RCVTIMEO)"

dmesg_since | grep -q "socket setsockopt: unknown level refused" || fail "unknown level was not refused"
ktap_pass "setsockopt: a level the protocol handler does not own raises ENOPROTOOPT"

dmesg_since | grep -q "socket setsockopt: unknown option name refused" || fail "unknown option name was not refused"
ktap_pass "setsockopt: an option name the handler does not know raises ENOPROTOOPT"

ktap_totals

