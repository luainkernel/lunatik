/*
* SPDX-FileCopyrightText: (c) 2024-2025 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Low-level Lua interface to the Linux Kernel Netfilter framework.
* This module allows registering Lua functions as Netfilter hooks to inspect
* and modify network packets.
*
* @module netfilter
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/module.h>
#include <linux/version.h>
#include <linux/netfilter.h>

#include <lua.h>
#include <lauxlib.h>
#include <lunatik.h>

#include "luanetfilter.h"
#include "luadata.h"

/***
* Represents a registered Netfilter hook.
* This is a userdata object returned by `netfilter.register()`. It encapsulates
* the kernel `struct nf_hook_ops` and associated Lunatik runtime information
* necessary to invoke the Lua callback when a packet matches the hook criteria.
* @type netfilter_hook
*/
typedef struct luanetfilter_s {
	lunatik_object_t *runtime;
	lunatik_object_t *skb;
	u32 mark;
	struct nf_hook_ops nfops;
} luanetfilter_t;


static void luanetfilter_release(void *private);

static inline bool luanetfilter_pushcb(lua_State *L, luanetfilter_t *luanf)
{
	if (lunatik_getregistry(L, luanf) != LUA_TTABLE) {
		pr_err("could not find ops table\n");
		return false;
	}

	if (lua_getfield(L, -1, "hook") != LUA_TFUNCTION) {
		pr_err("operation not defined");
		return false;
	}
	return true;
}

static inline lunatik_object_t *luanetfilter_pushskb(lua_State *L, luanetfilter_t *luanf, struct sk_buff *skb)
{
	if (lunatik_getregistry(L, luanf->skb) != LUA_TUSERDATA) {
		pr_err("could not find skb");
		return NULL;
	}

	lunatik_object_t *data = (lunatik_object_t *)lunatik_toobject(L, -1);
	if (unlikely(data == NULL || skb_linearize(skb) != 0)) {
		pr_err("could not get skb\n");
		return NULL;
	}
	return data;
}

static int luanetfilter_hook_cb(lua_State *L, luanetfilter_t *luanf, struct sk_buff *skb)
{
	lunatik_object_t *data;

	if (!luanetfilter_pushcb(L, luanf) || (data = luanetfilter_pushskb(L, luanf, skb)) == NULL)
		return -1;

	if (skb_mac_header_was_set(skb))
		luadata_reset(data, skb_mac_header(skb), skb_headlen(skb) + skb_mac_header_len(skb), LUADATA_OPT_NONE);
	else
		luadata_reset(data, skb->data, skb_headlen(skb), LUADATA_OPT_NONE);

	if (lua_pcall(L, 1, 2, 0) != LUA_OK) {
		pr_err("%s\n", lua_tostring(L, -1));
		return -1;
	}

	if (!lua_isnil(L, -1))
		skb->mark = (u32)lua_tointeger(L, -1);
	return lua_tointeger(L, -2);
}

static inline unsigned int luanetfilter_docall(luanetfilter_t *luanf, struct sk_buff *skb)
{
	int ret;
	int policy = NF_ACCEPT;

	if (unlikely(!luanf || !luanf->runtime)) {
		pr_err("runtime not found\n");
		goto out;
	}

	if (likely(luanf->mark != skb->mark))
		goto out;

	lunatik_run(luanf->runtime, luanetfilter_hook_cb, ret, luanf, skb);
	return (ret < 0 || ret > NF_MAX_VERDICT) ? policy : ret;
out:
	return policy;
}

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(4, 4, 0))
static unsigned int luanetfilter_hook(void *priv, struct sk_buff *skb, const struct nf_hook_state *state)
{
	luanetfilter_t *luanf = (luanetfilter_t *)priv;
	return luanetfilter_docall(luanf, skb);
}
#elif (LINUX_VERSION_CODE >= KERNEL_VERSION(4, 1, 0))
static unsigned int luanetfilter_hook(const struct nf_hook_ops *ops, struct sk_buff *skb, const struct nf_hook_state *state)
{
	luanetfilter_t *luanf = (luanetfilter_t *)ops->priv;
	return luanetfilter_docall(luanf, skb);
}
#else
static unsigned int luanetfilter_hook(const struct nf_hook_ops *ops, struct sk_buff *skb, const struct net_device *in, const struct net_device *out, int (*okfn)(struct sk_buff *))
{
	luanetfilter_t *luanf = (luanetfilter_t *)ops->priv;
	return luanetfilter_docall(luanf, skb);
}
#endif

