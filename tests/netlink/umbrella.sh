#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# require("netlink") carries rt, genl and nl80211 without loading luanetlink.
#
# A kernel require holds the module it loads until the requiring state closes,
# so luanetlink's refcnt reads how many runtimes required the channel.
# umbrella_channel.lua requires netlink.channel and raises it by one until its
# stop, which is what the next read relies on. umbrella.lua then requires
# netlink alone: while it runs, the refcnt is where it was, so an umbrella that
# loaded the channel again would fail here.
#
# Usage: sudo bash tests/netlink/umbrella.sh

SCRIPT="tests/netlink/umbrella"
CHANNEL="tests/netlink/umbrella_channel"
MODULE="luanetlink"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	lunatik stop "$CHANNEL" 2>/dev/null
}

skip_all() { ktap_header; ktap_plan 1; ktap_skip "$1"; ktap_totals; exit 0; }

refcnt() { cat "/sys/module/$MODULE/refcnt" 2>/dev/null; }

trap cleanup EXIT
cleanup

before=$(refcnt) || skip_all "$MODULE not loaded"

ktap_header
ktap_plan 3

mark_dmesg
run_script "$CHANNEL"
[ "$(refcnt)" -eq $((before + 1)) ] || fail "$MODULE refcnt $before -> $(refcnt) while netlink.channel is required, not one more"
lunatik stop "$CHANNEL" 2>/dev/null
[ "$(refcnt)" -eq "$before" ] || fail "$MODULE refcnt $before -> $(refcnt) after the channel's runtime stopped"
ktap_pass "umbrella: a runtime that requires netlink.channel holds $MODULE until its stop"

run_script "$SCRIPT"
[ "$(refcnt)" -eq "$before" ] || fail "$MODULE refcnt $before -> $(refcnt) while netlink is required: the umbrella loads the channel"
lunatik stop "$SCRIPT" 2>/dev/null
ktap_pass "umbrella: a runtime that requires netlink leaves $MODULE unheld"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

