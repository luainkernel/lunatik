/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Linux socket buffer interface.
* @module skb
* @usage
*   -- lunatik run -c softirq <script>: raises the priority of the UDP packets the host sends
*   local netfilter = require("netfilter")
*   local nf        = require("linux.nf")
*
*   local PROTOCOL <const> = 9
*   local UDP <const>      = 17
*   local PRIORITY <const> = 6
*
*   local function prioritize(skb)
*     if skb:data():getuint8(PROTOCOL) == UDP then
*       skb:priority(PRIORITY)
*     end
*     return nf.action.ACCEPT
*   end
*
*   netfilter.register{
*     hook     = prioritize,
*     pf       = nf.proto.IPV4,
*     hooknum  = nf.inet.LOCAL_OUT,
*     priority = nf.ip.pri.FILTER,
*   }
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/skbuff.h>
#include <linux/if_vlan.h>
#include <linux/netdevice.h>
#include <linux/tcp.h>
#include <linux/udp.h>
#include <net/ip.h>
#include <net/ip6_checksum.h>
#if defined(CONFIG_NF_CONNTRACK_MARK)
#include <net/netfilter/nf_conntrack.h>
#endif

#include "luaskb.h"

static const lunatik_class_t luaskb_class;

LUNATIK_PRIVATECHECKER(luaskb_check, luaskb_t *, &luaskb_class,
	luaL_argcheck(L, private->skb != NULL, ix, "skb is not set");
);

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
* Represents a socket buffer (`sk_buff`).
* This is a userdata object handed to the hooks that receive packets; it is
* `SINGLE`, so it cannot be shared with another runtime, and so are the views
* `skb:data()` returns.
*
* A `netfilter` hook callback receives one and `tc_ctx:skb()` returns one, valid only while that
* callback runs: once it returns, every method raises `skb is not set`, and the views that
* `skb:data()` returned are cleared too. `skb:copy()` keeps a packet past the callback.
* @type skb
*/

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
	lunatik_pushoptinteger(L, dev, dev->ifindex);
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
	lunatik_pushoptinteger(L, skb_vlan_tag_present(skb), skb_vlan_tag_get_id(skb));
	return 1;
}

#define luaskb_checklinear(L, lskb, ix)								\
	luaL_argcheck((L), (lskb)->kfunc ? !skb_is_nonlinear((lskb)->skb) : !skb_linearize((lskb)->skb),	\
		(ix), "skb is not linear")

static lunatik_object_t *luaskb_pushview(lua_State *L, lunatik_object_t **view)
{
	if (*view != NULL)
		lunatik_getregistry(L, *view);
	else { /* luaskb_attach, or a copy's first call for the layer */
		lunatik_object_t *object = luadata_new(L, LUNATIK_OPT_SINGLE);
		lunatik_register(L, -1, object);
		lunatik_getobject(object);
		*view = object;
	}
	return *view;
}

#define luaskb_ispresent(skb, start)	((start) != NULL && (start) <= skb_tail_pointer(skb))

static unsigned char *luaskb_start(struct sk_buff *skb, int layer)
{
	switch (layer) {
	case LUASKB_NET:
		return skb_network_header(skb);
	case LUASKB_MAC:
		return skb_mac_header_was_set(skb) ? skb_mac_header(skb) : NULL;
	default:
		return skb->data;
	}
}

