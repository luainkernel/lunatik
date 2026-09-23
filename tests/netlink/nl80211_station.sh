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
# The wiphy goes into a network namespace of the test's own (netns.sh) and every
# session the script opens takes the pid of the process kept there: in the
# initial namespace the interface is one a network manager may take and bring
# down under the test, which stops the AP and flushes its stations.
#
# Usage: sudo bash tests/netlink/nl80211_station.sh

SCRIPT="tests/netlink/nl80211_station"
MODULE="luasocket"
IFNAME="lunatikap0"
NETNS="lunatik_nl80211_station"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"
source "$(dirname "$(readlink -f "$0")")/../netns.sh"

HWSIM_LOADED=0
cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	iw dev "$IFNAME" del 2>/dev/null
	ip netns exec "$NETNS" iw dev "$IFNAME" del 2>/dev/null
	netns_down
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
command -v iw > /dev/null 2>&1 && command -v nsenter > /dev/null 2>&1 || skip "nl80211_station: iw or nsenter not available"
modinfo mac80211_hwsim > /dev/null 2>&1 || skip "nl80211_station: mac80211_hwsim unavailable"
if ! lsmod | grep -q '^mac80211_hwsim'; then
	modprobe mac80211_hwsim radios=2 2>/dev/null || skip "nl80211_station: mac80211_hwsim failed to load"
	HWSIM_LOADED=1
	for _ in $(seq 1 20); do ip -br link show 2>/dev/null | grep -q wlan && break; sleep 0.1; done
fi

netns_up || skip "nl80211_station: cannot create a network namespace"
netns_wiphy || skip "nl80211_station: cannot move a hwsim wiphy into $NETNS"
echo "return $NSPID" > "$PIDMOD"

mark_dmesg
run_script "$SCRIPT"
rm -f "$PIDMOD"
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

