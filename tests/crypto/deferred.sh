#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# crypto.comp() waits for an asynchronous acomp implementation, a hardware engine's, through
# crypto_wait_req on a request flagged CRYPTO_TFM_REQ_MAY_BACKLOG. No software acomp answers
# asynchronously and no test host carries an engine, so deferred.c registers one for the test,
# lunatik-deferred, built against the running kernel's build tree as tests/install builds zfs.c and
# loaded for the script. Its compress answers -EINPROGRESS and its decompress -EBUSY, backlogged,
# or -ENOSPC without the flag, as qat_alg_send_message does; 10 ms after the call a worker copies
# the input into the output, sets the length, and completes the request, sending -EINPROGRESS
# first for the backlogged one. Beside it, under the same name at a lower priority,
# a synchronous twin, which 6.15 and later allocate as the asynchronous transform's fallback.
#
# lunatik-deferred names itself through algname; compress returns the input whole and decompress
# does too through the backlog, so a call that read the output's length before the wait, or that
# dropped the flag, fails; an output shorter than the input raises from either the EINVAL the
# completion carries. The module's count of what the worker completed, one per call the script
# made, shows the asynchronous driver served them, and run_test reads no Lua error, warning or
# oops in dmesg. Skips where the running kernel has no build tree, and unloads the module once the
# script that pins it stopped.
#
# Usage: sudo bash tests/crypto/deferred.sh

SCRIPT=tests/crypto/deferred
MODULE=deferred
CALLS=4 # deferred.lua's compress and decompress, each into a whole and a short output
BUILD="/lib/modules/$(uname -r)/build"
DIR="$(dirname "$(readlink -f "$0")")"
TMP=""

source "$DIR/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	grep -q "^$MODULE " /proc/modules && rmmod "$MODULE"
	[ -z "$TMP" ] || rm -rf "$TMP"
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

[ -f "$BUILD/Makefile" ] || { ktap_skip "crypto/deferred: no build tree at $BUILD"; ktap_totals; exit 0; }

TMP=$(mktemp -d)
cp "$DIR/$MODULE.c" "$TMP/"
echo "obj-m := $MODULE.o" > "$TMP/Kbuild"
make -C "$BUILD" M="$TMP" modules > "$TMP/build.log" 2>&1 ||
	{ comment "$(tail -5 "$TMP/build.log")"; fail "crypto/deferred: $MODULE.c did not build"; }
insmod "$TMP/$MODULE.ko" || fail "crypto/deferred: $MODULE.ko did not load"

run_test "$SCRIPT" || fail "crypto/deferred"
lunatik stop "$SCRIPT"
completed=$(cat "/sys/module/$MODULE/parameters/completed")
[ "$completed" = "$CALLS" ] || fail "crypto/deferred: the worker completed $completed requests, not $CALLS"
ktap_pass "crypto/deferred"
ktap_totals

