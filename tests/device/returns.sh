#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A callback that raises, or whose return the binding cannot use, fails its
# operation, and the runtime answers the next one.
#
# returns.lua creates lunatik_offset, whose read and write return an offset
# that is not an integer, lunatik_length, whose write returns a length that is
# not an integer, lunatik_raised, whose read, write and release raise, and
# lunatik_sound, whose read and write return integers:
#
# - a read or a write whose callback returns an offset that is not an integer,
#   and a write whose callback returns such a length, each fail with ECANCELED
#   and log the error naming the value and the operation;
# - a read or a write whose callback raises fails with ECANCELED, and the
#   error of each, and of the release that follows, is logged with the
#   operation;
# - a read or a write of the sound device through a buffer at an unmapped
#   address fails with EFAULT, where python3 is there to pass one;
# - after them, a read and a write of the same runtime's sound device, whose
#   callbacks return an offset and a length, succeed, so the runtime's lock
#   was given back.
#
# A build that reads those returns outside a protected call raises with no
# handler, which is a BUG, so the test skips unless the loaded luadevice lists
# luadevice_pcall in /proc/kallsyms.
#
# Usage: sudo bash tests/device/returns.sh

SCRIPT="tests/device/returns"
OFFSET="lunatik_offset"
LENGTH="lunatik_length"
RAISED="lunatik_raised"
SOUND="lunatik_sound"
CONTENT="returns"
ECANCELED="Operation canceled"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

export LC_ALL=C

skip_all() { ktap_header; ktap_plan 1; ktap_skip "$1"; ktap_totals; exit 0; }

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
}
trap cleanup EXIT
cleanup

grep -Eq " luadevice_pcall[[:space:]]\[luadevice\]$" /proc/kallsyms 2>/dev/null ||
	skip_all "no luadevice_pcall in the loaded luadevice: a callback's return would raise with no handler"

# fails unless the command fails with the error named
refuses() {
	local error="$1" output
	shift
	output=$("$@" 2>&1) && return 1
	[[ "$output" == *"$error"* ]]
}

writeto() { printf x > "/dev/$1"; }

# prints the errno names of a read and of a write through an unmapped buffer
faults() {
	python3 - "/dev/$1" <<'PY'
import ctypes, errno, os, sys
libc = ctypes.CDLL(None, use_errno=True)
fd = os.open(sys.argv[1], os.O_RDWR)
unmapped = ctypes.c_void_p(1)
names = []
for op in (libc.read, libc.write):
    ret = op(fd, unmapped, 1)
    names.append(errno.errorcode[ctypes.get_errno()] if ret < 0 else str(ret))
os.close(fd)
print(" ".join(names))
PY
}

# fails unless the kernel log since the mark holds the error and the operation
logged() { dmesg_since | grep -q "luadevice: $1: $2$"; }

ktap_header
ktap_plan 7

mark_dmesg
run_script "$SCRIPT"
for dev in "$OFFSET" "$LENGTH" "$RAISED" "$SOUND"; do
	[ -c "/dev/$dev" ] || fail "the script's device $dev did not appear"
done

refuses "$ECANCELED" cat "/dev/$OFFSET" || fail "a read returning an offset that is not an integer did not fail with ECANCELED"
logged "offset is not an integer" read || fail "the read's error is not in the kernel log"
ktap_pass "a read whose callback returns an offset that is not an integer fails with ECANCELED and logs it"

refuses "$ECANCELED" writeto "$OFFSET" || fail "a write returning an offset that is not an integer did not fail with ECANCELED"
logged "offset is not an integer" write || fail "the write's error is not in the kernel log"
ktap_pass "a write whose callback returns an offset that is not an integer fails with ECANCELED and logs it"

refuses "$ECANCELED" writeto "$LENGTH" || fail "a write returning a length that is not an integer did not fail with ECANCELED"
logged "length is not an integer" write || fail "the write's error is not in the kernel log"
ktap_pass "a write whose callback returns a length that is not an integer fails with ECANCELED and logs it"

refuses "$ECANCELED" cat "/dev/$RAISED" || fail "a read whose callback raises did not fail with ECANCELED"
refuses "$ECANCELED" writeto "$RAISED" || fail "a write whose callback raises did not fail with ECANCELED"
logged raised read && logged raised write && logged raised release || fail "a raising callback's error is not in the kernel log"
ktap_pass "a read or a write whose callback raises fails with ECANCELED, and each error, the release's too, is logged"

if command -v python3 > /dev/null 2>&1; then
	[ "$(faults "$SOUND")" = "EFAULT EFAULT" ] || fail "a read or a write through an unmapped buffer did not fail with EFAULT"
	ktap_pass "a read or a write through an unmapped buffer fails with EFAULT"
else
	ktap_skip "no python3 to pass an unmapped buffer"
fi

[ "$(cat "/dev/$SOUND")" = "$CONTENT" ] && writeto "$SOUND" ||
	fail "the runtime did not answer a sound read and write after the failed ones"
ktap_pass "the runtime answers a read and a write whose callbacks return integers after the failed ones"

lunatik stop "$SCRIPT" > /dev/null
check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"

ktap_totals

