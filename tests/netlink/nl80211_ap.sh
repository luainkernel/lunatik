#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests netlink.nl80211.ap():start/stop: loads mac80211_hwsim, creates an AP
# interface on the first simulated wiphy, brings it up (rt.link), starts
# beaconing with a minimal open-AP beacon on channel 1 and then stops it,
# entirely from the kernel. Skips if mac80211_hwsim is unavailable.
#
# The wiphy goes into a network namespace of the test's own (netns.sh) and every
# session the script opens takes the pid of the process kept there: in the
# initial namespace the interface is one a network manager may take and bring
# down under the test, which stops the AP and flushes its stations.
#
# Usage: sudo bash tests/netlink/nl80211_ap.sh

SCRIPT="tests/netlink/nl80211_ap"
MODULE="luasocket"
IFNAME="lunatikap0"
NETNS="lunatik_nl80211_ap"

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
ktap_plan 3

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}
skip() { ktap_skip "$1"; ktap_totals; exit 0; }
command -v iw > /dev/null 2>&1 && command -v nsenter > /dev/null 2>&1 || skip "nl80211_ap: iw or nsenter not available"
modinfo mac80211_hwsim > /dev/null 2>&1 || skip "nl80211_ap: mac80211_hwsim unavailable"
if ! lsmod | grep -q '^mac80211_hwsim'; then
	modprobe mac80211_hwsim radios=2 2>/dev/null || skip "nl80211_ap: mac80211_hwsim failed to load"
	HWSIM_LOADED=1
	for _ in $(seq 1 20); do ip -br link show 2>/dev/null | grep -q wlan && break; sleep 0.1; done
fi

netns_up || skip "nl80211_ap: cannot create a network namespace"
netns_wiphy || skip "nl80211_ap: cannot move a hwsim wiphy into $NETNS"
echo "return $NSPID" > "$PIDMOD"

mark_dmesg
run_script "$SCRIPT"
rm -f "$PIDMOD"
check_dmesg || { ktap_totals; exit 1; }

dmesg | grep -q "netlink nl80211_ap: AP started" || fail "ap:start did not bring up the AP"
ktap_pass "ap:start begins beaconing on an AP interface"

dmesg | grep -q "netlink nl80211_ap: second start raises" || fail "second ap:start did not raise"
ktap_pass "ap:start raises on an already-beaconing AP"

dmesg | grep -q "netlink nl80211_ap: AP stopped" || fail "ap:stop did not stop the AP"
ktap_pass "ap:stop stops beaconing"

ktap_totals