static const luaL_Reg luanetfilter_mt[] = {
	{"__gc", lunatik_deleteobject},
	{NULL, NULL}
};

static const lunatik_class_t luanetfilter_class = {
	.name = "netfilter",
	.methods = luanetfilter_mt,
	.release = luanetfilter_release,
	.sleep = false,
};

/***
* Registers a Netfilter hook.
* The hook function will be called for packets matching the specified criteria.
* @function register
* @tparam table opts A table containing the options for the Netfilter hook.
*   It should have the following fields:
*
*   - `hook` (function): The Lua function to be called for each packet.
*     It receives a `luadata` object representing the packet buffer (`skb`)
*     and should return an integer verdict (e.g., `netfilter.action.ACCEPT`).
*   - `pf` (integer): The protocol family (e.g., `netfilter.family.INET`).
*   - `hooknum` (integer): The hook number within the protocol family (e.g., `netfilter.inet_hooks.LOCAL_OUT`).
*   - `priority` (integer): The hook priority (e.g., `netfilter.ip_priority.FILTER`).
*   - `mark` (integer, optional): Packet mark to match. If set, the hook is only called for packets with this mark.
* @treturn userdata A handle representing the registered hook. This handle can be garbage collected to unregister the hook.
*/
static int luanetfilter_register(lua_State *L)
{
	luaL_checktype(L, 1, LUA_TTABLE);
	lunatik_object_t *object = lunatik_newobject(L, &luanetfilter_class , sizeof(luanetfilter_t));
	luanetfilter_t *nf = (luanetfilter_t *)object->private;
	luadata_attach(L, nf, skb);
	nf->runtime = NULL;

	struct nf_hook_ops *nfops = &nf->nfops;
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(5, 14, 0))
	nfops->hook_ops_type = NF_HOOK_OP_UNDEFINED;
#endif
	nfops->hook = luanetfilter_hook;
	nfops->dev = NULL;
	nfops->priv = nf;
	lunatik_setinteger(L, 1, nfops, pf);
	lunatik_setinteger(L, 1, nfops, hooknum);
	lunatik_setinteger(L, 1, nfops, priority);
	lunatik_optinteger(L, 1, nf, mark, 0);

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(4, 13, 0))
	if (nf_register_net_hook(&init_net, nfops) != 0)
#else
	if (nf_register_hook(nfops) != 0)
#endif
		luaL_error(L, "failed to register netfilter hook");
	lunatik_setruntime(L, netfilter, nf);
	lunatik_getobject(nf->runtime);
	lunatik_registerobject(L, 1, object);
	return 1;
}

static const luaL_Reg luanetfilter_lib[] = {
	{"register", luanetfilter_register},
	{NULL, NULL},
};

static void luanetfilter_release(void *private)
{
	luanetfilter_t *nf = (luanetfilter_t *)private;
	if (!nf->runtime)
		return;

	nf_unregister_net_hook(&init_net, &nf->nfops);
	lunatik_putobject(nf->runtime);
	nf->runtime = NULL;
}

LUNATIK_NEWLIB(netfilter, luanetfilter_lib, &luanetfilter_class, luanetfilter_flags);

static int __init luanetfilter_init(void)
{
    return 0;
}

static void __exit luanetfilter_exit(void)
{
}

module_init(luanetfilter_init);
module_exit(luanetfilter_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>");

