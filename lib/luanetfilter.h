/*
* SPDX-FileCopyrightText: (c) 2024-2025 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Low-level Lua interface to the Linux Kernel Netfilter framework.
*
* This header file defines constants used by the C implementation and exposed to Lua.
*
* @module netfilter
*/

#ifndef luanetfilter_h
#define luanetfilter_h

#include <linux/netfilter.h>
#include <linux/netfilter_ipv4.h>
#include <linux/netfilter_bridge.h>
#include <linux/netfilter_arp.h>
#include <linux/netfilter/x_tables.h>

#include <lunatik.h>


/***
* Table of Netfilter protocol families.
* @table family
*   @field UNSPEC Unspecified protocol family.
*   @tfield integer UNSPEC Unspecified protocol family.
*   @tfield integer INET Internetwork protocol family (covering IPv4/IPv6).
*   @tfield integer IPV4 Internet Protocol version 4.
*   @tfield integer IPV6 Internet Protocol version 6.
*   @tfield integer ARP Address Resolution Protocol.
*   @tfield integer NETDEV Network device hooks (ingress/egress).
*   @tfield integer BRIDGE Ethernet bridging hooks.
*/
const lunatik_reg_t luanetfilter_family[] = {
	{"UNSPEC", NFPROTO_UNSPEC},
	{"INET", NFPROTO_INET},
	{"IPV4", NFPROTO_IPV4},
	{"IPV6", NFPROTO_IPV6},
	{"ARP", NFPROTO_ARP},
	{"NETDEV", NFPROTO_NETDEV},
	{"BRIDGE", NFPROTO_BRIDGE},
	{NULL, 0}
};

/***
* Table of Netfilter hook verdicts (actions).
* These determine the fate of a packet processed by a hook.
* @table action
*   @tfield integer DROP Drop the packet silently.
*   @tfield integer ACCEPT Let the packet pass.
*   @tfield integer STOLEN Packet is consumed by the hook; processing stops.
*   @tfield integer QUEUE Queue the packet to a userspace program.
*   @tfield integer REPEAT Re-inject the packet into the current hook (use with caution).
*   @tfield integer STOP Terminate rule traversal in the current chain (iptables specific).
*   @tfield integer CONTINUE Alias for ACCEPT, primarily for Xtables.
*   @tfield integer RETURN Return from the current chain to the calling chain (iptables specific).
*/
const lunatik_reg_t luanetfilter_action[] = {
	{"DROP", NF_DROP},
	{"ACCEPT", NF_ACCEPT},
	{"STOLEN", NF_STOLEN},
	{"QUEUE", NF_QUEUE},
	{"REPEAT", NF_REPEAT},
	{"STOP", NF_STOP},
	{"CONTINUE", XT_CONTINUE},
	{"RETURN", XT_RETURN},
	{NULL, 0}
};

/***
* Table of Netfilter hooks in the INET (IPv4/IPv6) family.
* These define points in the network stack where packet processing can occur.
* @table inet_hooks
*   @tfield integer PRE_ROUTING After packet reception, before routing decision.
*   @tfield integer LOCAL_IN For packets destined to the local machine, after routing.
*   @tfield integer FORWARD For packets to be forwarded to another interface, after routing.
*   @tfield integer LOCAL_OUT For packets generated locally, before sending to an interface.
*   @tfield integer POST_ROUTING Before packets are sent out, after routing and just before handing to hardware.
*/
const lunatik_reg_t luanetfilter_inet_hooks[] = {
	{"PRE_ROUTING", NF_INET_PRE_ROUTING},
	{"LOCAL_IN", NF_INET_LOCAL_IN},
	{"FORWARD", NF_INET_FORWARD},
	{"LOCAL_OUT", NF_INET_LOCAL_OUT},
	{"POST_ROUTING", NF_INET_POST_ROUTING},
	{NULL, 0}
};

/***
* Table of Netfilter hooks in the BRIDGE family.
* These define points for processing layer 2 (Ethernet) bridge traffic.
* @table bridge_hooks
*   @tfield integer PRE_ROUTING For packets entering the bridge, before any bridge processing (e.g., ebtables broute chain).
*   @tfield integer LOCAL_IN For bridged packets destined for the bridge interface itself (if IP processing is enabled on the bridge).
*   @tfield integer FORWARD For packets being forwarded by the bridge between its ports (e.g., ebtables filter chain).
*   @tfield integer LOCAL_OUT For packets originating from the bridge interface itself.
*   @tfield integer POST_ROUTING For packets leaving the bridge, after all bridge processing (e.g., ebtables nat chain).
*/
static const lunatik_reg_t luanetfilter_bridge_hooks[] = {
	{"PRE_ROUTING", NF_BR_PRE_ROUTING},
	{"LOCAL_IN", NF_BR_LOCAL_IN},
	{"FORWARD", NF_BR_FORWARD},
	{"LOCAL_OUT", NF_BR_LOCAL_OUT},
	{"POST_ROUTING", NF_BR_POST_ROUTING},
	{NULL, 0},
};

/***
* Table of Netfilter hooks in the ARP family.
* @table arp_hooks
*   @tfield integer IN For incoming ARP packets.
*   @tfield integer OUT For outgoing ARP packets.
*   @tfield integer FORWARD For forwarded ARP packets (e.g., by an ARP proxy).
*/
static const lunatik_reg_t luanetfilter_arp_hooks[] = {
	{"IN", NF_ARP_IN},
	{"OUT", NF_ARP_OUT},
	{"FORWARD", NF_ARP_FORWARD},
	{NULL, 0}
};

