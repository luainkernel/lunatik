#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A file open across its device's stop keeps the device's memory and not its
# node.
#
# held.lua creates lunatik_held, whose write of "stop" stops the device from
# that write and collects its object, lunatik_selfstop, whose open does the
# same, and lunatik_refused, whose open raises. An open file holds the device's
# memory from its open to its close, and a refused open gives it back at once;
# the node goes with the stop or with the runtime, whatever is open. A kprobe on
# luadevice_free, read from kprobe_profile, counts the devices whose memory
# went, and one on lunatik_releaseobject the Lunatik objects freed:
#
# - a live device reads and writes, and an open its callback refuses fails with
#   ECANCELED and holds nothing: that device goes with its runtime;
# - a device stopped and collected while a file holds it leaves /dev and sysfs
#   at once; the file reads and writes ENXIO, reopening it through /proc finds
#   no device, and the memory goes at its close and not before;
# - a device stopped and collected from its own open, between the share the
#   open took and its callback, leaves that open a file that reads ENXIO and
#   holds the memory until its close;
# - a runtime stopped while a file holds its device removes the node, and the
#   file reads, writes and reopens ENXIO; the script starts again under the
#   same name with that file still open, the file reads ENXIO rather than reach
#   the new device, a reopen of it through /proc is refused with ENXIO when the
#   new device took its number, and the memory goes at its close, the stopped
#   runtime's object with it, once the driver runtime has collected the copy of
#   its handle that lunatik stop left there.
#
# A build without the file's hold reads freed memory in each held case, so the
# test skips unless the loaded luadevice lists luadevice_free in /proc/kallsyms.
#
# Usage: sudo bash tests/device/held.sh

SCRIPT="tests/device/held"
HELD="lunatik_held"
SELFSTOP="lunatik_selfstop"
REFUSED="lunatik_refused"
TRACING="/sys/kernel/tracing"
INSTANCE="$TRACING/instances/lunatik_device"
PROBE="lunatik_device/luadevice_free"
OBJECTS="lunatik_device/lunatik_releaseobject"
ENXIO="No such device or address"
ECANCELED="Operation canceled"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

export LC_ALL=C

skip_all() { ktap_header; ktap_plan 1; ktap_skip "$1"; ktap_totals; exit 0; }

cleanup() {
	exec 3<&- 4<&- 5<&-
	lunatik stop "$SCRIPT" 2>/dev/null
	if [ -d "$INSTANCE" ]; then
		for probe in "$PROBE" "$OBJECTS"; do
			echo 0 > "$INSTANCE/events/$probe/enable" 2>/dev/null
		done
		rmdir "$INSTANCE"
	fi
	for probe in "$PROBE" "$OBJECTS"; do
		grep -q ":$probe " "$TRACING/kprobe_events" 2>/dev/null && echo "-:$probe" >> "$TRACING/kprobe_events"
	done
}
trap cleanup EXIT
cleanup

grep -Eq " luadevice_free[[:space:]]\[luadevice\]$" /proc/kallsyms 2>/dev/null ||
	skip_all "no luadevice_free in the loaded luadevice: a held file would read freed memory"
echo "p:$PROBE luadevice_free" >> "$TRACING/kprobe_events" 2>/dev/null || skip_all "no kprobe events in tracefs"
echo "p:$OBJECTS lunatik_releaseobject" >> "$TRACING/kprobe_events" 2>/dev/null ||
	skip_all "couldn't place a kprobe on lunatik_releaseobject"
mkdir "$INSTANCE" && echo 1 > "$INSTANCE/events/$PROBE/enable" || skip_all "couldn't enable the kprobe on luadevice_free"
echo 1 > "$INSTANCE/events/$OBJECTS/enable" || skip_all "couldn't enable the kprobe on lunatik_releaseobject"

hits() { awk -v event="${1#*/}" '$1 == event { print $2 }' "$TRACING/kprobe_profile"; }
frees() { hits "$PROBE"; }

# fails unless the command fails with the error named
refuses() {
	local error="$1" output
	shift
	output=$("$@" 2>&1) && return 1
	[[ "$output" == *"$error"* ]]
}

writeheld() { printf x >&"$1"; }

ktap_header
ktap_plan 12

mark_dmesg
run_script "$SCRIPT"
[ -c "/dev/$HELD" ] && [ -c "/dev/$SELFSTOP" ] && [ -c "/dev/$REFUSED" ] || fail "the script's devices did not appear"
base=$(frees)

[ "$(cat "/dev/$HELD")" = "held" ] && printf x > "/dev/$HELD" || fail "a live device failed to read or write"
ktap_pass "a live device reads and writes"

