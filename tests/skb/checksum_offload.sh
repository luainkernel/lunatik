#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests skb:checksum on packets whose checksum the stack completes after the hook, as they reach
# the wire.
#
# Two namespaces of the test's own, SRC and DST, each join the initial namespace by a veth pair.
# The end in the initial namespace towards DST has tx checksum offload off, so validate_xmit_skb
# completes there, in software, the checksum a CHECKSUM_PARTIAL packet leaves pending, and
# segments a GSO one computing each segment's checksum: DST then receives every packet
# CHECKSUM_NONE, verifies it, and counts a wrong one in InCsumErrors (Tcp and Udp in
# /proc/net/snmp, Udp6InCsumErrors in /proc/net/snmp6). A POST_ROUTING hook calls checksum() on
# every packet of at least PAYLOAD bytes that leaves through that end, and counts them, and those
# longer than the MTU, which are GSO skbs, until a datagram of REPORT bytes closes the case and
# prints the counts. Each case passes when the hook saw its packets, a GSO one among them for a case
# named *gso, and DST counted no checksum error.
#
# The host sends to DST a TCP segment, which leaves CHECKSUM_PARTIAL, and a bulk TCP stream, whose
# skbs leave GSO and CHECKSUM_PARTIAL, over IPv4 and IPv6: checksum() writes the pseudo-header sum
# the completion starts from, where a build that writes the complete checksum there leaves a field
# the completion sums the segment into a second time. A UDP datagram the host sends over IPv4 and
# IPv6 leaves CHECKSUM_NONE, since the device offloads no checksum, and gets the complete one. SRC
# keeps tx offload, so what it sends crosses into the initial namespace CHECKSUM_PARTIAL, which
# forwards it to DST: a UDP datagram, one sent with UDP_SEGMENT, a GSO skb, and a bulk TCP stream,
# each forwarded as it came. A UDP datagram sent over a VXLAN device of the host, with outer UDP
# checksums, leaves CHECKSUM_PARTIAL with the inner checksum pending and the outer one computed for
# it (udp_set_csum): checksum() leaves the outer one as it is, where a build that writes a sum there,
# a seed or a complete checksum taken before the inner one is completed, has DST count it wrong.
#
# SRC also sends with UDP_SEGMENT over a bridge whose port, a third veth, has tx checksum offload
# off: the bridge offloads the checksum, so the socket builds the GSO skb, and the port segments it
# in software into CHECKSUM_NONE segments in one transmit, which the initial end aggregates with
# fraglist GRO (rx-gro-list) into one FRAGLIST GSO skb, CHECKSUM_UNNECESSARY, and forwards to DST.
# checksum() leaves its UDP checksum and its state as they are, where a build that sets it
# CHECKSUM_NONE has the segmentation on the way out print skb_warn_bad_offload's WARNING, which the
# case and check_dmesg read.
#
# Forwarding is turned on for the test's own devices, not for the host, and only over IPv4: IPv6
# forwards only where the host forwards on every device. Skips without veth, socat or ethtool; the
# IPv6 cases skip where IPv6 is off, the VXLAN case without vxlan and the fraglist case on a veth
# without fraglist GRO.
#
# Usage: sudo bash tests/skb/checksum_offload.sh

