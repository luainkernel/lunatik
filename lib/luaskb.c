/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Socket buffer (skb) interface.
* Provides access to Linux socket buffer fields and operations from Lua.
* @module skb
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/skbuff.h>
#include <linux/if_vlan.h>
#include <linux/netdevice.h>
#include <linux/tcp.h>
#include <linux/udp.h>
#include <net/ip.h>

#include "luadata.h"
#include "luaskb.h"

LUNATIK_PRIVATECHECKER(luaskb_check, luaskb_t *,
	luaL_argcheck(L, private->skb != NULL, ix, "skb is not set");
);

#define luaskb_pushoptinteger(L, cond, val)	\
	((cond) ? lua_pushinteger(L, val) : lua_pushnil(L))

static inline __sum16 luaskb_checksum(struct sk_buff *skb, struct iphdr *iph,
	unsigned int iphlen, __u8 proto, unsigned int len)
{
	return csum_tcpudp_magic(iph->saddr, iph->daddr, len, proto,
		skb_checksum(skb, iphlen, len, 0));
}

/***
* Returns the length of the skb data.
* This is the Lua __len metamethod, allowing use of the # operator.
* @function __len
* @treturn integer Length in bytes.
*/
static int luaskb_len(lua_State *L)
{
	luaskb_t *lskb = luaskb_check(L, 1);
	lua_pushinteger(L, lskb->skb->len);
	return 1;
}

/***
* Returns the network interface index.
* @function ifindex
* @treturn integer Interface index, or nil if not available.
*/
static int luaskb_ifindex(lua_State *L)
{
	luaskb_t *lskb = luaskb_check(L, 1);
	struct net_device *dev = lskb->skb->dev;
	luaskb_pushoptinteger(L, dev, dev->ifindex);
	return 1;
}

/***
* Returns the VLAN tag ID if present.
* @function vlan
* @treturn integer VLAN ID, or nil if no VLAN tag.
*/
static int luaskb_vlan(lua_State *L)
{
	luaskb_t *lskb = luaskb_check(L, 1);
	struct sk_buff *skb = lskb->skb;
	luaskb_pushoptinteger(L, skb_vlan_tag_present(skb), skb_vlan_tag_get_id(skb));
	return 1;
}

/***
* Exports the skb buffer as a data object for direct manipulation.
* With no argument, starts at the network layer (L3).
* With "mac", includes the MAC header (L2).
* @function data
* @tparam[opt] string layer Pass "mac" to include the L2 MAC header.
* @treturn data A data object pointing into the skb buffer.
* @raise Error if skb linearization fails, MAC header is not set, or layer is invalid.
*/
static int luaskb_data(lua_State *L)
{
	luaskb_t *lskb = luaskb_check(L, 1);
	lunatik_object_t *data = lskb->data;
	struct sk_buff *skb = lskb->skb;
	static const char *const layers[] = {"", "mac", NULL};
	bool mac = luaL_checkoption(L, 2, "", layers);

	luaL_argcheck(L, skb_linearize(skb) == 0, 1, "skb linearize failed");

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
* Resizes the skb data area.
* Expands via skb_put() or shrinks via skb_trim().
* @function resize
* @tparam integer new_size Desired size in bytes.
* @raise Error if insufficient tailroom for expansion.
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
* Recomputes IP, TCP, and UDP checksums for the skb.
* Recalculates the IP header checksum unconditionally. If the protocol
* is TCP or UDP, also recalculates the transport-layer checksum using
* the pseudo-header (addresses, length, protocol).
* @function checksum
*/
static int luaskb_rechecksum(lua_State *L)
{
	luaskb_t *lskb = luaskb_check(L, 1);
	struct sk_buff *skb = lskb->skb;
	struct iphdr *iph = ip_hdr(skb);
	unsigned int iphlen = ip_hdrlen(skb);

	ip_send_check(iph);

	if (iph->protocol == IPPROTO_UDP) {
		struct udphdr *udph = udp_hdr(skb);
		udph->check = 0;
		udph->check = luaskb_checksum(skb, iph, iphlen, IPPROTO_UDP, ntohs(udph->len));
	}
	else if (iph->protocol == IPPROTO_TCP) {
		struct tcphdr *tcph = tcp_hdr(skb);
		tcph->check = 0;
		tcph->check = luaskb_checksum(skb, iph, iphlen, IPPROTO_TCP, ntohs(iph->tot_len) - iphlen);
	}
	return 0;
}

/***
* Forwards the skb out through its ingress device.
* Clones the skb, rewinds the data pointer to the MAC header, and calls
* dev_queue_xmit(). The caller should return DROP for the original skb.
* @function forward
* @raise Error if skb has no device, MAC header is not set, or clone fails.
*/
static int luaskb_forward(lua_State *L)
{
	luaskb_t *lskb = luaskb_check(L, 1);
	struct sk_buff *skb = lskb->skb;
	struct net_device *dev = skb->dev;

	luaL_argcheck(L, dev != NULL, 1, "skb has no device");
	luaL_argcheck(L, skb_mac_header_was_set(skb), 1, "MAC header not set");

	struct sk_buff *nskb = skb_clone(skb, GFP_ATOMIC);
	luaL_argcheck(L, nskb != NULL, 1, "skb clone failed");

	skb_push(nskb, nskb->data - skb_mac_header(nskb));
	dev_queue_xmit(nskb);
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
	{"__gc",    lunatik_deleteobject},
	{"__len",   luaskb_len},
	{"ifindex", luaskb_ifindex},
	{"vlan",    luaskb_vlan},
	{"data",    luaskb_data},
	{"resize",   luaskb_resize},
	{"checksum", luaskb_rechecksum},
	{"forward",  luaskb_forward},
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

