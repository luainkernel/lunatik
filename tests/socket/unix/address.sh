#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the AF_UNIX name getsockname(), getpeername() and receivefrom() answer with.
# The kernel reports a pathname's length with the terminator it added and an abstract
# name's bytes alone, so a bound pathname comes back as the script spelled it, an
# abstract name keeps its leading NUL, an autobound one is the NUL and five
# hexadecimal digits the kernel picked, and an unbound socket is the empty string.
# getpeername() answers with those same names read across a connection, and a receive
# from a peer the kernel names no address for must answer with the message alone. A
# connected AF_UNIX stream is not TCP: it names its sender whenever that peer bound.
#
# The pathname case discriminates on the terminator, the abstract and autobound ones
# on the leading NUL, which stops a C string before its first byte. The unbound peer
# case runs straight after a receive from a bound one, so unfixed it answers with
# that peer's name; what it asserts is the number of values, which a stale address
# of any shape fails.
#
# Usage: sudo bash tests/socket/unix/address.sh

SCRIPT="tests/socket/unix/address"
MODULE="luasocket"
SOCKETS="/tmp/lunatikaddress.sock /tmp/lunatikaddressserver.sock /tmp/lunatikaddressclient.sock"
SOCKETS="$SOCKETS /tmp/lunatikaddresspeer.sock /tmp/lunatikaddresscaller.sock"

source "$(dirname "$(readlink -f "$0")")/../../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	rm -f $SOCKETS
}
trap cleanup EXIT
cleanup

expect() { # expect <line> <description>
	dmesg_since | grep -q "unix address: $1" || fail "$2"
	ktap_pass "$2"
}

ktap_header
ktap_plan 12

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}

[ -e /proc/net/unix ] || {
	echo "# SKIP: no AF_UNIX support"
	ktap_totals
	exit 0
}

mark_dmesg
run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }

expect "unbound getsockname is empty" "unix getsockname: an unbound socket answers with the empty string"
expect "pathname getsockname ok" "unix getsockname: a pathname comes back without the terminator the kernel counts"
expect "abstract getsockname ok" "unix getsockname: an abstract name comes back with its leading NUL"
expect "autobind getsockname ok" "unix getsockname: an autobound name is the NUL and the digits the kernel picked"
expect "pathname getpeername ok" "unix getpeername: a connected socket names the path its peer bound"
expect "receive names a connected stream's peer" "unix receive: a connected stream names the path its peer bound"
expect "unbound getpeername is empty" "unix getpeername: a peer that never bound is the empty string"
expect "abstract getpeername ok" "unix getpeername: an abstract peer comes back with its leading NUL"
expect "receive names no unbound stream peer" "unix receive: a stream from an unbound peer answers with the message alone"
expect "receivefrom names a pathname peer" "unix receivefrom: a datagram names the path its peer bound"
expect "receivefrom names no unbound peer" "unix receivefrom: a datagram from an unbound peer answers with the message alone"
expect "receivefrom names an abstract peer" "unix receivefrom: a datagram names the abstract name its peer bound"

cleanup
check_dmesg || { ktap_totals; exit 1; }

ktap_totals