SCRIPT="tests/skb/checksum_offload"
SRC="lunatik_cksrc"
DST="lunatik_ckdst"
SRC_IF="lunatikcks0"
SRC_PEER="lunatikcks1"
DST_IF="lunatikckd0"
DST_PEER="lunatikckd1" # IFACE in checksum_offload.lua
FL_IF="lunatikckf0"
FL_PEER="lunatikckf1"
BRIDGE="lunatikckbr"
VXLAN="lunatikckvx"
SRC_HOST="10.199.12.1"
SRC_ADDR="10.199.12.2"
DST_HOST="10.199.13.1"
DST_ADDR="10.199.13.2"
DST_FLADDR="10.199.13.3"
DST_HOST6="fd00:1262::1"
DST_ADDR6="fd00:1262::2"
FL_HOST="10.199.14.1"
FL_ADDR="10.199.14.2"
VX_HOST="10.199.15.1"
VX_ADDR="10.199.15.2"
VX_MAC="02:00:00:00:12:62"
VNI=1262
VXPORT=4789
PORT=5580        # TCP over IPv4
PORT6=5581       # TCP over IPv6
UDPPORT=5582
REPORT_PORT=5583
PAYLOAD=400      # PAYLOAD in checksum_offload.lua
REPORT=151       # REPORT in checksum_offload.lua
UDPHDRS=28       # an IPv4 and a UDP header
BULK=$((1 << 20))
SEGMENT=1000
SEGMENTS=4
FLSEGMENTS=8
SOL_UDP=17
UDP_SEGMENT=103
CASES="tcp4 tcp4gso tcp6 tcp6gso udp4 udp6 fwdudp4 fwdudp4gso fwdtcp4gso vxlan fraglist"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	pkill -f "TCP6?-LISTEN:($PORT|$PORT6),reuseaddr,fork" 2>/dev/null
	ip link del "$VXLAN" 2>/dev/null
	ip netns del "$SRC" 2>/dev/null
	ip netns del "$DST" 2>/dev/null
	ip link del "$SRC_PEER" 2>/dev/null
	ip link del "$DST_PEER" 2>/dev/null
	ip link del "$FL_PEER" 2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan $(($(echo $CASES | wc -w) + 1))

skip_all() {
	echo "# SKIP: $1"
	for c in $CASES; do ktap_skip "checksum offload $c"; done
	ktap_skip "no Lua errors, kernel warnings or oopses"
	ktap_totals
	exit 0
}

command -v socat > /dev/null 2>&1 || skip_all "socat unavailable"
command -v ethtool > /dev/null 2>&1 || skip_all "ethtool unavailable"

mac() { ip netns exec "$1" cat "/sys/class/net/$2/address"; }

# pair <netns> <dev> <peer>: a veth pair, <dev> in <netns> and <peer> here, both up
pair() {
	ip link add "$3" type veth peer name "$2" netns "$1" 2> /dev/null || return 1
	ip link set "$3" up
	ip -n "$1" link set "$2" up
}

ip netns add "$SRC"
ip netns add "$DST"
pair "$SRC" "$SRC_IF" "$SRC_PEER" && pair "$DST" "$DST_IF" "$DST_PEER" && pair "$SRC" "$FL_IF" "$FL_PEER" ||
	skip_all "cannot create a veth pair"
ethtool -K "$DST_PEER" tx off > /dev/null 2>&1 || skip_all "cannot turn tx checksum offload off on veth"

ipv6=1
[ "$(cat "/proc/sys/net/ipv6/conf/$DST_PEER/disable_ipv6" 2> /dev/null)" = 0 ] || ipv6=0

ip addr add "$SRC_HOST/30" dev "$SRC_PEER"
ip -n "$SRC" addr add "$SRC_ADDR/30" dev "$SRC_IF"
ip -n "$SRC" route add default via "$SRC_HOST"
ip addr add "$DST_HOST/29" dev "$DST_PEER"
ip -n "$DST" addr add "$DST_ADDR/29" dev "$DST_IF"
ip -n "$DST" addr add "$DST_FLADDR/29" dev "$DST_IF"
ip -n "$DST" route add default via "$DST_HOST"
if [ "$ipv6" = 1 ]; then
	ip addr add "$DST_HOST6/64" dev "$DST_PEER" nodad
	ip -n "$DST" addr add "$DST_ADDR6/64" dev "$DST_IF" nodad
	ip neigh replace "$DST_ADDR6" lladdr "$(mac "$DST" "$DST_IF")" dev "$DST_PEER" nud permanent
	ip -n "$DST" neigh replace "$DST_HOST6" lladdr "$(cat "/sys/class/net/$DST_PEER/address")" dev "$DST_IF" \
		nud permanent
fi
for dev in "$SRC_PEER" "$DST_PEER" "$FL_PEER"; do
	sysctl -qw "net.ipv4.conf.$dev.forwarding=1"
done

