/*
* SPDX-FileCopyrightText: (c) 2024-2025 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef luanetfilter_h
#define luanetfilter_h

#include <linux/netfilter.h>
#include <linux/netfilter_ipv4.h>
#include <linux/netfilter_bridge.h>
#include <linux/netfilter_arp.h>
#include <linux/netfilter/x_tables.h>

#include <lunatik.h>

#define luanetfilter_newbuffer(L, obj, field)		\
do {							\
	obj->field = lunatik_checknull(L, luadata_new(NULL, 0, false, LUADATA_OPT_NONE));	\
	lunatik_cloneobject(L, obj->field);		\
	lunatik_setregistry(L, -1, obj->field);	\
	lua_pop(L, 1); /* skb */			\
} while (0)

#define lunatik_setinteger(L, idx, hook, field) 		\
do {								\
	lunatik_checkfield(L, idx, #field, LUA_TNUMBER);	\
	hook->field = lua_tointeger(L, -1);			\
	lua_pop(L, 1);						\
} while (0)

#define lunatik_setstring(L, idx, hook, field, maxlen)        \
do {								\
	size_t len;						\
	lunatik_checkfield(L, idx, #field, LUA_TSTRING);	\
	const char *str = lua_tolstring(L, -1, &len);			\
	if (len > maxlen)					\
		luaL_error(L, "'%s' is too long", #field);	\
	strncpy((char *)hook->field, str, maxlen);		\
	lua_pop(L, 1);						\
} while (0)

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

const lunatik_reg_t luanetfilter_inet_hooks[] = {
	{"PRE_ROUTING", NF_INET_PRE_ROUTING},
	{"LOCAL_IN", NF_INET_LOCAL_IN},
	{"FORWARD", NF_INET_FORWARD},
	{"LOCAL_OUT", NF_INET_LOCAL_OUT},
	{"POST_ROUTING", NF_INET_POST_ROUTING},
	{NULL, 0}
};

static const lunatik_reg_t luanetfilter_bridge_hooks[] = {
	{"PRE_ROUTING", NF_BR_PRE_ROUTING},
	{"LOCAL_IN", NF_BR_LOCAL_IN},
	{"FORWARD", NF_BR_FORWARD},
	{"LOCAL_OUT", NF_BR_LOCAL_OUT},
	{"POST_ROUTING", NF_BR_POST_ROUTING},
	{NULL, 0},
};

static const lunatik_reg_t luanetfilter_arp_hooks[] = {
	{"IN", NF_ARP_IN},
	{"OUT", NF_ARP_OUT},
	{"FORWARD", NF_ARP_FORWARD},
	{NULL, 0}
};

const lunatik_reg_t luanetfilter_netdev_hooks[] = {
    {"INGRESS", NF_NETDEV_INGRESS},
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 16, 0)
    {"EGRESS", NF_NETDEV_EGRESS},
#endif
    {NULL, 0}
};

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

