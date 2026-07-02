/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Generic netlink multicast channel.
* Exposes `netlink.channel`, a generic netlink family with one multicast group
* whose `broadcast` is safe from softirq (netfilter hooks, XDP), for
* kernel-to-userspace telemetry. Request/response netlink (rtnetlink, generic
* netlink) is done in Lua over the `socket` module; only this softirq-capable
* multicast path needs a dedicated kernel object.
*
* @module netlink
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/skbuff.h>
#include <net/netlink.h>
#include <net/genetlink.h>

#include <lunatik.h>

/* generic netlink command and attribute used by netlink.channel broadcasts */
#define LUANETLINK_CMD		1
#define LUANETLINK_PAYLOAD	1

typedef struct luanetlink_channel_s {
	struct genl_family          family;
	struct genl_multicast_group mcgrp;
	bool                        registered;
} luanetlink_channel_t;

LUNATIK_PRIVATECHECKER(luanetlink_channel_check, luanetlink_channel_t *);

static void luanetlink_channel_release(void *private)
{
	luanetlink_channel_t *ch = (luanetlink_channel_t *)private;

	if (ch->registered)
		genl_unregister_family(&ch->family);
}

/***
* A generic netlink multicast channel.
* Returned by `netlink.channel()`. Backed by a generic netlink family with one
* multicast group; `broadcast` is safe from softirq (netfilter hooks, XDP) and
* delivers to userspace subscribers of the family's group.
* @type netlink.channel
*/

/***
* Broadcasts a message to all userspace subscribers of the channel's group.
* Safe to call from softirq. Silently ignores the case where no userspace
* process is subscribed (`-ESRCH`).
* @function broadcast
* @tparam string data Raw payload bytes.
* @raise on an oversized payload or an allocation or send error (other than
*   no subscribers).
*/
static int luanetlink_broadcast(lua_State *L)
{
	luanetlink_channel_t *ch = luanetlink_channel_check(L, 1);
	size_t len;
	const char *data = luaL_checklstring(L, 2, &len);

	/* nla_len is a u16 and __nla_reserve() doesn't bound-check it */
	luaL_argcheck(L, len <= U16_MAX - NLA_HDRLEN, 2, "message too large");

	struct sk_buff *skb = genlmsg_new(nla_total_size(len), GFP_ATOMIC);

	if (!skb)
		return lunatik_enomem(L);

	void *hdr = genlmsg_put(skb, 0, 0, &ch->family, 0, LUANETLINK_CMD);
	if (!hdr || nla_put(skb, LUANETLINK_PAYLOAD, (int)len, data) != 0) {
		nlmsg_free(skb);
		lunatik_throw(L, -EMSGSIZE);
	}
	genlmsg_end(skb, hdr);

	int ret = genlmsg_multicast(&ch->family, skb, 0, 0, GFP_ATOMIC);
	if (ret < 0 && ret != -ESRCH)
		lunatik_throw(L, ret);
	return 0;
}

static const luaL_Reg luanetlink_channel_mt[] = {
	{"__gc",      lunatik_deleteobject},
	{"broadcast", luanetlink_broadcast},
	{NULL, NULL}
};

LUNATIK_OPENER(netlink);

static const lunatik_class_t luanetlink_channel_class = {
	.name    = "netlink.channel",
	.methods = luanetlink_channel_mt,
	.release = luanetlink_channel_release,
	.opener  = luaopen_netlink,
	.opt     = LUNATIK_OPT_SOFTIRQ | LUNATIK_OPT_SINGLE,
};

/***
* Creates a generic netlink multicast channel.
* Registers a generic netlink family `name` with a single multicast group (also
* named `name`); userspace resolves the family by name (e.g. via `netlink.genl`)
* to learn the group it must join. Like a netfilter hook, it must be created at
* script load (process context); the returned channel lives for the runtime and
* its `broadcast` may then be called from softirq.
* @function channel
* @tparam string name Generic netlink family name (up to `GENL_NAMSIZ-1` bytes).
* @treturn netlink.channel A new channel object.
* @raise if the name is empty or too long, or family registration fails.
*/
static int luanetlink_channel_new(lua_State *L)
{
	size_t len;
	const char *name = luaL_checklstring(L, 1, &len);
	luaL_argcheck(L, len > 0 && len < GENL_NAMSIZ, 1, "invalid family name length");
	lunatik_object_t *object = lunatik_newobject(L, &luanetlink_channel_class,
		sizeof(luanetlink_channel_t), LUNATIK_OPT_NONE);
	luanetlink_channel_t *ch = (luanetlink_channel_t *)object->private;

	memcpy(ch->family.name, name, len + 1);
	memcpy(ch->mcgrp.name, name, len + 1);
	ch->family.version  = 1;
	ch->family.module   = THIS_MODULE;
	ch->family.mcgrps   = &ch->mcgrp;
	ch->family.n_mcgrps = 1;

	lunatik_try(L, genl_register_family, &ch->family);
	ch->registered = true;

	lunatik_register(L, -1, object); /* pin: release sleeps, must run at teardown */
	return 1; /* object */
}

static const luaL_Reg luanetlink_lib[] = {
	{"channel", luanetlink_channel_new},
	{NULL, NULL}
};

LUNATIK_CLASSES(netlink, &luanetlink_channel_class);
LUNATIK_NEWLIB(netlink, luanetlink_lib, luanetlink_classes);

static int __init luanetlink_init(void)
{
	return 0;
}

static void __exit luanetlink_exit(void)
{
}

module_init(luanetlink_init);
module_exit(luanetlink_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ringzero.com.br>");

