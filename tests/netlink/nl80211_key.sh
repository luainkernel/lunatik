#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests netlink.nl80211.key():add/del: loads mac80211_hwsim, brings up a
# beaconing AP, installs a group key (GTK) as hostapd does right after
# START_AP, asserts an out-of-range key index raises, then removes the key --
# the group-key control plane from the kernel. The pairwise (PTK) path needs a
# real association and is exercised by the WPA handshake test. Skips if
# mac80211_hwsim is absent.
#
# Usage: sudo bash tests/netlink/nl80211_key.sh

SCRIPT="tests/netlink/nl80211_key"
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
cleanup

ktap_header
ktap_plan 3

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}
skip() { ktap_skip "$1"; ktap_totals; exit 0; }
modinfo mac80211_hwsim > /dev/null 2>&1 || skip "nl80211_key: mac80211_hwsim unavailable"
if ! lsmod | grep -q '^mac80211_hwsim'; then
	modprobe mac80211_hwsim radios=2 2>/dev/null || skip "nl80211_key: mac80211_hwsim failed to load"
	HWSIM_LOADED=1
	for _ in $(seq 1 20); do ip -br link show 2>/dev/null | grep -q wlan && break; sleep 0.1; done
fi

mark_dmesg
run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }

dmesg | grep -q "netlink nl80211_key: gtk installed" || fail "group key install failed"
ktap_pass "key:add installs a group key (GTK)"

dmesg | grep -q "netlink nl80211_key: bad index raises" || fail "out-of-range index did not raise"
ktap_pass "key:add raises on an out-of-range index"

dmesg | grep -q "netlink nl80211_key: gtk removed" || fail "group key removal failed"
ktap_pass "key:del removes the group key"

ktap_totals

