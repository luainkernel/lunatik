#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests that an integer a socket hands the kernel is refused as out of bounds past
# the type that takes it, instead of reaching the kernel with its low bits: the
# family, type and protocol socket.new takes, either side of an int; an AF_INET
# address past 32 bits or negative, through bind, connect and send; an AF_NETLINK
# port id or group mask past 32 bits or negative, through bind and connect; a
# receive length below 0 or past INT_MAX; the flags of receive, connect and
# accept and the backlog of listen, past an int; and the level, name and integer
# value of setsockopt, past 32 bits, the value below INT_MIN too. Each value
# past 32 bits carries low bits a truncating build accepts, so that build answers
# with a socket, a bind or EAGAIN rather than the refusal. An unsigned option's
# value, SO_MARK's, is accepted past INT_MAX, up to the u32 it is, and below 0.
#
# Usage: sudo bash tests/socket/bounds.sh

SCRIPT="tests/socket/bounds"
MODULE="luasocket"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 2

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}

run_test "$SCRIPT" || fail "a socket accepted an integer past its type, or raised something else"
ktap_pass "socket: an integer argument past its type is refused as out of bounds"

cleanup
check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"

ktap_totals

