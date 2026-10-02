#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests which argument socket:connect() reads as its flags, and what it answers. An
# AF_INET address is spelled as two arguments, so a call that gives no flags must
# not have its port read as one; an AF_UNIX address is spelled as one, so the
# argument past it is the flags. The AF_INET port is 6922, whose value carries the
# O_NONBLOCK bit, so a port read as flags asks for a non-blocking connect and the
# call answers nil and "EINPROGRESS" instead of true.
#
# The first case discriminates on that port; on an architecture whose O_NONBLOCK is
# not 0o4000, alpha and parisc among them, it passes without discriminating. The
# second pins that a flag given past the port still reaches the kernel, which a fix
# that simply ignored the third argument would fail. The AF_UNIX case pins that a
# one-argument family's index lands past the path and not on it; its listener's
# backlog is 0, which that connect fills. A second socket, whose send timeout keeps
# a connect from waiting for good, then finds no room: with O_NONBLOCK given past
# the path it answers false at once, well before the timeout, which pins that the
# flag reaches the kernel, and through unix:connect, which takes no flags, it
# answers false once the timeout ends its wait.
# inet:connect hands the nonblocking connect's nil and "EINPROGRESS" through, and
# a connect to the port once nothing listens on it pins that a refusal still
# raises its errno's name, ECONNREFUSED. A connect called again on a socket a
# nonblocking one left connecting waits for the handshake, with no flag and no
# timeout, and answers true once it completes; once the peer refused it, the
# call raises ECONNREFUSED. tests/socket/inprogress pins the call that finds the
# handshake still under way.
#
# Usage: sudo bash tests/socket/connect.sh

SCRIPT="tests/socket/connect"
MODULE="luasocket"
SOCKET="/tmp/lunatikconnect.sock"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	rm -f "$SOCKET"
}
trap cleanup EXIT
cleanup

expect() { # expect <line> <description>
	dmesg_since | grep -q "socket connect: $1" || fail "$2"
	ktap_pass "$2"
}

ktap_header
ktap_plan 9

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}

mark_dmesg
run_script "$SCRIPT"
cleanup
check_dmesg || { ktap_totals; exit 1; }

expect "an address and a port alone connect" "socket connect: an AF_INET port is not read as the flags"
expect "a flag past the port reaches the kernel" "socket connect: a flag given past the port reaches the kernel"
expect "a connect called again answers true once the handshake completes" "socket connect: a connect called again answers true once the handshake completes"
expect "inet:connect hands the answer through" "socket connect: inet:connect answers what socket:connect answers"
expect "a refused connect raises" "socket connect: a connect the peer refuses raises ECONNREFUSED"
expect "a connect called again after a refusal raises" "socket connect: a connect called again after the peer refused raises ECONNREFUSED"
expect "a path alone connects" "socket connect: an AF_UNIX path keeps the argument past it for the flags"
expect "a flag past the path reaches the kernel" "socket connect: a flag given past an AF_UNIX path makes a connect with no room answer false at once"
expect "a full backlog answers false once a send timeout ends the wait" "socket connect: unix:connect answers false once a send timeout ends its wait for room"

ktap_totals

