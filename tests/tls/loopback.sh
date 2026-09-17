#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the plaintext data path a keyed socket becomes: over a loopback pair
# whose two ends carry the same session on both directions, a send on one side
# comes back decrypted on the other with the record type reported as application
# data, which is what says the record layer ran at all. The reverse direction
# proves both were keyed and not only the one written first; TLS 1.2 and the
# zero-salt cipher are the version and cipher cells; and a record read in two
# calls carries its type on the second read too, which process_rx_list attaches
# and a binding that only looked at the first record of a receive would miss.
#
# Each case keys its own pair over a listener bound to port 0 and closes both
# ends before the next, so the test takes no fixed port from the host and a
# failing case leaves nothing behind. Skipped whole where the tls ULP is neither
# registered nor loadable, and the ChaCha20-Poly1305 case alone where the
# install answers ENOENT because the kernel builds no AEAD for it.
#
# Usage: sudo bash tests/tls/loopback.sh

SCRIPT="tests/tls/loopback"
MODULE="luasocket"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

MARKERS=(
	"a TLS 1.3 session carries plaintext"
	"the reverse direction carries plaintext too"
	"a TLS 1.2 session carries plaintext"
	"the zero-salt cipher carries plaintext"
	"a record read in two calls reports its type twice"
)
CASES=(
	"loopback: a TLS 1.3 AES-GCM-128 session relays plaintext"
	"loopback: the reverse direction of that session relays plaintext"
	"loopback: a TLS 1.2 session relays plaintext"
	"loopback: the zero-salt cipher relays plaintext"
	"loopback: a record read in two calls reports its type on both"
)

# a case the kernel can decline for a reason of its own: the marker the script
# prints in place of the case's own, and what makes that a skip
SKIPMARKERS=(
	[3]="the zero-salt cipher is unavailable (ENOENT)"
)
SKIPREASONS=(
	[3]="the kernel builds no rfc7539(chacha20,poly1305)"
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

for i in "${!CASES[@]}"; do
	if [ -n "${SKIPMARKERS[$i]}" ] && dmesg_since | grep -q "tls loopback: ${SKIPMARKERS[$i]}"; then
		ktap_skip "${CASES[$i]}: ${SKIPREASONS[$i]}"
		continue
	fi
	dmesg_since | grep -q "tls loopback: ${MARKERS[$i]}" || fail "${CASES[$i]}"
	ktap_pass "${CASES[$i]}"
done

ktap_totals