/***
* Linearizes the skb and returns a view from where `layer` starts to the end of
* the packet: "net" at the network header and "mac" at the MAC header, or, with no
* `layer`, at `skb->data`, where the packet starts as the hook sees it: the network
* header in an IPv4 or IPv6 netfilter hook and the MAC header in a tc callback. In a
* tc callback the skb is not linearized, and a non-linear one raises.
*
* The skb keeps one view per start: the view with no layer and the "net" and "mac"
* views are three objects, and a second call returns the same view, ending at the
* tail as it is then: a `resize` alone does not move a view's end. The skb stays
* linear once a view is taken, so no later call moves the bytes a view reads. A view
* is valid until the callback that received the skb returns, or, for a copy, until
* the copy is collected: afterwards its length is 0 and every access raises "out of
* bounds".
* @function data
* @tparam[opt] string layer "net" or "mac"
* @treturn data the view, or nil when the layer's header is not set or lies past the tail
* @raise if the skb is not linear, in a tc callback or after a failed linearization, or if
* layer is invalid
*/
static int luaskb_data(lua_State *L)
{
	luaskb_t *lskb = luaskb_check(L, 1);
	luaskb_checklinear(L, lskb, 1);

	struct sk_buff *skb = lskb->skb;
	static const char *const layers[] = {"net", "mac", NULL};
	int layer = lua_isnoneornil(L, 2) ? LUASKB_DATA : luaL_checkoption(L, 2, NULL, layers);
	unsigned char *start = luaskb_start(skb, layer);

	if (luaskb_ispresent(skb, start))
		luadata_reset(luaskb_pushview(L, &lskb->view[layer]), start, skb_tail_pointer(skb) - start,
			LUADATA_OPT_NONE);
	else
		lua_pushnil(L);
	return 1;
}

/***
* Expands (skb_put_zero) or shrinks (skb_trim) the skb data area; the bytes an
* expansion adds read as zeros. The skb is linearized first, so `n` is the
* length of the whole packet, which `#skb` returns afterwards. In a tc callback
* the skb is not linearized, and a non-linear one raises.
* @function resize
* @tparam integer n desired size in bytes, from 0 up to `UINT_MAX`
* @raise if out of bounds, if the skb is not linear, in a tc callback or after a failed
* linearization, or if the tailroom is insufficient for expansion
*/
static int luaskb_resize(lua_State *L)
{
	luaskb_t *lskb = luaskb_check(L, 1);
	struct sk_buff *skb = lskb->skb;
	size_t new_size = (size_t)lunatik_checkinteger(L, 2, 0, UINT_MAX);
	luaskb_checklinear(L, lskb, 1);
	size_t cur_size = skb->len;

	if (new_size > cur_size) {
		size_t needed = new_size - cur_size;
		luaL_argcheck(L, skb_tailroom(skb) >= needed, 2, "insufficient tailroom");
		skb_put_zero(skb, needed);
	}
	else if (new_size < cur_size)
		skb_trim(skb, new_size);
	return 0;
}

#define luaskb_csumend(skb, proto)						\
	(skb_transport_offset(skb) + ((proto) == IPPROTO_TCP ? offsetofend(struct tcphdr, check) :	\
	 (proto) == IPPROTO_UDP ? offsetofend(struct udphdr, check) : 0))
#define luaskb_iswhole4(skb, iph)							\
	((iph)->ihl >= 5 && ntohs((iph)->tot_len) >= ip_hdrlen(skb) &&			\
	 skb_network_offset(skb) + ntohs((iph)->tot_len) <= (skb)->len &&		\
	 luaskb_csumend(skb, (iph)->protocol) <= (skb)->len)
#define luaskb_iswhole6(skb, ip6h)							\
	(skb_transport_offset(skb) + ntohs((ip6h)->payload_len) <= (skb)->len &&	\
	 luaskb_csumend(skb, (ip6h)->nexthdr) <= (skb)->len)

static inline void luaskb_csum(struct sk_buff *skb, u8 proto, __sum16 csum)
{
	if (proto == IPPROTO_UDP)
		udp_hdr(skb)->check = csum;
	else if (proto == IPPROTO_TCP)
		tcp_hdr(skb)->check = csum;
}

