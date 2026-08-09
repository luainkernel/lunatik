#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests netlink.nl80211: loads mac80211_hwsim (simulated wifi radios), then the
# module lists the simulated wlan interfaces over the nl80211 generic netlink
# family (asserting one is present, in STATION mode and with its fields decoded)
# and asserts both simulated wiphys come out of the fragmented GET_WIPHY dump.
# Skips if mac80211_hwsim is unavailable.
#
# Usage: sudo bash tests/netlink/nl80211.sh

SCRIPT="tests/netlink/nl80211"
MODULE="luasocket"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

HWSIM_LOADED=0
cleanup() { lunatik stop "$SCRIPT" 2>/dev/null; [ "$HWSIM_LOADED" = 1 ] && rmmod mac80211_hwsim 2>/dev/null; }
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 3

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}
skip() { ktap_skip "$1"; ktap_totals; exit 0; }
modinfo mac80211_hwsim > /dev/null 2>&1 || skip "nl80211: mac80211_hwsim unavailable"
if ! lsmod | grep -q '^mac80211_hwsim'; then
	modprobe mac80211_hwsim radios=2 2>/dev/null || skip "nl80211: mac80211_hwsim failed to load"
	HWSIM_LOADED=1
	for _ in $(seq 1 20); do ip -br link show 2>/dev/null | grep -q wlan && break; sleep 0.1; done
fi

mark_dmesg
run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }

dmesg | grep -q "netlink nl80211: hwsim interface listed" || fail "no wlan interface listed"
ktap_pass "nl80211: hwsim interface listed"

dmesg | grep -q "netlink nl80211: interface is STATION" || fail "interface not in STATION mode"
ktap_pass "nl80211: interface reports STATION iftype"

dmesg | grep -q "netlink nl80211: wiphys accumulated" || fail "wiphy accumulation incomplete"
ktap_pass "nl80211: both hwsim wiphys accumulated from the fragmented dump"

ktap_totals

