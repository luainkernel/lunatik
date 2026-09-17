#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests how the options pick the hello, and what the binding refuses before it
# picks one. A server hello with no credentials is refused because the kernel
# publishes no anonymous server hello, and nothing else here raises that
# message; a fall-through to the client's anonymous arm would answer ESRCH.
# More identities than ta_my_peerids holds, a cert with no privkey, and peerids
# beside a cert are the binding's own refusals, ahead of the copy loop and of a
# submit that would fail only at an agent this host has none of. The last of
# them is the one that keeps the psk and x509 arms apart: with it gone the
# credentials of both reach tls_client_hello_psk, which ignores the cert.
#
# The last four are the types and the bounds rather than the combinations: a
# peerid of the wrong type, a peerid and a timeout each wider than the field
# that carries it, and an option field of the wrong type, every one of which
# would otherwise reach the kernel silently truncated or as a zero.
#
# The last two are argument 1 rather than the options: luasocket_openfile is a
# second reader of a socket private, and it checks the class before it reads the
# private and the private before it attaches a file. An object of another class
# read through that pointer is a kernel crash one line of script reaches.
#
# The empty identity list is the one case that reaches the kernel:
# tls_client_hello_psk refuses it with EINVAL before allocating, so that errno
# is also the reading that the psk arm was the one selected.
#
# No case reaches handshake_req_submit, so an installed agent changes nothing
# here and the suite needs no skip for one. A refusal carries a Lua position
# prefix, which KTAP_ERRORS matches, so it is asserted with a plain string
# search and never printed; the bare errno the kernel answers carries none, and
# its case prints it on a failure.
#
# Usage: sudo bash tests/handshake/options.sh

SCRIPT="tests/handshake/options"
MODULE="luahandshake"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 11

skip_all()
{
	echo "# SKIP: $1"
	ktap_skip "options: a server hello with no credentials is refused"
	ktap_skip "options: an empty peerids list selects the psk arm"
	ktap_skip "options: more identities than the kernel holds are refused"
	ktap_skip "options: a cert with no privkey is refused"
	ktap_skip "options: peerids beside a cert is refused"
	ktap_skip "options: a peerid that is not a number is refused"
	ktap_skip "options: a peerid wider than the kernel's field is refused"
	ktap_skip "options: a field of the wrong type is refused"
	ktap_skip "options: a timeout wider than the kernel's field is refused"
	ktap_skip "options: an object of another class is refused"
	ktap_skip "options: a closed socket is refused"
	ktap_totals
	exit 0
}

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || skip_all "$MODULE not loaded"

mark_dmesg
run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }

dmesg_since | grep -q "handshake options: a server hello needs credentials" ||
	fail "a server hello with no credentials was not refused"
ktap_pass "options: a server hello with no credentials is refused"

dmesg_since | grep -q "handshake options: an empty peerids list selects the psk arm" ||
	fail "an empty peerids list did not reach the psk hello"
ktap_pass "options: an empty peerids list selects the psk arm"

dmesg_since | grep -q "handshake options: six identities are refused" ||
	fail "six identities were not refused"
ktap_pass "options: more identities than the kernel holds are refused"

dmesg_since | grep -q "handshake options: a cert with no privkey is refused" ||
	fail "a cert with no privkey was not refused"
ktap_pass "options: a cert with no privkey is refused"

dmesg_since | grep -q "handshake options: peerids beside a cert is refused" ||
	fail "peerids beside a cert was not refused"
ktap_pass "options: peerids beside a cert is refused"

dmesg_since | grep -q "handshake options: a peerid that is not a number is refused" ||
	fail "a peerid that is not a number was not refused"
ktap_pass "options: a peerid that is not a number is refused"

dmesg_since | grep -q "handshake options: a peerid wider than the kernel's field is refused" ||
	fail "a peerid wider than the kernel's field was not refused"
ktap_pass "options: a peerid wider than the kernel's field is refused"

dmesg_since | grep -q "handshake options: a field of the wrong type is refused" ||
	fail "a field of the wrong type was not refused"
ktap_pass "options: a field of the wrong type is refused"

dmesg_since | grep -q "handshake options: a timeout wider than the kernel's field is refused" ||
	fail "a timeout wider than the kernel's field was not refused"
ktap_pass "options: a timeout wider than the kernel's field is refused"

dmesg_since | grep -q "handshake options: an object of another class is refused" ||
	fail "an object of another class was not refused"
ktap_pass "options: an object of another class is refused"

dmesg_since | grep -q "handshake options: a closed socket is refused" ||
	fail "a closed socket was not refused"
ktap_pass "options: a closed socket is refused"

ktap_totals

