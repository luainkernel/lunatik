#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests which argument socket:connect() reads as its flags. An AF_INET address is
# spelled as two arguments, so a call that gives no flags must not have its port
# read as one; an AF_UNIX address is spelled as one, so the argument past it is the
# flags. The AF_INET port is 6922, whose value carries the O_NONBLOCK bit, so a port
# read as flags asks for a non-blocking connect and the call answers EINPROGRESS
# instead of connecting.
#
# The first case discriminates on that port; on an architecture whose O_NONBLOCK is
# not 0o4000, alpha and parisc among them, it passes without discriminating. The
# second pins that a flag given past the port still reaches the kernel, which a fix
# that simply ignored the third argument would fail. The AF_UNIX case guards the
# families whose address is one argument.
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
ktap_plan 3

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}

mark_dmesg
run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }

expect "an address and a port alone connect" "socket connect: an AF_INET port is not read as the flags"
expect "a flag past the port reaches the kernel" "socket connect: a flag given past the port reaches the kernel"
expect "a path alone connects" "socket connect: an AF_UNIX path keeps the argument past it for the flags"

cleanup
check_dmesg || { ktap_totals; exit 1; }

ktap_totals

