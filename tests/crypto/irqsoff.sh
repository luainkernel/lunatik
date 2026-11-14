#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# crypto.shash and crypto.skcipher methods raise "not allowed with IRQs disabled" in a softirq runtime's
# callback reached with IRQs already off. hid's raw_event runs there for a device behind an HCD whose
# hc_driver carries no HCD_BH, OHCI's, which completes a URB in its interrupt handler: hid_irq_in calls
# hid_input_report and the driver's raw_event, and luahid takes the runtime's lock with spin_lock_irqsave.
# No test host carries such a controller, and uhid hands a report on from a write, with IRQs on, so
# irqsoff.c, built against the running kernel's build tree as deferred.sh builds deferred.c and loaded for
# the case, is a HID transport whose one device, added as the module loads, gets one input report from a
# hard irq_work, which runs in hardirq context.
#
# irqsoff.lua, a softirq runtime, creates a sha256 and a ctr(aes) in its body, keys the cipher there, and
# registers a driver only that device matches, whose raw_event calls digest, setkey and encrypt, answers
# -EPROTO where each of them raised the refusal and raises otherwise. The case passes where
# hid_input_report returned -EPROTO for the report, which no other driver answers and a raw_event that
# raised or did not run does not, and the module and the script are gone before it reads it; a second
# case reads no Lua error, warning or oops in dmesg. Without the refusal, ctr-aes-ce on arm64 sets the key
# in NEON, where kernel_neon_begin is a BUG with IRQs off, so the test skips unless the loaded luacrypto is
# the installed one and that file carries the refusal. It also skips where the kernel has no HID bus or no
# build tree, or serves no sha256 or ctr(aes).
#
# Usage: sudo bash tests/crypto/irqsoff.sh

SCRIPT=tests/crypto/irqsoff
MODULE=irqsoff
CRYPTO=luacrypto
EPROTO=-71 # what irqsoff.lua's raw_event answers once each method refused
REFUSAL="not allowed with IRQs disabled"
BUILD="/lib/modules/$(uname -r)/build"
DIR="$(dirname "$(readlink -f "$0")")"
TMP=""

source "$DIR/../lib.sh"

cleanup() {
	grep -q "^$MODULE " /proc/modules && rmmod "$MODULE"
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	[ -z "$TMP" ] || rm -rf "$TMP"
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 2

[ -d /sys/bus/hid ] || skip_script "crypto/irqsoff: the kernel has no HID bus"
[ -f "$BUILD/Makefile" ] || skip_script "crypto/irqsoff: no build tree at $BUILD"
carries $CRYPTO "$REFUSAL" ||
	skip_script "crypto/irqsoff: the loaded $CRYPTO does not carry the refusal: ctr-aes-ce would key in NEON with IRQs off"

TMP=$(mktemp -d)
cp "$DIR/$MODULE.c" "$TMP/"
echo "obj-m := $MODULE.o" > "$TMP/Kbuild"
make -C "$BUILD" M="$TMP" modules > "$TMP/build.log" 2>&1 ||
	{ comment "$(tail -5 "$TMP/build.log")"; fail "crypto/irqsoff: $MODULE.c did not build"; }

if ! output=$(run_test --context=softirq "$SCRIPT"); then
	unserved=$(grep -o -m 1 'the kernel serves no [^[:space:]]*' <<< "$output") &&
		skip_script "crypto/irqsoff: $unserved"
	echo "$output"
	fail "crypto/irqsoff: the script did not load"
fi
insmod "$TMP/$MODULE.ko" || fail "crypto/irqsoff: $MODULE.ko did not load"

status=$(cat "/sys/module/$MODULE/parameters/status")
rmmod "$MODULE"
lunatik stop "$SCRIPT"

[ "$status" = "$EPROTO" ] || fail "crypto/irqsoff: hid_input_report returned $status for the report, not $EPROTO"
ktap_pass "crypto/irqsoff: shash and skcipher methods refuse a softirq runtime's raw_event reached with IRQs off"

check_dmesg && ktap_pass "crypto/irqsoff: no Lua errors, kernel warnings or oopses"
ktap_totals

