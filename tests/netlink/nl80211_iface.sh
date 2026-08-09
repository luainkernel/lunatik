#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests netlink.nl80211.interface():add/del: loads mac80211_hwsim, creates an AP
# interface on the first simulated wiphy, asserts add returns its ifindex and it
# shows up as an AP in a dump, asserts a second add of the same interface raises,
# then deletes it and confirms it is gone. Skips if mac80211_hwsim is unavailable.
#
# Usage: sudo bash tests/netlink/nl80211_iface.sh

SCRIPT="tests/netlink/nl80211_iface"
MODULE="luasocket"
IFNAME="lunatikap0"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

HWSIM_LOADED=0
cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	ip link del "$IFNAME" 2>/dev/null
	[ "$HWSIM_LOADED" = 1 ] && rmmod mac80211_hwsim 2>/dev/null
}
trap cleanup EXIT

ktap_header
ktap_plan 3

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}
skip() { ktap_skip "$1"; ktap_totals; exit 0; }
modinfo mac80211_hwsim > /dev/null 2>&1 || skip "nl80211_iface: mac80211_hwsim unavailable"
if ! lsmod | grep -q '^mac80211_hwsim'; then
	modprobe mac80211_hwsim radios=2 2>/dev/null || skip "nl80211_iface: mac80211_hwsim failed to load"
	HWSIM_LOADED=1
	for _ in $(seq 1 20); do ip -br link show 2>/dev/null | grep -q wlan && break; sleep 0.1; done
fi

mark_dmesg
run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }

dmesg | grep -q "netlink nl80211_iface: AP interface added" || fail "interface:add did not create the AP"
ktap_pass "interface:add creates an AP and returns its ifindex"

dmesg | grep -q "netlink nl80211_iface: duplicate add raises" || fail "duplicate add did not raise"
ktap_pass "interface:add raises on a rejected interface"

dmesg | grep -q "netlink nl80211_iface: interface deleted" || fail "interface:del did not remove it"
ktap_pass "interface:del removes the interface"

ktap_totals