/***
* Recomputes IP and transport-layer (TCP/UDP) checksums and writes them into the packet.
* On IPv4 it recomputes the header checksum and the TCP or UDP checksum; on IPv6, the TCP or UDP
* checksum when that header follows the fixed one. A packet that is neither IPv4 nor IPv6, an IPv6
* packet with extension headers, a packet whose IP header gives a length past its end, or on IPv4
* shorter than the header or an IHL below 5, and one too short to hold its TCP or UDP checksum
* field are left unchanged; `resize` does not rewrite that length.
* @function checksum
*/
static int luaskb_checksum(lua_State *L)
{
	luaskb_t *lskb = luaskb_check(L, 1);
	struct sk_buff *skb = lskb->skb;

	if (skb->protocol == htons(ETH_P_IP)) {
		struct iphdr *iph = ip_hdr(skb);
		if (!luaskb_iswhole4(skb, iph))
			return 0;
		ip_send_check(iph);
		luaskb_csum(skb, iph->protocol, 0);
		luaskb_csum(skb, iph->protocol, luaskb_csum4(skb, iph, ip_hdrlen(skb)) ?: CSUM_MANGLED_0);
	}
	else if (skb->protocol == htons(ETH_P_IPV6)) {
		struct ipv6hdr *ip6h = ipv6_hdr(skb);
		if (!luaskb_iswhole6(skb, ip6h))
			return 0;
		luaskb_csum(skb, ip6h->nexthdr, 0);
		luaskb_csum(skb, ip6h->nexthdr, luaskb_csum6(skb, ip6h) ?: CSUM_MANGLED_0);
	}
	return 0;
}

/***
* Transmits a clone of the skb out of `skb->dev`, the device `skb:ifindex()` names.
* The original is untouched and still takes the hook's verdict, so a callback that forwards a
* packet returns `DROP` to not send it twice.
* @function forward
* @raise if skb has no device, MAC header is not set or is past the data, or clone fails
*/
static int luaskb_forward(lua_State *L)
{
	luaskb_t *lskb = luaskb_check(L, 1);
	struct sk_buff *skb = lskb->skb;
	struct net_device *dev = skb->dev;

	luaL_argcheck(L, dev != NULL, 1, "skb has no device");
	luaL_argcheck(L, skb_mac_header_was_set(skb), 1, "MAC header not set");
	luaL_argcheck(L, skb_mac_header(skb) <= skb->data, 1, "MAC header past the data");

	struct sk_buff *nskb = lunatik_checknull(L, skb_clone(skb, GFP_ATOMIC));

	skb_push(nskb, nskb->data - skb_mac_header(nskb));
	dev_queue_xmit(nskb);
	return 0;
}

#if defined(CONFIG_NF_CONNTRACK_MARK)
/***
* Gets or sets the conntrack mark: with no argument reads it, with `value` sets
* it. Returns the current (or new) mark, or nil if no conntrack is associated.
* Present only on a kernel built with `CONFIG_NF_CONNTRACK_MARK`: elsewhere the method is nil,
* and a script that may run there tests `skb.connmark` before calling it.
* @function connmark
* @tparam[opt] integer value 32-bit mark to set, from 0 up to `U32_MAX`
* @treturn integer 32-bit connmark, or nil if no conntrack is associated
* @raise if `value` is out of bounds
*/
static int luaskb_connmark(lua_State *L)
{
	luaskb_t *lskb = luaskb_check(L, 1);
	bool set = !lua_isnone(L, 2);
	u32 value = set ? (u32)lunatik_checkinteger(L, 2, 0, U32_MAX) : 0;
	enum ip_conntrack_info ctinfo;
	struct nf_conn *ct = nf_ct_get(lskb->skb, &ctinfo);

	if (ct && set)
		WRITE_ONCE(ct->mark, value);
	lunatik_pushoptinteger(L, ct, (lua_Integer)(u32)READ_ONCE(ct->mark));
	return 1;
}
#endif /* CONFIG_NF_CONNTRACK_MARK */

#define luaskb_integer(name, field) \
static int luaskb_##name(lua_State *L) \
{ \
	luaskb_t *lskb = luaskb_check(L, 1); \
	struct sk_buff *skb = lskb->skb; \
	if (!lua_isnone(L, 2)) \
		skb->field = (typeof(skb->field))lunatik_checkinteger(L, 2, 0, U32_MAX); \
	lua_pushinteger(L, skb->field); \
	return 1; \
}

/***
* Gets or sets the packet mark: with no argument reads it, with `value` sets it.
* @function mark
* @tparam[opt] integer value the new packet mark, from 0 up to `U32_MAX`
* @treturn integer the packet mark
* @raise if `value` is out of bounds
*/
luaskb_integer(mark, mark);

