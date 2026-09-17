#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests socket:receiverecord() and socket:sendrecord() on a socket that carries
# no ULP, which is what the two methods do when nothing decodes their control
# message: a receive reports the bytes and no record type, and a send hands the
# payload over unchanged, because sock_cmsg_send skips every control message
# whose level is not SOL_SOCKET. Then the two guards of the new path: a record
# type wider than the byte it travels in is refused naming the argument, and
# MSG_DONTWAIT on an empty socket raises EAGAIN, which says the flags argument
# reaches kernel_recvmsg.
#
# Each case connects a client to its own listener bound to port 0 and accepts
# it, so the test takes no fixed port from the host. No CONFIG_TLS, no tls ULP.
#
# Usage: sudo bash tests/socket/record.sh

SCRIPT="tests/socket/record"
MODULE="luasocket"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 4

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_skip "record: a receive on an unkeyed socket reports no record type"
	ktap_skip "record: a send on an unkeyed socket ignores the record type"
	ktap_skip "record: a record type outside 0-255 is refused"
	ktap_skip "record: a non-blocking receive on an empty socket raises EAGAIN"
	ktap_totals
	exit 0
}

mark_dmesg
run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }

dmesg_since | grep -q "socket record: an unkeyed receive reports no record type" ||
	fail "record: a receive on an unkeyed socket reports no record type"
ktap_pass "record: a receive on an unkeyed socket reports no record type"

dmesg_since | grep -q "socket record: an unkeyed send ignores the record type" ||
	fail "record: a send on an unkeyed socket ignores the record type"
ktap_pass "record: a send on an unkeyed socket ignores the record type"

dmesg_since | grep -q "socket record: a record type outside a byte is refused" ||
	fail "record: a record type outside 0-255 is refused"
ktap_pass "record: a record type outside 0-255 is refused"

dmesg_since | grep -q "socket record: a non-blocking receive on an empty socket raises EAGAIN" ||
	fail "record: a non-blocking receive on an empty socket raises EAGAIN"
ktap_pass "record: a non-blocking receive on an empty socket raises EAGAIN"

ktap_totals