refuses "$ECANCELED" cat "/dev/$REFUSED" || fail "an open its callback refuses did not fail with ECANCELED"
ktap_pass "an open its callback refuses fails with ECANCELED"

exec 3<> "/dev/$HELD"
printf stop >&3 || fail "the stop written through the held file failed"
[ ! -e "/dev/$HELD" ] && [ ! -e "/sys/class/luadevice/$HELD" ] || fail "a device stopped while a file holds it is still in /dev or sysfs"
ktap_pass "a device stopped while a file holds it leaves /dev and sysfs"

refuses "$ENXIO" cat <&3 || fail "a file held across its device's stop did not read ENXIO"
refuses "$ENXIO" writeheld 3 || fail "a file held across its device's stop did not write ENXIO"
refuses "$ENXIO" cat /proc/self/fd/3 || fail "a reopen of a file held across its device's stop was not refused with ENXIO"
ktap_pass "a file held across its device's stop reads, writes and reopens ENXIO"

[ "$(frees)" -eq "$base" ] || fail "a device's memory went while a file held it"
exec 3<&-
[ "$(frees)" -eq $((base + 1)) ] || fail "a device's memory did not go at the close of the file that held it"
ktap_pass "a device's memory goes at the close of the file held across its stop, and not before"

exec 5<> "/dev/$SELFSTOP" || fail "an open whose callback stops the device did not succeed"
[ ! -e "/dev/$SELFSTOP" ] || fail "a device stopped from its own open is still in /dev"
refuses "$ENXIO" cat <&5 || fail "the file whose open stopped the device did not read ENXIO"
[ "$(frees)" -eq $((base + 1)) ] || fail "a device stopped from its own open went while that file held it"
exec 5<&-
[ "$(frees)" -eq $((base + 2)) ] || fail "a device stopped from its own open did not go at the close of that file"
ktap_pass "a device stopped from its own open is held by the share that open took, until that file closes"

lunatik stop "$SCRIPT" > /dev/null
[ "$(frees)" -eq $((base + 3)) ] || fail "a device whose open was refused did not go with its runtime"
ktap_pass "a refused open holds nothing: its device goes with its runtime"

run_script "$SCRIPT"
base=$(frees)
exec 4<> "/dev/$HELD"
number=$(stat -c %t:%T "/dev/$HELD")
lunatik stop "$SCRIPT" > /dev/null
[ ! -e "/dev/$HELD" ] && [ ! -e "/sys/class/luadevice/$HELD" ] || fail "a runtime stop left the node of a device a file holds"
refuses "$ENXIO" cat <&4 || fail "a file held across its runtime's stop did not read ENXIO"
refuses "$ENXIO" writeheld 4 || fail "a file held across its runtime's stop did not write ENXIO"
refuses "$ENXIO" cat /proc/self/fd/4 || fail "a reopen of a file held across its runtime's stop was not refused with ENXIO"
ktap_pass "a runtime stopped while a file holds its device removes the node, and the file reads, writes and reopens ENXIO"

run_script "$SCRIPT"
[ "$(cat "/dev/$HELD")" = "held" ] || fail "the device started again under its name does not read"
refuses "$ENXIO" cat <&4 || fail "a file held across its runtime's stop reached the device started again"
ktap_pass "the device starts again under its name while the old file is open, and the old file does not reach it"

if [ "$(stat -c %t:%T "/dev/$HELD")" = "$number" ]; then
	refuses "$ENXIO" cat /proc/self/fd/4 || fail "a reopen of a file held across its runtime's stop opened the device that took its number"
	ktap_pass "a reopen of a file held across its runtime's stop does not open the device that took its number"
else
	ktap_skip "the device started again did not take the number of the one the file holds"
fi

printf 'collectgarbage()\n' | lunatik > /dev/null # drops the copy of the handle lunatik stop left in the driver
objects=$(hits "$OBJECTS")
[ "$(frees)" -eq $((base + 2)) ] || fail "a device's memory went while a file held it across its runtime's stop"
exec 4<&-
[ "$(frees)" -eq $((base + 3)) ] || fail "a device's memory did not go at the close of the file held across its runtime's stop"
[ "$(hits "$OBJECTS")" -eq $((objects + 1)) ] || fail "the runtime stopped while a file held its device was not freed at that file's close"
ktap_pass "a device's memory, and its stopped runtime's object, go at the close of the file held across the stop, and not before"

lunatik stop "$SCRIPT" > /dev/null
check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"

ktap_totals

