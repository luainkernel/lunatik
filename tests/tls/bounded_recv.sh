#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests that a receive on a keyed socket comes back, which is the property a
# kernel thread relaying plaintext rests on: tls_rx_rec_wait waits on
# sk_wait_event and never looks at kthread_should_stop, so a receive that is not
# bounded is a thread that cannot be stopped. MSG_DONTWAIT answers EAGAIN
# without waiting, SO_RCVTIMEO answers EAGAIN after the timeout, and the session
# still carries plaintext afterwards rather than being spent by the timeout.
#
# The two waits are measured and the elapsed time is printed, so "returns
# promptly" is a number and not a claim. tests/socket/setsockopt.sh already
# bounds a plain socket's receive; this one earns its place on a keyed socket,
# where the wait is the strparser's and not tcp_recvmsg's.
#
# The pair is keyed over a listener bound to port 0, so the test takes no fixed
# port from the host. Skipped whole where the tls ULP is neither registered nor
# loadable.
#
# Usage: sudo bash tests/tls/bounded_recv.sh

SCRIPT="tests/tls/bounded_recv"
MODULE="luasocket"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

MARKERS=(
	"a non-blocking receive returned in"
	"a receive bounded by SO_RCVTIMEO returned in"
	"the session still carries plaintext after a timeout"
)
CASES=(
	"bounded_recv: MSG_DONTWAIT on an empty keyed socket raises EAGAIN at once"
	"bounded_recv: SO_RCVTIMEO bounds the strparser wait and raises EAGAIN"
	"bounded_recv: a session that timed out still carries plaintext"
)

ktap_header
ktap_plan ${#CASES[@]}

skip_all()
{
	echo "# SKIP: $1"
	for c in "${CASES[@]}"; do ktap_skip "$c"; done
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

# the two waits report what they measured, so the numbers reach the KTAP output
comment "$(dmesg_since | grep -o "tls bounded: a .* returned in .* ms")"

for i in "${!CASES[@]}"; do
	dmesg_since | grep -q "tls bounded: ${MARKERS[$i]}" || fail "${CASES[$i]}"
	ktap_pass "${CASES[$i]}"
done

ktap_totals

