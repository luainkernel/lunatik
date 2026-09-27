#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A data view of an skb copy keeps the copy alive.
#
# copy_view.lua takes one step per echo request marked MARK in a LOCAL_OUT netfilter
# hook, each ending in a full collection, and a kprobe on luaskb_release, read
# from kprobe_profile, counts the skb objects freed; the hook passes the echo
# reply, which carries the ping's mark where net.ipv4.fwmark_reflect is set:
#
# - plain: a copy dropped with no view goes at the collection, which is also what
#   shows that the kprobe counts a copy's release;
# - held: a copy kept while its one view is dropped stays;
# - kept: that copy, dropped while two new views of it are kept, stays;
# - first: one view reads the bytes the copy held and is dropped, and the copy
#   stays, held by the other;
# - last: the other view reads them too and is dropped, and the copy goes;
# - stop: a copy dropped while its view is kept stays, and goes when the runtime
#   stops, with the hook's own skb.
#
# A build whose view holds no reference releases the copy in the kept step: the
# test fails there and sends no further ping, so no view of a freed copy is read.
#
# Usage: sudo bash tests/skb/copy_view.sh

SCRIPT="tests/skb/copy_view"
MARK=1275 # MARK in copy_view.lua
LOCAL="127.0.0.1"
TRACING="/sys/kernel/tracing"
INSTANCE="$TRACING/instances/lunatik_skb"
RELEASES="lunatik_skb/luaskb_release"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

skip_all() { ktap_header; ktap_plan 1; ktap_skip "$1"; ktap_totals; exit 0; }

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	if [ -d "$INSTANCE" ]; then
		echo 0 > "$INSTANCE/events/$RELEASES/enable" 2>/dev/null
		rmdir "$INSTANCE"
	fi
	grep -q ":$RELEASES " "$TRACING/kprobe_events" 2>/dev/null && echo "-:$RELEASES" >> "$TRACING/kprobe_events"
}
trap cleanup EXIT
cleanup

echo "p:$RELEASES luaskb_release" >> "$TRACING/kprobe_events" 2>/dev/null ||
	skip_all "couldn't place a kprobe on luaskb_release"
mkdir "$INSTANCE" && echo 1 > "$INSTANCE/events/$RELEASES/enable" || skip_all "couldn't enable the kprobe on luaskb_release"

releases() { awk -v event="${RELEASES#*/}" '$1 == event { print $2 }' "$TRACING/kprobe_profile"; }

# sends the ping the hook takes <cell> on, and fails unless the hook reports it ok
step() {
	local cell="$1" failed
	ping -c 1 -W 1 -m "$MARK" "$LOCAL" > /dev/null 2>&1
	failed=$(dmesg_since | grep -o "skb copy view: $cell FAIL.*" | head -1)
	[ -z "$failed" ] || fail "$failed"
	dmesg_since | grep -q "skb copy view: $cell ok" || fail "the hook never reached $cell"
}

ktap_header
ktap_plan 7

mark_dmesg
run_script --context=softirq "$SCRIPT"
base=$(releases)

step plain
[ "$(releases)" -eq $((base + 1)) ] || fail "a copy dropped with no view was not released at the collection"
ktap_pass "a copy dropped with no view goes at the next collection"

step held
[ "$(releases)" -eq $((base + 1)) ] || fail "a copy was released while it was kept and its view was dropped"
ktap_pass "a copy kept while its view is dropped stays"

step kept
[ "$(releases)" -eq $((base + 1)) ] || fail "a copy was released while two of its views were kept"
ktap_pass "a copy dropped while its views are kept stays"

step first
[ "$(releases)" -eq $((base + 1)) ] || fail "a copy was released while one of its views was kept"
ktap_pass "a view reads the bytes of a dropped copy, and dropped, leaves the copy to the other view"

step last
[ "$(releases)" -eq $((base + 2)) ] || fail "a copy was not released when its last view went"
ktap_pass "the last view of a dropped copy reads its bytes, and dropped, releases it"

step stop
[ "$(releases)" -eq $((base + 2)) ] || fail "a copy was released while its view was kept"
lunatik stop "$SCRIPT" 2>/dev/null
[ "$(releases)" -eq $((base + 4)) ] || fail "the stop released $(( $(releases) - base - 2 )) skb objects, not the kept view's copy and the hook's own"
ktap_pass "a copy whose view is kept goes when the runtime stops"

check_dmesg && ktap_pass "no Lua errors in kernel"
ktap_totals

