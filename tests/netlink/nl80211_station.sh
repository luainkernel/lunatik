#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests netlink.nl80211.station():add/del/set/list: loads mac80211_hwsim, brings
# up a beaconing AP, adds a station and asserts it is listed, asserts a duplicate
# add raises, sets it authorized, then deletes it and asserts it is gone — the
# whole station control plane from the kernel. Skips if mac80211_hwsim is absent.
#
# Usage: sudo bash tests/netlink/nl80211_station.sh

SCRIPT="tests/netlink/nl80211_station"
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
ktap_plan 4

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}
skip() { ktap_skip "$1"; ktap_totals; exit 0; }
modinfo mac80211_hwsim > /dev/null 2>&1 || skip "nl80211_station: mac80211_hwsim unavailable"
if ! lsmod | grep -q '^mac80211_hwsim'; then
	modprobe mac80211_hwsim radios=2 2>/dev/null || skip "nl80211_station: mac80211_hwsim failed to load"
	HWSIM_LOADED=1
	for _ in $(seq 1 20); do ip -br link show 2>/dev/null | grep -q wlan && break; sleep 0.1; done
fi

mark_dmesg
run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }

dmesg | grep -q "netlink nl80211_station: added" || fail "station:add did not add the station"
ktap_pass "station:add adds a station, visible in a dump"

dmesg | grep -q "netlink nl80211_station: duplicate add raises" || fail "duplicate add did not raise"
ktap_pass "station:add raises on a duplicate"

dmesg | grep -q "netlink nl80211_station: authorized" || fail "station:set authorized failed"
ktap_pass "station:set{authorized} is accepted (STA_FLAGS2 path)"

dmesg | grep -q "netlink nl80211_station: deleted" || fail "station:del did not remove it"
ktap_pass "station:del removes the station"

ktap_totals

