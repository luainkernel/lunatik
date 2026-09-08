#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# The netdevice chain is global: register_netdevice_notifier replays and
# delivers events for every network namespace, and a device name is unique only
# within one. So a callback given the name alone cannot tell a device it can
# resolve from a homonymous one it cannot, and resolving the wrong one silently
# acts on another device.
#
# The test creates the same device name in the initial namespace and in another
# one, and asserts that both are reported, each carrying the index and the
# namespace inode number that identify it. It deliberately does not assert that
# a foreign device is hidden: narrowing the chain to one namespace is the shape
# this replaced, and a green test for it would make restoring generality a
# regression.
#
# Ground truth comes from the shell: /sys/class/net/<dev>/ifindex for the index
# and /proc/self/ns/net for the namespace, read on each side. That ground truth
# needs the suite to run in the initial namespace, read as PID 1 sharing its
# namespace: a container whose PID 1 is inside one too passes that check and
# fails the first case instead of skipping.
#
# Usage: sudo bash tests/notifier/device_identity.sh

SCRIPT="tests/notifier/device_identity"
NETNS="lunatik_ni"
REPLAYDEV="lnid0"
LIVEDEV="lnid1"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	ip netns del "$NETNS" 2>/dev/null
	ip link del "$REPLAYDEV" 2>/dev/null
	ip link del "$LIVEDEV" 2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 8

skip_all() {
	echo "# SKIP: $1"
	ktap_skip "linux.netns() names the namespace the suite runs in"
	ktap_skip "replay reports a device of the initial namespace as its own"
	ktap_skip "replay reports a homonymous device of another namespace as foreign"
	ktap_skip "live register reports a device of the initial namespace as its own"
	ktap_skip "live register reports a homonymous device of another namespace as foreign"
	ktap_skip "live unregister reports the foreign device with the identity it had"
	ktap_skip "live unregister reports the own device with the identity it had"
	ktap_skip "no Lua errors in kernel"
	ktap_totals
	exit 0
}

# the inode number readlink prints as net:[<inum>], which is what the binding reports
netns_inum() {
	local link
	link=$("$@" readlink /proc/self/ns/net) || return 1
	link="${link#net:\[}"
	echo "${link%\]}"
}

command -v ip > /dev/null 2>&1 || skip_all "ip not available"
[ "$(readlink /proc/1/ns/net)" = "$(readlink /proc/self/ns/net)" ] ||
	skip_all "suite runs in a network namespace of its own, no ground truth for linux.netns()"
ip link add "$REPLAYDEV" type dummy 2>/dev/null || skip_all "cannot create a dummy device"
ip netns add "$NETNS" 2>/dev/null || skip_all "cannot create a network namespace"
ip netns exec "$NETNS" ip link add "$REPLAYDEV" type dummy 2>/dev/null ||
	skip_all "cannot create a dummy device in another namespace"

OWN_NETNS=$(netns_inum) || fail "cannot read the namespace of the suite"
FOREIGN_NETNS=$(netns_inum ip netns exec "$NETNS") || fail "cannot read the namespace of $NETNS"
[ "$OWN_NETNS" != "$FOREIGN_NETNS" ] || fail "$NETNS reports the namespace the suite runs in"

own_replay=$(cat "/sys/class/net/$REPLAYDEV/ifindex")
foreign_replay=$(ip netns exec "$NETNS" cat "/sys/class/net/$REPLAYDEV/ifindex")

mark_dmesg
run_script "$SCRIPT"

dmesg_since | grep -qF "device_identity: netns $OWN_NETNS" ||
	fail "linux.netns() did not report $OWN_NETNS"
ktap_pass "linux.netns() names the namespace the suite runs in"

dmesg_since | grep -qF "device_identity: register $REPLAYDEV $own_replay $OWN_NETNS own" ||
	fail "replay did not report $REPLAYDEV of the initial namespace (ifindex $own_replay)"
ktap_pass "replay reports a device of the initial namespace as its own"

dmesg_since | grep -qF "device_identity: register $REPLAYDEV $foreign_replay $FOREIGN_NETNS foreign" ||
	fail "replay did not report $REPLAYDEV of $NETNS (ifindex $foreign_replay)"
ktap_pass "replay reports a homonymous device of another namespace as foreign"

ip link add "$LIVEDEV" type dummy || fail "cannot create $LIVEDEV"
own_live=$(cat "/sys/class/net/$LIVEDEV/ifindex")
dmesg_since | grep -qF "device_identity: register $LIVEDEV $own_live $OWN_NETNS own" ||
	fail "live register did not report $LIVEDEV of the initial namespace (ifindex $own_live)"
ktap_pass "live register reports a device of the initial namespace as its own"

ip netns exec "$NETNS" ip link add "$LIVEDEV" type dummy || fail "cannot create $LIVEDEV in $NETNS"
foreign_live=$(ip netns exec "$NETNS" cat "/sys/class/net/$LIVEDEV/ifindex")
dmesg_since | grep -qF "device_identity: register $LIVEDEV $foreign_live $FOREIGN_NETNS foreign" ||
	fail "live register did not report $LIVEDEV of $NETNS (ifindex $foreign_live)"
ktap_pass "live register reports a homonymous device of another namespace as foreign"

ip netns exec "$NETNS" ip link del "$LIVEDEV" || fail "cannot delete $LIVEDEV from $NETNS"
dmesg_since | grep -qF "device_identity: unregister $LIVEDEV $foreign_live $FOREIGN_NETNS foreign" ||
	fail "live unregister did not report $LIVEDEV of $NETNS (ifindex $foreign_live)"
ktap_pass "live unregister reports the foreign device with the identity it had"

ip link del "$LIVEDEV" || fail "cannot delete $LIVEDEV"
dmesg_since | grep -qF "device_identity: unregister $LIVEDEV $own_live $OWN_NETNS own" ||
	fail "live unregister did not report $LIVEDEV of the initial namespace (ifindex $own_live)"
ktap_pass "live unregister reports the own device with the identity it had"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