/***
* Gets or sets the packet priority: with no argument reads it, with `value` sets it.
* @function priority
* @tparam[opt] integer value the new packet priority, from 0 up to `U32_MAX`
* @treturn integer the packet priority
* @raise if `value` is out of bounds
*/
luaskb_integer(priority, priority);

static int luaskb_copy(lua_State *L);

static void luaskb_release(void *private)
{
	luaskb_t *lskb = (luaskb_t *)private;
	lunatik_object_t *view;
	luaskb_foreachview(lskb, layer, view)
		luadata_close(view);
	if (lskb->skb)
		kfree_skb(lskb->skb);
}

static int luaskb_gc(lua_State *L)
{
	luaskb_t *lskb = (luaskb_t *)lunatik_checkobjectclass(L, 1, &luaskb_class)->private;

	lunatik_object_t *view;
	if (lskb != NULL) /* a constructor that raised left no private */
		luaskb_foreachview(lskb, layer, view) {
			luadata_clear(view); /* the release may run on a kernel worker, beside the view's reader */
			lunatik_unregister(L, view);
		}
	return lunatik_deleteobject(L);
}

static const luaL_Reg luaskb_lib[] = {
	{NULL, NULL}
};

static const luaL_Reg luaskb_mt[] = {
	{"__gc",     luaskb_gc},
	{"__len",    luaskb_len},
	{"ifindex",  luaskb_ifindex},
	{"vlan",     luaskb_vlan},
	{"data",     luaskb_data},
	{"resize",   luaskb_resize},
	{"checksum", luaskb_checksum},
	{"forward",  luaskb_forward},
	{"copy",     luaskb_copy},
#if defined(CONFIG_NF_CONNTRACK_MARK)
	{"connmark", luaskb_connmark},
#endif
	{"mark",     luaskb_mark},
	{"priority", luaskb_priority},
	{NULL, NULL}
};

static const lunatik_class_t luaskb_class = {
	.name    = "skb",
	.methods = luaskb_mt,
	.release = luaskb_release,
	.opt = LUNATIK_OPT_SOFTIRQ | LUNATIK_OPT_SINGLE,
	.owner   = THIS_MODULE,
};

/***
* Returns an independent copy of the skb with its own data buffer.
* The skb is linearized before copying to avoid failures on fragmented skbs
* (e.g. bridged traffic with paged data). In a tc callback the skb is not
* linearized, and a non-linear one raises.
* A view of the copy that `data()` returns is valid until the copy is collected,
* and is then cleared as a view of a callback's skb is when the callback returns.
* @function copy
* @treturn skb
* @raise if skb is FRAGLIST GSO, if the skb is not linear, in a tc callback or after a failed
* linearization, or if copy allocation fails
*/
static int luaskb_copy(lua_State *L)
{
	luaskb_t *lskb = luaskb_check(L, 1);
	luaskb_checkfraglist(L, lskb, 1);
	luaskb_checklinear(L, lskb, 1);

	lunatik_object_t *object = lunatik_newobject(L, &luaskb_class, sizeof(luaskb_t), LUNATIK_OPT_NONE);
	luaskb_t *copy = (luaskb_t *)object->private;
	copy->skb = lunatik_checknull(L, skb_copy(lskb->skb, GFP_ATOMIC));
	return 1;
}

lunatik_object_t *luaskb_attach(lua_State *L, bool kfunc)
{
	lunatik_require(L, &luaskb_class);
	lunatik_object_t *object = lunatik_newobject(L, &luaskb_class, sizeof(luaskb_t), LUNATIK_OPT_NONE);
	luaskb_t *lskb = (luaskb_t *)object->private;
	lskb->kfunc = kfunc;
	luaskb_foreachlayer(layer)
		luaskb_pushview(L, &lskb->view[layer]);
	lua_pop(L, LUASKB_VIEWS);
	return object;
}
EXPORT_SYMBOL(luaskb_attach);

LUNATIK_CLASSES(skb, &luaskb_class);
LUNATIK_NEWLIB(skb, luaskb_lib, luaskb_classes);

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
MODULE_VERSION(LUNATIK_RELEASE);
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ringzero.com.br>");
MODULE_AUTHOR("Carlos Carvalho <carloslack@gmail.com>");
MODULE_AUTHOR("Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>");

