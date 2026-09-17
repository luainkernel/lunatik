#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests what the kernel makes of the blob tls.pack builds, over setsockopt at
# SOL_TLS: it is refused with ENOPROTOOPT on a socket whose ULP was never
# attached, a TLS 1.3 and a TLS 1.2 session install, a direction already keyed
# answers EBUSY, and a blob one byte short, a version the kernel does not
# implement, a second cipher on the other direction, and ARIA-GCM under anything
# but TLS 1.2 each answer EINVAL.
#
# Each case connects a client to its own listener bound to port 0, so the test
# takes no fixed port from the host. The ULP attach autoloads tls.ko through
# request_module, which sleeps, so the script runs in process context.
#
# Skipped whole where the tls ULP is neither registered nor loadable. Two cases
# skip alone: ChaCha20-Poly1305 where the kernel cannot allocate its AEAD, which
# the install reports as ENOENT, and ARIA where the uapi header predates it.
#
# Usage: sudo bash tests/tls/key.sh

SCRIPT="tests/tls/key"
MODULE="luasocket"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

# the marker the kernel script prints for a case, and the KTAP description of it
MARKERS=(
	"an unkeyed socket refuses SOL_TLS"
	"TX and RX installed"
	"a direction installs once"
	"TLS 1.2 installed"
	"the zero-salt cipher installed"
	"a short blob refused"
	"an unimplemented version refused"
	"the directions must agree"
	"ARIA is refused outside TLS 1.2"
)
CASES=(
	"key: keying a socket whose ULP was never attached raises ENOPROTOOPT"
	"key: a TLS 1.3 AES-GCM-128 session installs on both directions"
	"key: a direction that is already keyed raises EBUSY"
	"key: a TLS 1.2 session installs"
	"key: the zero-salt cipher installs"
	"key: a blob one byte short of the cipher's struct raises EINVAL"
	"key: a version the kernel does not implement raises EINVAL"
	"key: the two directions must carry the same version and cipher"
	"key: ARIA-GCM under TLS 1.3 raises EINVAL before any AEAD is allocated"
)

# a case the kernel can decline for a reason of its own: the marker the script
# prints in place of the case's own, and what makes that a skip
SKIPMARKERS=(
	[4]="the zero-salt cipher is unavailable (ENOENT)"
	[8]="ARIA is absent from this kernel's uapi"
)
SKIPREASONS=(
	[4]="the kernel builds no rfc7539(chacha20,poly1305)"
	[8]="uapi/linux/tls.h carries no ARIA cipher before 6.1"
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
	if [ -n "${SKIPMARKERS[$i]}" ] && dmesg_since | grep -q "tls key: ${SKIPMARKERS[$i]}"; then
		ktap_skip "${CASES[$i]}: ${SKIPREASONS[$i]}"
		continue
	fi
	dmesg_since | grep -q "tls key: ${MARKERS[$i]}" || fail "${CASES[$i]}"
	ktap_pass "${CASES[$i]}"
done

ktap_totals

