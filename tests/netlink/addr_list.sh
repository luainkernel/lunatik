#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests netlink.rt.addr():list(): lists interface addresses and verifies that
# the loopback address 127.0.0.1/8 is present, without a peer. On a dummy
# interface, 192.0.2.1 peer 192.0.2.2 and 2001:db8::1 peer 2001:db8::2, whose
# IFA_ADDRESS carries the peer, report the local address as `address` and the
# other end as `peer`; 192.0.2.3 peer 0.0.0.0, dumped with IFA_LOCAL alone, and
# 2001:db8::3/64, dumped with IFA_ADDRESS alone, report it as `address` without
# a peer.
#
# Usage: sudo bash tests/netlink/addr_list.sh

SCRIPT="tests/netlink/addr_list"
MODULE="luasocket"
NAME="lunatikaddr0"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	ip link del "$NAME" 2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 7

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}

IPV4=1
IPV6=1
{ ip link add "$NAME" type dummy && ip addr add 192.0.2.1 peer 192.0.2.2 dev "$NAME" &&
	ip addr add 192.0.2.3 peer 0.0.0.0 dev "$NAME"; } 2>/dev/null || IPV4=0
{ [ "$IPV4" = 1 ] && ip -6 addr add 2001:db8::1 peer 2001:db8::2 dev "$NAME" &&
	ip -6 addr add 2001:db8::3/64 dev "$NAME"; } 2>/dev/null || IPV6=0

mark_dmesg
run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }

dmesg | grep -q "netlink addr_list: 127.0.0.1 found" || fail "127.0.0.1 not found in addr_list"
ktap_pass "addr_list: 127.0.0.1 present on loopback"

dmesg | grep -q "netlink addr_list: prefix_len ok" || fail "loopback prefix_len != 8"
ktap_pass "addr_list: loopback prefix_len == 8"

dmesg | grep -q "netlink addr_list: loopback without peer" || fail "loopback reports a peer"
ktap_pass "addr_list: loopback reports no peer"

if [ "$IPV4" = 1 ]; then
	dmesg | grep -q "netlink addr_list: ipv4 peer" || fail "192.0.2.1 peer 192.0.2.2 not reported as address and peer"
	ktap_pass "addr_list: an IPv4 address with a peer reports its own address and the peer"

	dmesg | grep -q "netlink addr_list: ipv4 without peer" || fail "192.0.2.3 not reported without a peer"
	ktap_pass "addr_list: an IPv4 address with peer 0.0.0.0, dumped without IFA_ADDRESS, reports its address"
else
	for _ in 1 2; do ktap_skip "addr_list: cannot add IPv4 peer addresses to a dummy"; done
fi

if [ "$IPV6" = 1 ]; then
	dmesg | grep -q "netlink addr_list: ipv6 peer" || fail "2001:db8::1 peer 2001:db8::2 not reported as address and peer"
	ktap_pass "addr_list: an IPv6 address with a peer reports its own address and the peer"

	dmesg | grep -q "netlink addr_list: ipv6 without peer" || fail "2001:db8::3 not reported without a peer"
	ktap_pass "addr_list: an IPv6 address without a peer, dumped without IFA_LOCAL, reports its address"
else
	for _ in 1 2; do ktap_skip "addr_list: cannot add IPv6 addresses to a dummy"; done
fi

ktap_totals

