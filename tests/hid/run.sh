#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs hid regression tests and reports aggregated KTAP results.
#
# register: hid.register() sizes the driver's id_table from the Lua table it is
# given, through luaL_len(), which a __len metamethod answers with any number the
# script likes, and reads every entry through lua_geti() and lua_getfield(), which
# an __index metamethod answers however it likes. It registers the id_tables the
# binding serves, one entry and LUAHID_MAXIDS of them, under a vendor no device on
# the bus carries, and refuses a longer table, a fabricated length, a length that
# is not an integer, an entry that is not a table and an entry that raises while it
# is read. It also refuses a name that fills NAME_MAX with no room for its
# terminator, and accepts the longest one that does leave room. The accepted ones
# are read back from /sys/bus/hid/drivers, since a driver that raised nothing has
# still not necessarily reached the bus, and read again after the runtime stops,
# since they leave the bus with it.
#
# The refusals carry the weight: hid.register() hands the id_table to the driver
# before the walk that can raise, so the object's release owns it from then on, and
# a fix that also freed the table by hand would free it twice. The finalizer the
# script forces after each refusal is where that lands.
#
# hid.register needs a softirq runtime: its class is LUNATIK_OPT_SOFTIRQ and
# lunatik_setruntime() refuses any other context.
#
# Usage: sudo bash tests/hid/run.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

SCRIPT=tests/hid/register
DRIVERS=/sys/bus/hid/drivers
LONGNAME=$(printf 'x%.0s' $(seq 1 254)) # NAME_MAX - 1, the longest name hid.register serves
NAMES="lunatik_hid_one lunatik_hid_max lunatik_hid_after $LONGNAME"
TOTAL=$(echo $NAMES | wc -w)

skip() { ktap_header; ktap_plan 1; ktap_skip "$1"; ktap_totals; exit 0; }

cleanup() { lunatik stop "$SCRIPT" > /dev/null 2>&1; }
trap cleanup EXIT
cleanup

[ -d /sys/bus/hid ] || skip "hid: the kernel has no HID bus"

ktap_header
ktap_plan 3

onbus() {
	local name count=0
	for name in $NAMES; do
		[ -d "$DRIVERS/$name" ] && count=$((count + 1))
	done
	echo $count
}

if run_test "$SCRIPT" softirq; then
	ktap_pass "hid/register"
else
	ktap_fail "hid/register"
fi

count=$(onbus)
if [ "$count" -eq "$TOTAL" ]; then
	ktap_pass "hid/register: the accepted drivers are on the hid bus"
else
	ktap_fail "hid/register: $count of $TOTAL drivers under $DRIVERS"
fi

lunatik stop "$SCRIPT" > /dev/null 2>&1
count=$(onbus)
if [ "$count" -eq 0 ]; then
	ktap_pass "hid/register: the drivers leave the hid bus with the runtime"
else
	ktap_fail "hid/register: $count drivers outlived their runtime under $DRIVERS"
fi

ktap_totals
RESULT=0
[ $KTAP_FAIL -eq 0 ] || RESULT=1

echo ""
bash "$DIR/idtable_leak.sh" || RESULT=1
exit $RESULT

