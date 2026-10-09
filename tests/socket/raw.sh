#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests socket.raw's new, which creates an AF_PACKET socket and binds it. The script
# reads each socket's address back through getsockname(): new binds the ethertype and
# the interface it names, and in place of one it does not name, every ethertype,
# ETH_P_ALL, or every interface, index 0.
#
# When the bind raises, on an interface index no device holds or on one past the
# bounds the binding takes, new raises that error unchanged once it has closed the
# socket. new creates the socket with no ethertype and the bind names it, so a socket
# a failed bind leaves is listed in /proc/net/packet as SOCK_RAW with no ethertype and
# no interface. The script stops its collector, which keeps such a socket alive until
# the runtime stops, and the test reads the sockets listed that way before the run and
# after it: one that appeared during the run and is still listed is one new left open.
#
# Usage: sudo bash tests/socket/raw.sh

SCRIPT="tests/socket/raw"
PROTO="88b5"
ALL="0003"
MODULE="luasocket"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
}
trap cleanup EXIT
cleanup

# the inodes of the SOCK_RAW packet sockets /proc/net/packet lists with no ethertype and no interface
unbound() { awk '$3 == 3 && $4 == "0000" && $5 == 0 { print $9 }' /proc/net/packet | sort; }

# said <pattern>: the script reported what new did, as the pattern reads it
said() { dmesg_since | grep -q "socket raw: new $1"; }
answer() { dmesg_since | grep "socket raw: new $1"; }

ktap_header
ktap_plan 7

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}

[ -e /proc/net/packet ] || {
	echo "# SKIP: no AF_PACKET support"
	ktap_totals
	exit 0
}

LO=$(cat /sys/class/net/lo/ifindex)
before=$(unbound)

mark_dmesg
run_script "$SCRIPT"
after=$(unbound)
check_dmesg || { ktap_totals; exit 1; }

said "binds $PROTO on $LO\$" || fail "unexpected address: $(answer binds)"
ktap_pass "raw: new binds the ethertype on the interface it names"

said "with no interface binds $PROTO on 0\$" || fail "unexpected address: $(answer 'with no interface')"
ktap_pass "raw: new with no interface binds the ethertype on every interface"

said "with no ethertype binds $ALL on $LO\$" || fail "unexpected address: $(answer 'with no ethertype')"
ktap_pass "raw: new with no ethertype binds every ethertype on the interface"

said "with no argument binds $ALL on 0\$" || fail "unexpected address: $(answer 'with no argument')"
ktap_pass "raw: new with no argument binds every ethertype on every interface"

said "on an absent interface raises ENODEV\$" || fail "unexpected answer: $(answer 'on an absent interface')"
ktap_pass "raw: new raises the bind's ENODEV on an absent interface"

said "on a negative interface raises .*out of bounds" || fail "unexpected answer: $(answer 'on a negative interface')"
ktap_pass "raw: new raises the bind's refusal of an interface index out of bounds"

left=$(comm -13 <(echo "$before") <(echo "$after") | grep -c .)
[ "$left" -eq 0 ] || fail "the failed binds left $left socket(s) with no ethertype in /proc/net/packet"
ktap_pass "raw: new closes the socket whose bind failed"

ktap_totals

