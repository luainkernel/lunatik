#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# ZFS beside Lunatik in the module tree: OpenZFS exports its own Lua, from zfs.ko and, before
# OpenZFS 2.2, from zlua.ko, under names lunatik.ko exports too, and the edit make install makes
# to modules.order leaves depmod giving those names to lunatik.ko. A stand-in for zfs.ko, built
# from zfs.c, sits at each path the edit orders, one at a time and under the name of the module
# there, in a tree of its own beside the installed Lunatik modules and the host's modules.order
# as the install left it, and after depmod -b reads that tree no module under kernel/lunatik/
# depends on it:
# - kernel/zfs/, where Ubuntu's kernels carry ZFS before 26.04, zfs.ko and zlua.ko;
# - updates/dkms/, where DKMS puts it on Debian and Ubuntu, zfs.ko and zlua.ko;
# - ubuntu/dkms/zfs/, where 26.04's kernels carry it, zfs.ko.
# The stand-in exports a name from ZFS's own Lua rather than one read from lunatik.ko, so it
# stands for ZFS whatever names lunatik.ko exports. Nothing is loaded, and the host's module tree
# is only read. Skipped where the running kernel has no build tree to build the stand-in against.
#
# Usage: sudo bash tests/install/run.sh

DIR="$(dirname "$(readlink -f "$0")")"
ZFS="kernel/zfs/zfs.ko kernel/zfs/zlua.ko updates/dkms/zfs.ko updates/dkms/zlua.ko ubuntu/dkms/zfs/zfs.ko"
RELEASE=$(uname -r)
INSTALLED="/lib/modules/$RELEASE"
TMP=""

source "$DIR/../lib.sh"

cleanup() {
	[ -z "$TMP" ] || rm -rf "$TMP"
}
trap cleanup EXIT
cleanup

skip() { ktap_header; ktap_plan 1; ktap_skip "$1"; ktap_totals; exit 0; }

[ -f "$INSTALLED/build/Makefile" ] || skip "install: no build tree at $INSTALLED/build"

ktap_header
ktap_plan $(wc -w <<< "$ZFS")

TMP=$(mktemp -d)
STUB="$TMP/stub"
TREE="$TMP/tree"
MODULES="$TREE/lib/modules/$RELEASE"

mkdir "$STUB"
cp "$DIR/zfs.c" "$STUB/"
echo 'obj-m := zfs.o' > "$STUB/Kbuild"
make -C "$INSTALLED/build" M="$STUB" modules > "$TMP/build.log" 2>&1 ||
	{ comment "$(tail -5 "$TMP/build.log")"; fail "install: the stand-in for zfs.ko did not build"; }

mkdir -p "$MODULES/kernel/lunatik"
cp "$INSTALLED"/kernel/lunatik/*.ko "$MODULES/kernel/lunatik/" ||
	fail "install: no Lunatik module installed in $INSTALLED/kernel/lunatik"
cp "$INSTALLED/modules.order" "$MODULES/" || fail "install: no modules.order in $INSTALLED"

for path in $ZFS; do
	mkdir -p "$MODULES/${path%/*}"
	cp "$STUB/zfs.ko" "$MODULES/$path"
	err=$(depmod -b "$TREE" "$RELEASE" 2>&1)
	status=$?
	rm "$MODULES/$path"
	if [ "$status" -ne 0 ] || ! grep -q "^$path:" "$MODULES/modules.dep"; then
		comment "$err"
		ktap_fail "install: depmod exited $status and read no module at $path"
		continue
	fi
	dependents=$(awk -v stub="$path" '$1 ~ /^kernel\/lunatik\// {
		for (i = 2; i <= NF; i++) if ($i == stub) print substr($1, 1, length($1) - 1)
	}' "$MODULES/modules.dep")
	if [ -n "$dependents" ]; then
		ktap_fail "install: with ZFS at $path, $(wc -l <<< "$dependents") Lunatik modules depend on it"
		comment "$dependents"
		continue
	fi
	ktap_pass "install: with ZFS at $path, no Lunatik module depends on it"
done

ktap_totals

