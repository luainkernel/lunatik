#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs hid regression tests and reports aggregated KTAP results.
#
# register: hid.register() sizes the driver's id_table from the Lua table it is
# given, through luaL_len(), which a __len metamethod answers with any number the
# script likes. It registers the id_tables the binding serves, one entry and
# LUAHID_MAXIDS of them, under a vendor no device on the bus carries, and refuses
# both a longer table and a fabricated length, whose byte size overflows. The
# accepted ones are read back from /sys/bus/hid/drivers, since a driver that
# raised nothing has still not necessarily reached the bus.
#
# hid.register needs a softirq runtime: its class is LUNATIK_OPT_SOFTIRQ and
# lunatik_setruntime() refuses any other context.
#
# Usage: sudo bash tests/hid/run.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

SCRIPT=tests/hid/register
DRIVERS=/sys/bus/hid/drivers
NAMES="lunatik_hid_one lunatik_hid_max"

skip() { ktap_header; ktap_plan 1; ktap_skip "$1"; ktap_totals; exit 0; }

cleanup() { lunatik stop "$SCRIPT" 2>/dev/null; }
trap cleanup EXIT
cleanup

[ -d /sys/bus/hid ] || skip "hid: the kernel has no HID bus"

ktap_header
ktap_plan 2

if run_test "$SCRIPT" softirq; then
	ktap_pass "hid/register"
else
	ktap_fail "hid/register"
fi

missing=""
for name in $NAMES; do
	[ -d "$DRIVERS/$name" ] || missing="$missing $name"
done
if [ -z "$missing" ]; then
	ktap_pass "hid/register: the accepted drivers are on the hid bus"
else
	ktap_fail "hid/register: missing from $DRIVERS:$missing"
fi

ktap_totals
[ $KTAP_FAIL -eq 0 ]

