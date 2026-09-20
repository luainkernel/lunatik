#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Shared setup for the fsnotify permission tests. Source it after lib.sh.
#
# A permission mark decides whether an access happens, so every one of them goes
# on a filesystem the test brings with it: a rule that denies then reaches
# nothing the machine needs, and the unmount in the trap takes the marks with
# it. perm_begin mounts that tmpfs and asks the module whether this kernel has
# the permission hooks, which is the running kernel's own answer rather than
# what a config file says the kernel was built with; when either is missing it
# skips the whole plan and leaves; a raise from the probe that does not name the
# config fails it instead.
#
# Sourced by every permission test, each of which stops PROBE and SCRIPT and
# unmounts MOUNT in its trap.

PROBE="tests/fsnotify/probe"
SCRATCH="/tmp/lunatik-fsnotify"
MOUNT="$SCRATCH/mnt"

# deny and exec assert on strerror text, which the locale sudo hands down would translate
export LC_ALL=C

perm_skip() {
	local i
	for i in $(seq "$1"); do ktap_skip "$2"; done
	ktap_totals
	exit 0
}

# perm_begin <plan> <name>
perm_begin() {
	ktap_header
	ktap_plan "$1"

	mkdir -p -m 0700 "$MOUNT"
	mount -t tmpfs -o size=1M,mode=0700 lunatik-fsnotify "$MOUNT" 2>/dev/null
	mountpoint -q "$MOUNT" || perm_skip "$1" "$2: no tmpfs to mark"

	mark_dmesg
	run_script "$PROBE"
	lunatik stop "$PROBE" 2>/dev/null
	dmesg_since | grep -qF "fsnotify permission probe: supported" || \
		perm_skip "$1" "$2: no CONFIG_FANOTIFY_ACCESS_PERMISSIONS"
}

