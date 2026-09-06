/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Generic netlink channel: a generic netlink family with one multicast group
* whose `multicast`/`unicast` are safe from softirq (netfilter hooks, XDP), for
* kernel-to-userspace delivery. The message body is built in Lua (e.g. with
* `netlink.message`) and sent as-is; request/response netlink is otherwise done
* in Lua over the `socket` module. Only this softirq-capable send path needs a
* dedicated kernel object.
*
* @module netlink.channel
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/skbuff.h>
#include <net/netlink.h>
#include <net/genetlink.h>

#include <lunatik.h>

/* the family's sole multicast group; genl requires a non-empty group name */
#define LUANETLINK_MCGRP	"lunatik"

typedef struct luanetlink_channel_s {
	struct genl_family          family;
	struct genl_multicast_group mcgrp;
	bool                        registered;
} luanetlink_channel_t;

static const lunatik_class_t luanetlink_channel_class;

LUNATIK_PRIVATECHECKER(luanetlink_channel_check, luanetlink_channel_t *, &luanetlink_channel_class);

static void luanetlink_channel_release(void *private)
{
	luanetlink_channel_t *channel = (luanetlink_channel_t *)private;

	if (channel->registered)
		genl_unregister_family(&channel->family);
}

/***
* A generic netlink channel.
* Returned by `netlink.channel()`. Backed by a generic netlink family with one
* multicast group; `multicast` and `unicast` are safe from softirq (netfilter
* hooks, XDP) and deliver to userspace subscribers of the family.
* @type netlink.channel
*/

/* Builds a genl message: a `cmd` header plus the caller's `payload`, trusted
 * to be well-formed attributes framed in Lua. Raises on an allocation error. */
static struct sk_buff *luanetlink_message(lua_State *L, struct genl_family *family,
	int cmd, const char *payload, size_t len, gfp_t gfp)
{
	struct sk_buff *skb = genlmsg_new(len, gfp);
	if (skb == NULL)
		lunatik_enomem(L);

	void *hdr = genlmsg_put(skb, 0, 0, family, 0, cmd);
	if (hdr == NULL) {
		nlmsg_free(skb);
		lunatik_throw(L, -EMSGSIZE);
	}
	if (len != 0)
		skb_put_data(skb, payload, len);
	genlmsg_end(skb, hdr);
	return skb;
}

/***
* Multicasts a message to every subscriber of the channel's group.
* Safe to call from softirq.
* @function multicast
* @tparam integer cmd Generic netlink command.
* @tparam[opt] string payload Message body (e.g. from `netlink.message`).
* @treturn boolean whether it reached at least one subscriber.
* @raise on an allocation error.
*/
static int luanetlink_multicast(lua_State *L)
{
	luanetlink_channel_t *channel = luanetlink_channel_check(L, 1);
	int cmd = (int)luaL_checkinteger(L, 2);
	size_t len;
	const char *payload = luaL_optlstring(L, 3, "", &len);
	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));
	struct sk_buff *skb = luanetlink_message(L, &channel->family, cmd, payload, len, gfp);

	lua_pushboolean(L, genlmsg_multicast(&channel->family, skb, 0, 0, gfp) >= 0);
	return 1;
}

/***
* Unicasts a message to a single userspace subscriber by port id.
* Safe to call from softirq.
* @function unicast
* @tparam integer portid Destination netlink port id.
* @tparam integer cmd Generic netlink command.
* @tparam[opt] string payload Message body (e.g. from `netlink.message`).
* @treturn boolean whether it was queued to the port id (`false` if the port
*   id is gone or its receive buffer is full).
* @raise if `portid` is 0, or on an allocation error.
*/
static int luanetlink_unicast(lua_State *L)
{
	luanetlink_channel_t *channel = luanetlink_channel_check(L, 1);
	u32 portid = (u32)luaL_checkinteger(L, 2);
	int cmd = (int)luaL_checkinteger(L, 3);
	size_t len;
	const char *payload = luaL_optlstring(L, 4, "", &len);
	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));

	luaL_argcheck(L, portid != 0, 2, "invalid port id");
	struct sk_buff *skb = luanetlink_message(L, &channel->family, cmd, payload, len, gfp);

	lua_pushboolean(L, genlmsg_unicast(&init_net, skb, portid) >= 0);
	return 1;
}

static const luaL_Reg luanetlink_channel_mt[] = {
	{"__gc",      lunatik_deleteobject},
	{"multicast", luanetlink_multicast},
	{"unicast",   luanetlink_unicast},
	{NULL, NULL}
};

LUNATIK_OPENER(netlink_channel);

static const lunatik_class_t luanetlink_channel_class = {
	.name    = "netlink.channel",
	.methods = luanetlink_channel_mt,
	.release = luanetlink_channel_release,
	.opener  = luaopen_netlink_channel,
	.opt     = LUNATIK_OPT_SOFTIRQ | LUNATIK_OPT_SINGLE,
};

/***
* Creates a generic netlink channel.
* Registers a generic netlink family `name` with a single multicast group;
* userspace resolves the family by name (e.g. via `netlink.genl`) to learn the
* group it must join. Like a netfilter hook, it must be created at script load
* (process context); the returned channel lives for the runtime and its
* `multicast`/`unicast` may then be called from softirq.
* @function new
* @tparam string name Generic netlink family name (up to `GENL_NAMSIZ-1` bytes).
* @treturn netlink.channel A new channel object.
* @raise if the name is empty or too long, or family registration fails.
* @within netlink.channel
*/
static int luanetlink_channel_new(lua_State *L)
{
	size_t len;
	const char *name = luaL_checklstring(L, 1, &len);
	luaL_argcheck(L, len > 0 && len < GENL_NAMSIZ, 1, "invalid family name length");
	lunatik_object_t *object = lunatik_newobject(L, &luanetlink_channel_class,
		sizeof(luanetlink_channel_t), LUNATIK_OPT_NONE);
	luanetlink_channel_t *channel = (luanetlink_channel_t *)object->private;

	memcpy(channel->family.name, name, len + 1);
	memcpy(channel->mcgrp.name, LUANETLINK_MCGRP, sizeof(LUANETLINK_MCGRP));
	channel->family.version  = 1;
	channel->family.module   = THIS_MODULE;
	channel->family.mcgrps   = &channel->mcgrp;
	channel->family.n_mcgrps = 1;

	lunatik_try(L, genl_register_family, &channel->family);
	channel->registered = true;

	lunatik_register(L, -1, object); /* pin: release sleeps, must run at teardown */
	return 1; /* object */
}

static const luaL_Reg luanetlink_lib[] = {
	{"new", luanetlink_channel_new},
	{NULL, NULL}
};

LUNATIK_CLASSES(netlink_channel, &luanetlink_channel_class);
LUNATIK_NEWLIB(netlink_channel, luanetlink_lib, luanetlink_channel_classes);

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

