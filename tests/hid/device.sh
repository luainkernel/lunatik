#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A HID driver's callbacks, driven by devices a peer creates through /dev/uhid.
#
# device.lua registers lunatik_hid_device for the vendor the peer's devices
# carry, from the body of a softirq runtime, and the peer, uhid.c, creates its
# devices once the script is loaded, so the HID core probes each one as it does
# a device plugged in. The probe stamps the device's table, and every callback of
# the device counts itself on that table; remove prints the count, so a table
# made anew for a call, or one shared by two devices, prints another number. On
# each device the peer binds, it sends seven reports whose first byte selects
# what raw_event answers, nothing, zero, a negative errno, a positive number, a
# numeric string, a number below every errno or a raise, and reads which of them
# reached its hidraw node:
#
# - a probe receives the device's table and the matching id_table entry;
# - report_fixup edits the descriptor the device is then parsed with, which
#   sysfs shows;
# - a report raw_event answers with nothing or zero reaches hidraw, and one it
#   answers with a negative errno does not;
# - a report raw_event answers with any other value, or raises on, does not
#   either, and each is logged with the callback;
# - two devices bound at once each get a table of their own, the one their
#   report_fixup, raw_event and remove receive, and remove runs when the
#   device goes;
# - a probe that raises fails the bind with ECANCELED and logs the error, and
#   gets no remove;
# - a device whose probe returned and whose descriptor the HID core then fails
#   to parse gets the remove, with the table report_fixup saw;
# - the report raw_event is handed is closed once the callback returns, also
#   after the last report of the seven, which it raises on: remove reads the
#   view raw_event kept and finds it closed, where a view left on the kernel's
#   buffer still reads its first byte;
# - a raw_event that raises on every report of a burst logs fewer errors than
#   the burst has reports, the log being rate limited;
# - stopping the runtime while it holds a device returns, and the device
#   leaves the driver.
#
# Skips where there is no /dev/uhid (CONFIG_UHID), no hidraw (CONFIG_HIDRAW) or no
# gcc to build the peer.
#
# Usage: sudo bash tests/hid/device.sh

SCRIPT="tests/hid/device"
DRIVER="lunatik_hid_device"
VENDOR="F055"
SOUND="0001"
SECOND="0002"
RAISE="0003"   # its probe raises
BREAK="0004"   # its report_fixup breaks the descriptor
STORM=30       # reports raw_event raises on in the burst
INVALID=6      # returns raw_event refuses, three on each of the two devices
FIXED="06 00 ff 09 01 a1 01 09 03 15 00 26 ff 00 75 08 95 02 81 02 c0"
PASSED="report 00 00|report 01 01"
SEEN=10        # probe, report_fixup, seven raw_events and remove
BROKEN=3       # probe, report_fixup and remove
ECANCELED=-125
RAISED="raised"
DIR="$(dirname "$(readlink -f "$0")")"
PEER_BIN="$(mktemp)"
OUT="$(mktemp)"
PEER=""

source "$DIR/../lib.sh"

skip_all() { ktap_header; ktap_plan 1; ktap_skip "$1"; ktap_totals; exit 0; }

# ends the peer, whose exit destroys its devices
peer_stop() {
	[ -n "$PEER" ] && kill "$PEER" 2>/dev/null && wait "$PEER" 2>/dev/null
	PEER=""
}

cleanup() {
	peer_stop
	lunatik stop "$SCRIPT" 2>/dev/null
	rm -f "$PEER_BIN" "$OUT"
}
trap cleanup EXIT
cleanup

[ -c /dev/uhid ] || skip_all "hid/device: no /dev/uhid to create a device with (CONFIG_UHID)"
CONFIG=$({ zcat /proc/config.gz || cat "/boot/config-$(uname -r)"; } 2>/dev/null)
[ -n "$CONFIG" ] && ! grep -qx 'CONFIG_HIDRAW=y' <<< "$CONFIG" &&
	skip_all "hid/device: no hidraw to read the reports from (CONFIG_HIDRAW)"
build_peer "$DIR/uhid.c" "$PEER_BIN" || skip_all "hid/device: no peer to create a device, without gcc or failing to build"

# runs the peer over the products given until it reported, leaving it holding its devices
peer_start() {
	"$PEER_BIN" "$@" > "$OUT" 2>&1 &
	PEER=$!
	for _ in $(seq 1 100); do
		grep -qx ready "$OUT" && return 0
		kill -0 "$PEER" 2>/dev/null || return 1
		sleep 0.1
	done
	return 1
}