# pin the neighbor entries so ARP never holds a packet back
ip neigh replace "$SRC_ADDR" lladdr "$(mac "$SRC" "$SRC_IF")" dev "$SRC_PEER" nud permanent
ip -n "$SRC" neigh replace "$SRC_HOST" lladdr "$(cat "/sys/class/net/$SRC_PEER/address")" dev "$SRC_IF" nud permanent
for addr in "$DST_ADDR" "$DST_FLADDR"; do
	ip neigh replace "$addr" lladdr "$(mac "$DST" "$DST_IF")" dev "$DST_PEER" nud permanent
done
ip -n "$DST" neigh replace "$DST_HOST" lladdr "$(cat "/sys/class/net/$DST_PEER/address")" dev "$DST_IF" nud permanent

declare -A skip

# the fraglist sender: a bridge in SRC whose port has tx checksum offload off
forwarding() { bridge -n "$SRC" link show dev "$FL_IF" 2> /dev/null | grep -q "state forwarding"; }
if ! ip -n "$SRC" link add "$BRIDGE" type bridge 2> /dev/null; then
	skip[fraglist]="no bridge"
elif ! ethtool -K "$FL_PEER" gro on rx-gro-list on > /dev/null 2>&1; then
	skip[fraglist]="no fraglist GRO on veth"
else
	ip netns exec "$SRC" ethtool -K "$FL_IF" tx off > /dev/null 2>&1
	ip -n "$SRC" link set "$FL_IF" master "$BRIDGE"
	ip -n "$SRC" link set "$BRIDGE" up
	ip -n "$SRC" addr add "$FL_ADDR/30" dev "$BRIDGE"
	ip -n "$SRC" route add "$DST_FLADDR/32" via "$FL_HOST" dev "$BRIDGE"
	ip addr add "$FL_HOST/30" dev "$FL_PEER"
	ip neigh replace "$FL_ADDR" lladdr "$(mac "$SRC" "$BRIDGE")" dev "$FL_PEER" nud permanent
	ip -n "$SRC" neigh replace "$FL_HOST" lladdr "$(cat "/sys/class/net/$FL_PEER/address")" dev "$BRIDGE" \
		nud permanent
	# keep IPv6's link-up traffic off the poll that aggregates the datagram
	for dev in "$FL_IF" "$BRIDGE"; do
		ip netns exec "$SRC" sysctl -qw "net.ipv6.conf.$dev.disable_ipv6=1" 2> /dev/null
	done
	TRIES=100 awaited forwarding ||
		skip[fraglist]="the bridge port never forwards"
fi

if ip link add "$VXLAN" type vxlan id "$VNI" remote "$DST_ADDR" local "$DST_HOST" dstport "$VXPORT" \
	udpcsum dev "$DST_PEER" 2> /dev/null; then
	ip link set "$VXLAN" up
	ip addr add "$VX_HOST/30" dev "$VXLAN"
	ip neigh replace "$VX_ADDR" lladdr "$VX_MAC" dev "$VXLAN" nud permanent
else
	skip[vxlan]="no vxlan"
fi

# csumerrors: the checksum errors DST counted, TCP, UDP and UDP over IPv6 summed
csumerrors() {
	ip netns exec "$DST" awk '
		/^(Tcp|Udp):/ { if (!($1 in col)) { for (i = 2; i <= NF; i++) if ($i == "InCsumErrors") col[$1] = i }
			else n += $col[$1] }
		$1 == "Udp6InCsumErrors" { n += $2 }
		END { print n + 0 }' /proc/net/snmp /proc/net/snmp6 2> /dev/null
}

reports=0
reported() { [ "$(dmesg_since | grep -c "skb checksum offload: seen")" -ge "$reports" ]; }

# report: the datagram that closes a case, then the hook's line for it
report() {
	reports=$((reports + 1))
	head -c $((REPORT - UDPHDRS)) /dev/zero | socat -u - "UDP:$DST_ADDR:$REPORT_PORT" 2> /dev/null
	awaited reported
}

# the stimuli, one per case
send() { head -c "$1" /dev/zero | timeout 10 socat -u - "$2" 2> /dev/null; }
fromsrc() { ip netns exec "$SRC" timeout 10 socat -u "OPEN:/dev/zero,readbytes=$1" "$2" 2> /dev/null; }
segmented() { ip netns exec "$SRC" timeout 10 socat -u -b $(($1 * SEGMENT)) \
	"OPEN:/dev/zero,readbytes=$(($1 * SEGMENT))" "$2,setsockopt-int=$SOL_UDP:$UDP_SEGMENT:$SEGMENT" 2> /dev/null; }

