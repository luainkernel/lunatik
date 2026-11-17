#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# OpenZFS's zfs.ko exports its own Lua under the names of Lua's C API, and the kernel refuses a
# module that exports a name a loaded module exports already. A stand-in for zfs.ko, built from
# zfs.c, exports lua_createtable as ZFS's Lua does, and loads beside lunatik.ko, which exports that
# function under Lunatik's prefix. Skipped where the running kernel has no build tree to build the
# stand-in against, and where a module named zfs is loaded already.
#
# Usage: sudo bash tests/install/zfs.sh

DIR="$(dirname "$(readlink -f "$0")")"
BUILD="/lib/modules/$(uname -r)/build"
TMP=""
LOADED=""

source "$DIR/../lib.sh"

cleanup() {
	[ -z "$LOADED" ] || rmmod zfs
	[ -z "$TMP" ] || rm -rf "$TMP"
}
trap cleanup EXIT
cleanup

[ -f "$BUILD/Makefile" ] || skip_script "install: no build tree at $BUILD"
[ ! -d /sys/module/zfs ] || skip_script "install: a module named zfs is loaded"

ktap_header
ktap_plan 1

TMP=$(mktemp -d)
cp "$DIR/zfs.c" "$TMP/"
echo 'obj-m := zfs.o' > "$TMP/Kbuild"
make -C "$BUILD" M="$TMP" modules > "$TMP/build.log" 2>&1 ||
	{ comment "$(tail -5 "$TMP/build.log")"; fail "install: the stand-in for zfs.ko did not build"; }

[ -d /sys/module/lunatik ] || fail "install: lunatik.ko is not loaded"
mark_dmesg
err=$(insmod "$TMP/zfs.ko" 2>&1) ||
	fail "install: the stand-in for zfs.ko did not load beside lunatik.ko: $err $(dmesg_since | tail -1)"
LOADED=1
ktap_pass "install: a module that exports lua_createtable, as zfs.ko does, loads beside lunatik.ko"

ktap_totals