/***
* Table of Netfilter hooks in the NETDEV family.
* These hooks operate at the network device driver level.
* @table netdev_hooks
*   @tfield integer INGRESS For packets as they are received by a network device, very early in the stack.
*   @tfield integer EGRESS For packets just before they are transmitted by a network device, very late in the stack (Kernel 5.16+).
*/
const lunatik_reg_t luanetfilter_netdev_hooks[] = {
    {"INGRESS", NF_NETDEV_INGRESS},
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 16, 0)
    {"EGRESS", NF_NETDEV_EGRESS},
#endif
    {NULL, 0}
};

/***
* Table of Netfilter hook priorities in the IP family.
* Hooks with lower priority numbers are called earlier within the same hook point.
* @table ip_priority
*   @tfield integer FIRST Highest priority, hook runs first.
*   @tfield integer RAW_BEFORE_DEFRAG Priority for `raw` table processing, before packet defragmentation.
*   @tfield integer CONNTRACK_DEFRAG Priority for connection tracking related to defragmentation.
*   @tfield integer RAW Priority for `raw` table processing.
*   @tfield integer SELINUX_FIRST Early priority for SELinux hooks.
*   @tfield integer CONNTRACK Priority for main connection tracking.
*   @tfield integer MANGLE Priority for `mangle` table processing (packet alteration).
*   @tfield integer NAT_DST Priority for Destination NAT (`nat` table, PREROUTING/OUTPUT).
*   @tfield integer FILTER Priority for `filter` table processing (packet filtering).
*   @tfield integer SECURITY Priority for security modules like SELinux.
*   @tfield integer NAT_SRC Priority for Source NAT (`nat` table, POSTROUTING/INPUT).
*   @tfield integer SELINUX_LAST Late priority for SELinux hooks.
*   @tfield integer CONNTRACK_HELPER Priority for connection tracking helper modules.
*   @tfield integer LAST Lowest priority, hook runs last.
*/
static const lunatik_reg_t luanetfilter_ip_priority[] = {
	{"FIRST", NF_IP_PRI_FIRST},
	{"RAW_BEFORE_DEFRAG", NF_IP_PRI_RAW_BEFORE_DEFRAG},
	{"CONNTRACK_DEFRAG", NF_IP_PRI_CONNTRACK_DEFRAG},
	{"RAW", NF_IP_PRI_RAW},
	{"SELINUX_FIRST", NF_IP_PRI_SELINUX_FIRST},
	{"CONNTRACK", NF_IP_PRI_CONNTRACK},
	{"MANGLE", NF_IP_PRI_MANGLE},
	{"NAT_DST", NF_IP_PRI_NAT_DST},
	{"FILTER", NF_IP_PRI_FILTER},
	{"SECURITY", NF_IP_PRI_SECURITY},
	{"NAT_SRC", NF_IP_PRI_NAT_SRC},
	{"SELINUX_LAST", NF_IP_PRI_SELINUX_LAST},
	{"CONNTRACK_HELPER", NF_IP_PRI_CONNTRACK_HELPER},
	{"LAST", NF_IP_PRI_LAST},
	{NULL, 0},
};

/***
* Table of Netfilter hook priorities in the BRIDGE family.
* Hooks with lower priority numbers are called earlier.
* @table bridge_priority
*   @tfield integer FIRST Highest priority for bridge hooks.
*   @tfield integer NAT_DST_BRIDGED Priority for Destination NAT on bridged-only packets (ebtables `dnat` chain).
*   @tfield integer FILTER_BRIDGED Priority for filtering bridged-only packets (ebtables `filter` chain in FORWARD).
*   @tfield integer BRNF Priority for bridge netfilter specific operations (interaction between bridge and IP stack).
*   @tfield integer NAT_DST_OTHER Priority for Destination NAT on packets routed through the bridge (iptables `PREROUTING` on bridge interface).
*   @tfield integer FILTER_OTHER Priority for filtering packets routed through the bridge (iptables `FORWARD` or `INPUT` on bridge interface).
*   @tfield integer NAT_SRC Priority for Source NAT on bridged or routed packets (ebtables `snat` or iptables `POSTROUTING`).
*   @tfield integer LAST Lowest priority for bridge hooks.
*/
static const lunatik_reg_t luanetfilter_bridge_priority[] = {
	{"FIRST", NF_BR_PRI_FIRST},
	{"NAT_DST_BRIDGED", NF_BR_PRI_NAT_DST_BRIDGED},
	{"FILTER_BRIDGED", NF_BR_PRI_FILTER_BRIDGED},
	{"BRNF", NF_BR_PRI_BRNF},
	{"NAT_DST_OTHER", NF_BR_PRI_NAT_DST_OTHER},
	{"FILTER_OTHER", NF_BR_PRI_FILTER_OTHER},
	{"NAT_SRC", NF_BR_PRI_NAT_SRC},
	{"LAST", NF_BR_PRI_LAST},
	{NULL, 0},
};

static const lunatik_namespace_t luanetfilter_flags[] = {
	{"family", luanetfilter_family},
	{"action", luanetfilter_action},
	{"inet_hooks", luanetfilter_inet_hooks},
	{"bridge_hooks", luanetfilter_bridge_hooks},
	{"arp_hooks", luanetfilter_arp_hooks},
	{"netdev_hooks", luanetfilter_netdev_hooks},
	{"ip_priority", luanetfilter_ip_priority},
	{"bridge_priority", luanetfilter_bridge_priority},
	{NULL, NULL}
};

#endif