stimulate() {
	case $1 in
	tcp4) send "$PAYLOAD" "TCP:$DST_ADDR:$PORT" ;;
	tcp4gso) send "$BULK" "TCP:$DST_ADDR:$PORT" ;;
	tcp6) send "$PAYLOAD" "TCP6:[$DST_ADDR6]:$PORT6" ;;
	tcp6gso) send "$BULK" "TCP6:[$DST_ADDR6]:$PORT6" ;;
	udp4) send "$PAYLOAD" "UDP:$DST_ADDR:$UDPPORT" ;;
	udp6) send "$PAYLOAD" "UDP6:[$DST_ADDR6]:$UDPPORT" ;;
	fwdudp4) fromsrc "$PAYLOAD" "UDP:$DST_ADDR:$UDPPORT" ;;
	fwdudp4gso) segmented "$SEGMENTS" "UDP:$DST_ADDR:$UDPPORT" ;;
	fwdtcp4gso) fromsrc "$BULK" "TCP:$DST_ADDR:$PORT" ;;
	vxlan) send "$PAYLOAD" "UDP:$VX_ADDR:$UDPPORT" ;;
	fraglist) segmented "$FLSEGMENTS" "UDP:$DST_FLADDR:$UDPPORT" ;;
	esac
}

listening() {
	[ -n "$(ip netns exec "$DST" ss -tHln "sport = :$PORT" 2> /dev/null)" ] &&
		{ [ "$ipv6" = 0 ] || [ -n "$(ip netns exec "$DST" ss -tHln "sport = :$PORT6" 2> /dev/null)" ]; }
}

mark_dmesg
run_script --context=softirq "$SCRIPT"

ip netns exec "$DST" socat -u "TCP-LISTEN:$PORT,reuseaddr,fork" OPEN:/dev/null &
[ "$ipv6" = 1 ] && ip netns exec "$DST" socat -u "TCP6-LISTEN:$PORT6,reuseaddr,fork" OPEN:/dev/null &
TRIES=20 awaited listening

declare -A verdict
for c in $CASES; do
	case $c in *6*) [ "$ipv6" = 1 ] || skip[$c]="IPv6 is off" ;; esac
	[ -n "${skip[$c]}" ] && continue
	before=$(csumerrors)
	warnings=$(dmesg_since | grep -c "WARNING:")
	stimulate "$c"
	sleep 0.5 # what SRC sent crosses its veth and the forward before the report
	report || { verdict[$c]="the hook never closed the case"; continue; }
	line=$(dmesg_since | grep "skb checksum offload: seen" | sed -n "${reports}p")
	seen=$(sed 's/.* seen \([0-9]*\) gso.*/\1/' <<< "$line")
	gso=$(sed 's/.* gso \([0-9]*\).*/\1/' <<< "$line")
	errors=$(($(csumerrors) - before))
	if [ "$seen" -eq 0 ]; then
		verdict[$c]="the hook saw no packet"
	elif [ "${c%gso}" != "$c" ] || [ "$c" = fraglist ] && [ "$gso" -eq 0 ]; then
		verdict[$c]="the hook saw no GSO skb among $seen packets"
	elif [ "$errors" -ne 0 ]; then
		verdict[$c]="DST counted $errors checksum errors"
	elif [ "$(dmesg_since | grep -c "WARNING:")" -ne "$warnings" ]; then
		verdict[$c]="the kernel warned"
	else
		verdict[$c]=ok
	fi
done

lunatik stop "$SCRIPT"
pkill -f "TCP6?-LISTEN:($PORT|$PORT6),reuseaddr,fork" 2>/dev/null

for c in $CASES; do
	if [ -n "${skip[$c]}" ]; then
		ktap_skip "checksum offload $c — ${skip[$c]}"
	elif [ "${verdict[$c]}" = ok ]; then
		ktap_pass "checksum offload $c"
	else
		ktap_fail "checksum offload $c: ${verdict[$c]}"
	fi
done

check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"
ktap_totals

