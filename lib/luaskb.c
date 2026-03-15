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
#include <net/ip6_checksum.h>

#include "luaskb.h"

LUNATIK_PRIVATECHECKER(luaskb_check, luaskb_t *,
	luaL_argcheck(L, private->skb != NULL, ix, "skb is not set");
);

#define luaskb_pushoptinteger(L, cond, val)	\
	((cond) ? lua_pushinteger(L, val) : lua_pushnil(L))

/* FRAGLIST GSO skbs hold segments in frag_list; skb_copy refuses to copy
 * them (ambiguous semantics: copy the container or the segments?). */
#define luaskb_checkfraglist(L, lskb, ix)				\
	luaL_argcheck(L, !(skb_shinfo((lskb)->skb)->gso_type &		\
		SKB_GSO_FRAGLIST), (ix), "FRAGLIST GSO skbs cannot be copied")

#define luaskb_csum4(skb, iph, iphlen)					\
	csum_tcpudp_magic((iph)->saddr, (iph)->daddr,			\
		ntohs((iph)->tot_len) - (iphlen), (iph)->protocol,	\
		skb_checksum((skb), (iphlen),				\
			ntohs((iph)->tot_len) - (iphlen), 0))

#define luaskb_csum6(skb, ip6h)						\
	csum_ipv6_magic(&(ip6h)->saddr, &(ip6h)->daddr,			\
		ntohs((ip6h)->payload_len), (ip6h)->nexthdr,		\
		skb_checksum((skb), skb_transport_offset(skb),		\
			ntohs((ip6h)->payload_len), 0))

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

#define luaskb_checklinearize(L, lskb, ix)	\
	luaL_argcheck(L, skb_linearize((lskb)->skb) == 0, (ix), "skb linearization failed")

/***
* @function data
* @tparam[opt] string layer "net" (default, L3) or "mac" (L2, includes MAC header)
* @treturn data
* @raise if linearization fails, MAC header is not set, or layer is invalid
*/
static int luaskb_data(lua_State *L)
{
	luaskb_t *lskb = luaskb_check(L, 1);
	luaskb_checklinearize(L, lskb, 1);

	lunatik_object_t *data = lskb->data;
	struct sk_buff *skb = lskb->skb;
	static const char *const layers[] = {"net", "mac", NULL};
	bool mac = luaL_checkoption(L, 2, "net", layers);

	void *ptr = skb->data;
	size_t size = skb_headlen(skb);

	if (mac) {
		luaL_argcheck(L, skb_mac_header_was_set(skb), 2, "MAC header not set");
		ptr  += skb_mac_offset(skb);
		size += skb_mac_header_len(skb);
	}

	if (data)
		lunatik_getregistry(L, data); /* push data */
	else /* copy: allocate on demand; release() has no lua_State to unregister */
		data = luadata_new(L, LUNATIK_OPT_SINGLE); /* push data */
	luadata_reset(data, ptr, size, LUADATA_OPT_NONE);
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

static inline void luaskb_csum(struct sk_buff *skb, u8 proto, __sum16 csum)
{
	if (proto == IPPROTO_UDP)
		udp_hdr(skb)->check = csum;
	else if (proto == IPPROTO_TCP)
		tcp_hdr(skb)->check = csum;
}

/***
* Recomputes IP and transport-layer (TCP/UDP) checksums.
* @function checksum
*/
static int luaskb_checksum(lua_State *L)
{
	luaskb_t *lskb = luaskb_check(L, 1);
	struct sk_buff *skb = lskb->skb;

	if (skb->protocol == htons(ETH_P_IP)) {
		struct iphdr *iph = ip_hdr(skb);
		unsigned int iphlen = ip_hdrlen(skb);
		ip_send_check(iph);
		luaskb_csum(skb, iph->protocol, 0);
		luaskb_csum(skb, iph->protocol, luaskb_csum4(skb, iph, iphlen));
	}
	else if (skb->protocol == htons(ETH_P_IPV6)) {
		struct ipv6hdr *ip6h = ipv6_hdr(skb);
		luaskb_csum(skb, ip6h->nexthdr, 0);
		luaskb_csum(skb, ip6h->nexthdr, luaskb_csum6(skb, ip6h));
	}
	return 0;
}

/***
* Forwards the skb out through its ingress device.
* @function forward
* @raise if skb has no device, MAC header is not set, or clone fails
*/
static int luaskb_forward(lua_State *L)
{
	luaskb_t *lskb = luaskb_check(L, 1);
	struct sk_buff *skb = lskb->skb;
	struct net_device *dev = skb->dev;

	luaL_argcheck(L, dev != NULL, 1, "skb has no device");
	luaL_argcheck(L, skb_mac_header_was_set(skb), 1, "MAC header not set");

	struct sk_buff *nskb = lunatik_checknull(L, skb_clone(skb, GFP_ATOMIC));

	skb_push(nskb, nskb->data - skb_mac_header(nskb));
	dev_queue_xmit(nskb);
	return 0;
}

static int luaskb_copy(lua_State *L);

static void luaskb_release(void *private)
{
	luaskb_t *lskb = (luaskb_t *)private;
	if (lskb->skb)
		kfree_skb(lskb->skb);
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
	{"forward",  luaskb_forward},
	{"copy",     luaskb_copy},
	{NULL, NULL}
};

static const lunatik_class_t luaskb_class = {
	.name    = "skb",
	.methods = luaskb_mt,
	.release = luaskb_release,
	.opt = LUNATIK_OPT_SOFTIRQ | LUNATIK_OPT_SINGLE,
};

/***
* Returns an independent copy of the skb with its own data buffer.
* The skb is linearized before copying to avoid failures on fragmented skbs
* (e.g. bridged traffic with paged data).
* @function copy
* @treturn skb
* @raise if skb is FRAGLIST GSO, linearization fails, or copy allocation fails
*/
static int luaskb_copy(lua_State *L)
{
	luaskb_t *lskb = luaskb_check(L, 1);
	luaskb_checkfraglist(L, lskb, 1);
	luaskb_checklinearize(L, lskb, 1);

	lunatik_object_t *object = lunatik_newobject(L, &luaskb_class, sizeof(luaskb_t), LUNATIK_OPT_NONE);
	luaskb_t *copy = (luaskb_t *)object->private;
	copy->skb = lunatik_checknull(L, skb_copy(lskb->skb, GFP_ATOMIC));
	return 1;
}

lunatik_object_t *luaskb_new(lua_State *L)
{
	lunatik_require(L, "skb");
	lunatik_object_t *object = lunatik_newobject(L, &luaskb_class, sizeof(luaskb_t), LUNATIK_OPT_NONE);
	luaskb_t *lskb = (luaskb_t *)object->private;
	lskb->data = luadata_new(L, LUNATIK_OPT_SINGLE);
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

