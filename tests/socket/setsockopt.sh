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
# Usage: sudo bash tests/socket/setsockopt.sh

SCRIPT="tests/socket/setsockopt"
MODULE="luasocket"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

ktap_header
ktap_plan 2

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

ktap_totals

