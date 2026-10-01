#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A data view of an skb copy is valid while the copy lives, and is cleared when the copy goes.
#
# copy_view.lua takes one step per echo request marked MARK in a LOCAL_OUT netfilter
# hook, with a full collection after what a step drops, and kprobes on luaskb_release and
# luadata_release, read from kprobe_profile, count the skb objects and the data objects
# freed; the hook passes the echo reply, which carries the ping's mark where
# net.ipv4.fwmark_reflect is set:
#
# - plain: a copy dropped with no view goes at the collection, which is also what
#   shows that the kprobe counts a copy's release;
# - held: a copy kept while its view is dropped stays, and a view taken again reads
#   the bytes the first one read;
# - again: after the copy is trimmed, a second data() call returns the object the first
#   one did, which ends at the new tail;
# - dropped: the copy, dropped while its view is kept, goes at the collection, its view
#   then has length 0 and raises "out of bounds", and goes once it is dropped too;
# - stop: a copy kept with its view goes when the runtime stops, with its view and the
#   hook's own skb and views.
#
# A build whose view keeps the copy alive fails the dropped step, and one whose copy
# leaves its view set fails there on the view's length, which the hook reads before any
# byte, so no view of a freed copy is read; one whose skb keeps a dropped view registered
# fails there on the data count.
#
# Usage: sudo bash tests/skb/copy_view.sh

SCRIPT="tests/skb/copy_view"
MARK=1275 # MARK in copy_view.lua
LOCAL="127.0.0.1"
RELEASES="lunatik_skb/luaskb_release"
FREED="lunatik_skb/luadata_release"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

skip_all() { ktap_header; ktap_plan 1; ktap_skip "$1"; ktap_totals; exit 0; }

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	kprobe_remove "$RELEASES"
	kprobe_remove "$FREED"
}
trap cleanup EXIT
cleanup

kprobe_place "$RELEASES" luaskb_release || skip_all "couldn't place a kprobe on luaskb_release"
kprobe_place "$FREED" luadata_release || skip_all "couldn't place a kprobe on luadata_release"

releases() { kprobe_hits "$RELEASES"; }
freed() { kprobe_hits "$FREED"; }

# sends the ping the hook takes <cell> on, and fails unless the hook reports it ok
step() {
	local cell="$1" failed
	ping -c 1 -W 1 -m "$MARK" "$LOCAL" > /dev/null 2>&1
	failed=$(dmesg_since | grep -o "skb copy view: $cell FAIL.*" | head -1)
	[ -z "$failed" ] || fail "$failed"
	dmesg_since | grep -q "skb copy view: $cell ok" || fail "the hook never reached $cell"
}

ktap_header
ktap_plan 6

mark_dmesg
run_script --context=softirq "$SCRIPT"
base=$(releases)
views=$(freed)

step plain
[ "$(releases)" -eq $((base + 1)) ] || fail "a copy dropped with no view was not released at the collection"
ktap_pass "a copy dropped with no view goes at the next collection"

step held
[ "$(releases)" -eq $((base + 1)) ] || fail "a copy was released while it was kept and its view was dropped"
ktap_pass "a copy kept while its view is dropped stays, and a view taken again reads its bytes"

step again
[ "$(releases)" -eq $((base + 1)) ] || fail "a copy was released while it was kept"
ktap_pass "a second data() call on a copy returns the view the first one did, at the copy's new tail"

step dropped
[ "$(releases)" -eq $((base + 2)) ] || fail "a copy dropped while its view was kept was not released at the collection"
[ "$(freed)" -eq $((views + 1)) ] || fail "the view of a dropped copy was not freed once it was dropped too"
ktap_pass "a copy dropped while its view is kept goes, its view raises \"out of bounds\" and goes once dropped"

step stop
[ "$(releases)" -eq $((base + 2)) ] || fail "a copy was released while it was kept"
lunatik stop "$SCRIPT" 2>/dev/null
[ "$(releases)" -eq $((base + 4)) ] || fail "the stop released $(( $(releases) - base - 2 )) skb objects, not the kept copy and the hook's own"
[ "$(freed)" -eq $((views + 4)) ] || fail "the stop freed $(( $(freed) - views - 1 )) data objects, not the kept copy's view and the hook's two"
ktap_pass "a copy kept with its view goes when the runtime stops, with its view and the hook's own"

check_dmesg && ktap_pass "no Lua errors in kernel"
ktap_totals

