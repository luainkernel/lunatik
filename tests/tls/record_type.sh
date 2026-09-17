#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the TLS control records socket:sendrecord() emits and
# socket:receiverecord() reports, over a loopback pair keyed on both directions
# with the same fixed vectors. An alert sent with the record type set arrives as
# an alert, which says the TX cmsg reached tls_process_cmsg: without it
# tls_sw_sendmsg would leave the record at application data. tls.close_notify()
# emits the two bytes the kernel's own tls_alert_send does, at warning level.
#
# Then the gap this closes, and its bound: the same close_notify read with plain
# socket:receive() raises EIO, because tls_record_content_type fails a record
# that is not application data when the caller supplied no control buffer; and
# application data read the same way still returns, so the EIO is about control
# records and not about keyed sockets.
#
# Each case keys its own pair over a listener bound to port 0 and closes both
# ends before the next, so the test takes no fixed port from the host and a
# failing case leaves nothing behind. Skipped whole where the tls ULP is neither
# registered nor loadable.
#
# Usage: sudo bash tests/tls/record_type.sh

SCRIPT="tests/tls/record_type"
MODULE="luasocket"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

MARKERS=(
	"a sent alert arrives as an alert"
	"close_notify is a warning-level alert"
	"a plain receive of a control record raises EIO"
	"a plain receive of application data returns it"
)
CASES=(
	"record_type: a record sent with the alert type arrives as an alert"
	"record_type: tls.close_notify emits a warning-level close_notify"
	"record_type: a plain receive of a control record raises EIO"
	"record_type: a plain receive of application data returns it"
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
	dmesg_since | grep -q "tls record: ${MARKERS[$i]}" || fail "${CASES[$i]}"
	ktap_pass "${CASES[$i]}"
done

ktap_totals

