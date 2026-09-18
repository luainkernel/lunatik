#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the tls ULP attach over socket:setsockopt(): SOL_TCP/TCP_ULP with the
# name "tls" raises ENOTCONN on a socket that was never connected, succeeds on
# one connected to a loopback listener, and raises EEXIST the second time.
# That second refusal is what says the first attach took: the attached ULP
# forwards a SOL_TCP option back to tcp_setsockopt, and a script has no
# getsockopt to read the ULP name back with.
#
# The stimulus is a listener bound to port 0 and a socket connected to the port
# getsockname reads back, so the test takes no fixed port from the host. Skipped
# where the tls ULP is neither registered nor loadable on demand.
#
# Usage: sudo bash tests/socket/ulp.sh

SCRIPT="tests/socket/ulp"
MODULE="luasocket"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 3

skip_all()
{
	echo "# SKIP: $1"
	ktap_skip "ulp: an attach on an unconnected socket raises ENOTCONN"
	ktap_skip "ulp: an attach on a connected socket takes"
	ktap_skip "ulp: a second attach raises EEXIST"
	ktap_totals
	exit 0
}

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || skip_all "$MODULE not loaded"

# registered (built in, or already loaded), or loadable: the attach autoloads
# through request_module("tcp-ulp-tls")
grep -qw tls /proc/sys/net/ipv4/tcp_available_ulp 2> /dev/null ||
	grep -q '^alias tcp-ulp-tls ' "/lib/modules/$(uname -r)/modules.alias" 2> /dev/null ||
	skip_all "the tls ULP is neither registered nor loadable"

mark_dmesg
run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }

dmesg_since | grep -q "socket ulp: unconnected attach refused" || fail "unconnected attach was not refused"
ktap_pass "ulp: an attach on an unconnected socket raises ENOTCONN"

dmesg_since | grep -q "socket ulp: attached to a connected socket" || fail "attach on a connected socket failed"
ktap_pass "ulp: an attach on a connected socket takes"

dmesg_since | grep -q "socket ulp: second attach refused" || fail "second attach was not refused"
ktap_pass "ulp: a second attach raises EEXIST"

ktap_totals

