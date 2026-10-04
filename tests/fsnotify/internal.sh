#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A verdict from the kernel's own errno block allows the access and is logged.
#
# include/linux/errno.h keeps ERESTARTSYS and the codes after it from user
# programs, and some mean something to the code that reads them: io_uring
# takes -EIOCBQUEUED from rw_verify_area as a request queued, and posts no
# completion for it. internal.lua answers every OPEN_PERM with -EIOCBQUEUED, so
# the open goes on, as anything that is not a verdict does, and the log names
# the invalid errno; a build that passes it on fails the open with errno 529.
#
# Usage: sudo bash tests/fsnotify/internal.sh

SCRIPT="tests/fsnotify/internal"
INVALID="luafsnotify: invalid errno"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"
source "$(dirname "$(readlink -f "$0")")/perm.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	lunatik stop "$PROBE" 2>/dev/null
	umount "$MOUNT" 2>/dev/null
	rm -rf "$SCRATCH"
}
trap cleanup EXIT
cleanup

perm_begin 3 "fsnotify/internal"

echo content > "$MOUNT/gated"

mark_dmesg
run_script "$SCRIPT"
read=$(cat "$MOUNT/gated" 2>&1)
lunatik stop "$SCRIPT" 2>/dev/null

[ "$read" = content ] || fail "the open a callback answered with an internal errno failed: $read"
ktap_pass "a verdict from the kernel's own errno block allows the access"

dmesg_since | grep -qF "$INVALID" || fail "the internal errno was not logged"
ktap_pass "the internal errno is logged"

check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"

ktap_totals

