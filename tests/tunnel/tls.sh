#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the relay with one end keyed for kTLS, which is the tunnel the epic is
# for: plaintext in on the plain side, a TLS record out on the keyed one, and
# the decrypted plaintext back the other way. Both the relay's keyed end and the
# peer's are keyed with tests/tls/session.lua's fixed vectors, so no handshake
# and no tlshd are involved.
#
# The record type is asserted and not only the bytes: on an unkeyed link
# receiverecord reports nil, so reading 23 is what says the payload travelled as
# a record and the record layer ran. A record the kernel types as something
# other than application data must be read and dropped, since its bytes sent on
# as plaintext would corrupt the far stream, and the application data behind it
# must still arrive; a close_notify is deliberately not the stimulus, because
# what a keyed socket does with reads after an alert is pinned nowhere in the
# tree and the case would rest on it.
#
# Skipped whole where the tls ULP is neither registered nor loadable.
#
# Usage: sudo bash tests/tunnel/tls.sh

SCRIPT="tests/tunnel/tls"
PEER="tests/tunnel/tls_peer"
MODULE="luasocket"

# the payloads tests/tunnel/pair.lua and tls_peer.lua send, as the exact bytes
ATOB="alpha to bravo"
BTOA="bravo to alpha"
CONTROL="handshake bytes"
AFTER="past the control record"
# the TLS content type of application data
DATA=23

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$PEER" > /dev/null 2>&1
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

CASES=(
	"tls: the plain side's payload reaches the keyed far end"
	"tls: it arrives there as application data, so it travelled as a record"
	"tls: the keyed side's payload reaches the plain far end decrypted"
	"tls: a record that is not application data is dropped and the data behind it is not"
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
out=$(lunatik spawn "$SCRIPT" 2>&1)
[ -z "$out" ] || fail "${CASES[0]}: lunatik spawn said: $out"
run_script "$PEER"
check_dmesg || { ktap_totals; exit 1; }

dmesg_since | grep -q "tunnel tls: B read $ATOB as record" || fail "${CASES[0]}"
ktap_pass "${CASES[0]}"

dmesg_since | grep -q "tunnel tls: B read $ATOB as record $DATA$" || fail "${CASES[1]}"
ktap_pass "${CASES[1]}"

dmesg_since | grep -q "tunnel tls: A read $BTOA$" || fail "${CASES[2]}"
ktap_pass "${CASES[2]}"

dmesg_since | grep -q "tunnel tls: A read $AFTER$" || fail "${CASES[3]}: the data behind the record never arrived"
dmesg_since | grep -q "$CONTROL" && fail "${CASES[3]}: the control record's bytes were forwarded"
ktap_pass "${CASES[3]}"

ktap_totals

