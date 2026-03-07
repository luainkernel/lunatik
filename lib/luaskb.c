/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Linux socket buffer interface.
* @module skb
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/skbuff.h>
#include <linux/if_vlan.h>
#include <linux/netdevice.h>
#include <linux/tcp.h>
#include <linux/udp.h>
#include <net/ip.h>

#include "luaskb.h"

LUNATIK_PRIVATECHECKER(luaskb_check, luaskb_t *,
	luaL_argcheck(L, private->skb != NULL, ix, "skb is not set");
);

#define luaskb_pushoptinteger(L, cond, val)	\
	((cond) ? lua_pushinteger(L, val) : lua_pushnil(L))

#define luaskb_csum(skb, iph, iphlen, proto, len)		\
	csum_tcpudp_magic((iph)->saddr, (iph)->daddr, (len), (proto),	\
		skb_checksum((skb), (iphlen), (len), 0))

/***
* @function __len
* @treturn integer skb length in bytes
*/
static int luaskb_len(lua_State *L)
{
	luaskb_t *lskb = luaskb_check(L, 1);
	lua_pushinteger(L, lskb->skb->len);
	return 1;
}

/***
* @function ifindex
* @treturn integer network interface index, or nil if not available
*/
static int luaskb_ifindex(lua_State *L)
{
	luaskb_t *lskb = luaskb_check(L, 1);
	struct net_device *dev = lskb->skb->dev;
	luaskb_pushoptinteger(L, dev, dev->ifindex);
	return 1;
}

/***
* @function vlan
* @treturn integer VLAN tag ID, or nil if not present
*/
static int luaskb_vlan(lua_State *L)
{
	luaskb_t *lskb = luaskb_check(L, 1);
	struct sk_buff *skb = lskb->skb;
	luaskb_pushoptinteger(L, skb_vlan_tag_present(skb), skb_vlan_tag_get_id(skb));
	return 1;
}

/***
* @function data
* @tparam[opt] string layer "net" (default, L3) or "mac" (L2, includes MAC header)
* @treturn data
* @raise if linearization fails, MAC header is not set, or layer is invalid
*/
static int luaskb_data(lua_State *L)
{
	luaskb_t *lskb = luaskb_check(L, 1);
	lunatik_object_t *data = lskb->data;
	struct sk_buff *skb = lskb->skb;
	static const char *const layers[] = {"net", "mac", NULL};
	bool mac = luaL_checkoption(L, 2, "net", layers);

	if (skb_linearize(skb) != 0)
		lunatik_enomem(L);

	void *ptr = skb->data;
	size_t size = skb_headlen(skb);

	if (mac) {
		luaL_argcheck(L, skb_mac_header_was_set(skb), 2, "MAC header not set");
		ptr  += skb_mac_offset(skb);
		size += skb_mac_header_len(skb);
	}

	luadata_reset(data, ptr, 0, size, LUADATA_OPT_NONE);
	lunatik_getregistry(L, data); /* push data */
	return 1;
}

/***
* Expands (skb_put) or shrinks (skb_trim) the skb data area.
* @function resize
* @tparam integer n desired size in bytes
* @raise if insufficient tailroom for expansion
*/
static int luaskb_resize(lua_State *L)
{
	luaskb_t *lskb = luaskb_check(L, 1);
	struct sk_buff *skb = lskb->skb;
	size_t new_size = (size_t)luaL_checkinteger(L, 2);
	size_t cur_size = skb_headlen(skb);

	if (new_size > cur_size) {
		size_t needed = new_size - cur_size;
		luaL_argcheck(L, skb_tailroom(skb) >= needed, 2, "insufficient tailroom");
		skb_put(skb, needed);
	}
	else if (new_size < cur_size)
		skb_trim(skb, new_size);
	return 0;
}

/***
* Recomputes IP and transport-layer (TCP/UDP) checksums.
* @function checksum
*/
static int luaskb_checksum(lua_State *L)
{
	luaskb_t *lskb = luaskb_check(L, 1);
	struct sk_buff *skb = lskb->skb;
	struct iphdr *iph = ip_hdr(skb);
	unsigned int iphlen = ip_hdrlen(skb);

	ip_send_check(iph);

	if (iph->protocol == IPPROTO_UDP) {
		struct udphdr *udph = udp_hdr(skb);
		udph->check = 0;
		udph->check = luaskb_csum(skb, iph, iphlen, IPPROTO_UDP, ntohs(udph->len));
	}
	else if (iph->protocol == IPPROTO_TCP) {
		struct tcphdr *tcph = tcp_hdr(skb);
		tcph->check = 0;
		tcph->check = luaskb_csum(skb, iph, iphlen, IPPROTO_TCP, ntohs(iph->tot_len) - iphlen);
	}
	return 0;
}

static void luaskb_release(void *private)
{
	luaskb_t *lskb = (luaskb_t *)private;
	if (lskb->data)
		luadata_close(lskb->data);
}

static const luaL_Reg luaskb_lib[] = {
	{NULL, NULL}
};

static const luaL_Reg luaskb_mt[] = {
	{"__gc",     lunatik_deleteobject},
	{"__len",    luaskb_len},
	{"ifindex",  luaskb_ifindex},
	{"vlan",     luaskb_vlan},
	{"data",     luaskb_data},
	{"resize",   luaskb_resize},
	{"checksum", luaskb_checksum},
	{NULL, NULL}
};

static const lunatik_class_t luaskb_class = {
	.name    = "skb",
	.methods = luaskb_mt,
	.release = luaskb_release,
	.sleep   = false,
	.shared  = true,
};

lunatik_object_t *luaskb_new(lua_State *L)
{
	lunatik_require(L, "skb");
	lunatik_object_t *object = lunatik_newobject(L, &luaskb_class, sizeof(luaskb_t), false);
	luaskb_t *lskb = (luaskb_t *)object->private;
	lskb->data = luadata_new(L, false);
	lunatik_getobject(lskb->data);
	lunatik_register(L, -1, lskb->data);
	lua_pop(L, 1);
	return object;
}
EXPORT_SYMBOL(luaskb_new);

LUNATIK_NEWLIB(skb, luaskb_lib, &luaskb_class, NULL);

static int __init luaskb_init(void)
{
	return 0;
}

static void __exit luaskb_exit(void)
{
}

module_init(luaskb_init);
module_exit(luaskb_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ringzero.com.br>");
MODULE_AUTHOR("Carlos Carvalho <carloslack@gmail.com>");
MODULE_AUTHOR("Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>");

