#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests that the upcall reaches the kernel's request queue on a host where no
# agent is listening. Every case here ends in a refusal, and which refusal is
# the whole reading: handshake_req_submit answers EINVAL for a socket with no
# struct file and ESRCH only past that test, from genl_has_listeners, so ESRCH
# says the binding attached the file the agent is handed. A socket that was
# never connected answers ENOTCONN instead, which is the binding's own guard;
# without it the call would reach submit and answer ESRCH like the rest.
#
# The second hello on the same socket is the idempotency case: an attach that
# ran twice would overwrite sock->file and orphan the first file, so the
# assertion is that second ESRCH together with a clean kernel log.
#
# Five identities are the accepted end of the bound options.sh refuses six at,
# and the only case anywhere that runs the peerid copy loop through to a
# submit: a loop that wrote past its own array, or a bound off by one, answers
# something other than ESRCH here. The client x509 and the server psk hellos
# after it are the two arms no other case selects, and together with the three
# above them they are every hello the two functions can pick. With no agent each
# answers ESRCH, so what they pin is that the arm is reachable and submits, not
# which of the five was taken.
#
# Skipped whole where tlshd is installed or running: an agent would accept the
# request and every outcome here would change.
#
# Usage: sudo bash tests/handshake/upcall.sh

SCRIPT="tests/handshake/upcall"
MODULE="luahandshake"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 7

skip_all()
{
	echo "# SKIP: $1"
	ktap_skip "upcall: an unconnected socket raises ENOTCONN"
	ktap_skip "upcall: a client hello reaches submit"
	ktap_skip "upcall: a second hello on the same socket reaches submit"
	ktap_skip "upcall: a server x509 hello reaches submit"
	ktap_skip "upcall: five identities reach submit"
	ktap_skip "upcall: a client x509 hello reaches submit"
	ktap_skip "upcall: a server psk hello reaches submit"
	ktap_totals
	exit 0
}

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || skip_all "$MODULE not loaded"
command -v tlshd > /dev/null 2>&1 && skip_all "tlshd is installed, so an agent may answer"
pgrep -x tlshd > /dev/null 2>&1 && skip_all "a tlshd process is running"

mark_dmesg
run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }

dmesg_since | grep -q "handshake upcall: an unconnected socket is refused" ||
	fail "an unconnected socket was not refused"
ktap_pass "upcall: an unconnected socket raises ENOTCONN"

dmesg_since | grep -q "handshake upcall: a client hello reaches submit and finds no agent" ||
	fail "a client hello did not reach submit"
ktap_pass "upcall: a client hello reaches submit"

dmesg_since | grep -q "handshake upcall: a second hello on the same socket reaches submit" ||
	fail "a second hello on the same socket did not reach submit"
ktap_pass "upcall: a second hello on the same socket reaches submit"

dmesg_since | grep -q "handshake upcall: a server x509 hello reaches submit" ||
	fail "a server x509 hello did not reach submit"
ktap_pass "upcall: a server x509 hello reaches submit"

dmesg_since | grep -q "handshake upcall: five identities reach submit" ||
	fail "five identities did not reach submit"
ktap_pass "upcall: five identities reach submit"

dmesg_since | grep -q "handshake upcall: a client x509 hello reaches submit" ||
	fail "a client x509 hello did not reach submit"
ktap_pass "upcall: a client x509 hello reaches submit"

dmesg_since | grep -q "handshake upcall: a server psk hello reaches submit" ||
	fail "a server psk hello did not reach submit"
ktap_pass "upcall: a server psk hello reaches submit"

ktap_totals