# what the peer printed of a device's reports, one per line
reports() { grep "^$1 report" "$OUT" | cut -d' ' -f2- | paste -sd'|'; }
wrote() { paste -sd'|' "$OUT"; }

logged() { dmesg_since | grep -qF "$1"; }
callback() { logged "luahid: $1: $2"; }
# the driver core's line for a failed probe: "probe of <device>" up to v6.8, "<device>: probe with driver" from v6.9
probefailed() { dmesg_since | grep -qE "0003:$VENDOR:$1\.[0-9A-F]+.* failed with error $2"; }

ktap_header
ktap_plan 11

mark_dmesg
run_script --context=softirq "$SCRIPT"

peer_start -r 1 "$SOUND" "$SECOND" "$RAISE" "$BREAK" || fail "the peer did not report: $(cat "$OUT")"

for product in "$SOUND" "$SECOND"; do
	logged "hid/device: probe lunatik_hid_$product f055 42" || fail "device $product was not probed with its table and id"
done
ktap_pass "a probe receives the device's table and the matching id_table entry"

grep -qxF "$SOUND rdesc $FIXED" "$OUT" || fail "the descriptor is not the one report_fixup edited: $(grep rdesc "$OUT")"
ktap_pass "report_fixup edits the descriptor the device is parsed with"

for product in "$SOUND" "$SECOND"; do
	[ "$(reports "$product")" = "$PASSED" ] || fail "device $product reached hidraw with: $(reports "$product"), the peer wrote: $(wrote)"
done
ktap_pass "a report raw_event answers with nothing or zero passes, and one it answers with a negative errno is dropped"

invalid=$(dmesg_since | grep -c "luahid: invalid errno: raw_event")
[ "$invalid" -eq "$INVALID" ] && callback "$RAISED" raw_event ||
	fail "raw_event logged $invalid of its $INVALID invalid returns, or not its raise"
ktap_pass "a report raw_event answers with any other value, or raises on, is dropped and the error logged"

peer_stop
for product in "$SOUND" "$SECOND"; do
	logged "hid/device: remove lunatik_hid_$product $SEEN" || fail "device $product's remove did not see the table its callbacks shared"
done
ktap_pass "two devices bound at once each get one table, which every callback and remove receive"

for product in "$SOUND" "$SECOND"; do
	logged "hid/device: view lunatik_hid_$product closed" || fail "device $product's report stayed readable after raw_event raised on it"
done
ktap_pass "the report raw_event is handed is closed once the callback returns, also when it raises"

grep -qx "$RAISE unbound" "$OUT" && callback "$RAISED" probe &&
	probefailed "$RAISE" "$ECANCELED" || fail "a probe that raised did not fail with ECANCELED and log"
logged "hid/device: remove lunatik_hid_$RAISE" && fail "a probe that raised got a remove"
ktap_pass "a probe that raises fails the bind with ECANCELED, logs the error and gets no remove"

grep -qx "$BREAK unbound" "$OUT" && logged "hid/device: remove lunatik_hid_$BREAK $BROKEN" ||
	fail "a probe the HID core failed after it returned did not get its remove"
ktap_pass "a device whose probe returned and whose descriptor fails to parse gets the remove"

raised=$(dmesg_since | grep -c "luahid: $RAISED: raw_event")
peer_start -r "$STORM" "$SOUND" || fail "the peer did not report: $(cat "$OUT")"
[ "$(reports "$SOUND")" = "$PASSED" ] || fail "the burst reached hidraw with: $(reports "$SOUND"), the peer wrote: $(wrote)"
peer_stop
raised=$(($(dmesg_since | grep -c "luahid: $RAISED: raw_event") - raised))
[ "$raised" -lt "$STORM" ] || fail "raw_event logged $raised errors for $STORM raises"
ktap_pass "a raw_event that raises on every report of a burst logs fewer errors than the burst has"

peer_start -r 1 "$SOUND" || fail "the peer did not report: $(cat "$OUT")"
lunatik stop "$SCRIPT" || fail "the runtime did not stop while it held a device"
driver=$(readlink /sys/bus/hid/devices/0003:$VENDOR:$SOUND.*/driver)
[ "${driver##*/}" != "$DRIVER" ] || fail "the device stayed with $DRIVER after its runtime stopped"
peer_stop
ktap_pass "a runtime stopped while it holds a device stops, and the device leaves the driver"

check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"

ktap_totals

