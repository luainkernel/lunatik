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
# - that device's remove raises, which is logged, and its table is released all
#   the same: the finalizer probe set on it runs in the full collection a later
#   remove makes, which a table left in the registry would escape;
# - the report raw_event is handed is closed once the callback returns, also
#   after the last report of the seven, which it raises on: remove reads the
#   view raw_event kept and finds it closed, where a view left on the kernel's
#   buffer still reads its first byte;
# - a raw_event that raises on every report of a burst logs fewer errors than
#   the burst has reports, the log being rate limited;
# - stopping the runtime while it holds a device returns, and the device
#   leaves the driver.
#
# The peer then creates three devices before the script loads, hid-generic
# binds them and the test releases the third; the peer sends their reports
# once the script is loaded, since raw_event refuses until the body returns.
# The body registers lunatik_hid_handing for the second one, then
# lunatik_hid_device, and stops lunatik_hid_handing, and the callbacks print
# whether they run while the body loads, which a flag it clears at its end
# tells:
#
# - a device on hid-generic gets probe and report_fixup inside hid.register,
#   and its reports reach the hidraw node made there;
# - a hid.register and a stop from the probe hid.register delivers raise "not
#   allowed inside hid.register or stop", and return;
# - a stop in the body delivers remove to the device the driver holds, and
#   lunatik_hid_device, which matches it too, probes it inside that stop;
# - a device no driver holds gets probe inside hid.register, and its reports
#   reach its hidraw node.
#
# A build that delivers the probe without that refusal waits forever on the
# device lock the probe holds, so those cases skip unless the loaded luahid is
# the installed one and that file carries the refusal, which is inline and has
# no symbol of its own, and where the kernel has no hid-generic.
#
# Skips where there is no /dev/uhid (CONFIG_UHID), no hidraw (CONFIG_HIDRAW) or no
# gcc to build the peer.
#
# Usage: sudo bash tests/hid/device.sh

SCRIPT="tests/hid/device"
DRIVER="lunatik_hid_device"
MODULE="luahid"
VENDOR="F055"
SOUND="0001"
SECOND="0002"
RAISE="0003"   # its probe raises
BREAK="0004"   # its report_fixup breaks the descriptor
PRESENT="0005" # on the bus before the script, its probe calls hid.register and stop
HANDED="0006"  # on the bus before the script, which hands it from one driver to the other
UNBOUND="0007" # on the bus before the script, released from hid-generic so that no driver holds it
HANDED_DATA=7
HANDED_SEEN=3  # probe, report_fixup and remove, by the driver that hands it
GENERIC="hid-generic"
CALL="hid.register or stop" # the call the refusal names, in luahid's own strings
REFUSAL="not allowed inside $CALL"
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

# whether the device of the product given is bound to the driver given
bound() {
	local driver
	driver=$(readlink /sys/bus/hid/devices/0003:$VENDOR:$1.*/driver)
	[ "${driver##*/}" = "$2" ]
}
ready() { grep -qx ready "$OUT"; }
refuses() {
	[ "$(cat /sys/module/$MODULE/srcversion 2> /dev/null)" = "$(modinfo -F srcversion $MODULE 2> /dev/null)" ] &&
		grep -aqF "$CALL" "$(modinfo -n $MODULE 2> /dev/null)"
}

ktap_header
ktap_plan 16

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

# remove's raise brings the first phase to 10 logged errors, DEFAULT_RATELIMIT_BURST: one more goes in a phase of its own
callback "$RAISED" remove && logged "hid/device: released lunatik_hid_$BREAK" ||
	fail "a remove that raised did not log, or left the device's table referenced"
ktap_pass "a remove that raises logs the error, and the device's table is released"

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

PRESENTED=(
	"a device on hid-generic gets probe and report_fixup inside hid.register, and its hidraw node passes its reports"
	"a hid.register and a stop from a callback hid.register delivers are refused, and return"
	"a stop in the body delivers remove, and the runtime's other driver that matches the device probes it inside the stop"
	"a device no driver holds gets probe inside hid.register, and its hidraw node passes its reports"
)
if [ -n "$CONFIG" ] && ! grep -qE '^CONFIG_HID_GENERIC=(y|m)$' <<< "$CONFIG"; then
	for name in "${PRESENTED[@]}"; do ktap_skip "$name: no $GENERIC to hold a device before the script"; done
elif ! refuses; then
	for name in "${PRESENTED[@]}"; do ktap_skip "$name: the loaded $MODULE does not carry the refusal: it would wait on the device lock"; done
else
	"$PEER_BIN" -r 1 -w "$PRESENT" "$HANDED" "$UNBOUND" > "$OUT" 2>&1 &
	PEER=$!
	for product in "$PRESENT" "$HANDED" "$UNBOUND"; do
		awaited bound "$product" "$GENERIC" ||
			fail "the devices the peer created before the script are not on $GENERIC: $(cat "$OUT")"
	done
	basename /sys/bus/hid/devices/0003:$VENDOR:$UNBOUND.* > /sys/bus/hid/drivers/$GENERIC/unbind
	run_script --context=softirq "$SCRIPT"
	kill -USR1 "$PEER" # the body returned, so raw_event passes the reports
	awaited ready || fail "the peer did not report: $(cat "$OUT")"
	peer_stop
	lunatik stop "$SCRIPT"

	logged "hid/device: probe lunatik_hid_$PRESENT f055 42 loading" &&
		grep -qxF "$PRESENT rdesc $FIXED" "$OUT" && [ "$(reports "$PRESENT")" = "$PASSED" ] ||
		fail "a device on $GENERIC was not probed and fixed inside hid.register, or its reports did not pass: $(wrote)"
	ktap_pass "${PRESENTED[0]}"

	logged "hid/device: nested register $REFUSAL" && logged "hid/device: nested stop $REFUSAL" ||
		fail "a hid.register or a stop from a probe hid.register delivered was not refused"
	ktap_pass "${PRESENTED[1]}"

	logged "hid/device: probe lunatik_hid_$HANDED f055 $HANDED_DATA loading" &&
		logged "hid/device: remove lunatik_hid_$HANDED $HANDED_SEEN loading" &&
		logged "hid/device: probe lunatik_hid_$HANDED f055 42 loading" && [ "$(reports "$HANDED")" = "$PASSED" ] ||
		fail "a stop in the body did not deliver remove, or the other driver did not probe the device: $(wrote)"
	ktap_pass "${PRESENTED[2]}"

	logged "hid/device: probe lunatik_hid_$UNBOUND f055 42 loading" && [ "$(reports "$UNBOUND")" = "$PASSED" ] ||
		fail "a device no driver held was not probed inside hid.register, or its reports did not pass: $(wrote)"
	ktap_pass "${PRESENTED[3]}"
fi

check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"

ktap_totals

