/*
* SPDX-FileCopyrightText: (c) 2024-2026 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Lua interface to the Linux Netfilter framework.
* @module netfilter
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/netfilter.h>

#include <lunatik.h>

#include "luaskb.h"

/***
* Registered Netfilter hook. Garbage collecting this object unregisters the hook.
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
		pr_err("couldn't find ops table\n");
		return false;
	}

	if (lua_getfield(L, -1, "hook") != LUA_TFUNCTION) {
		pr_err("operation not defined\n");
		return false;
	}
	return true;
}

static inline lunatik_object_t *luanetfilter_pushskb(lua_State *L, luanetfilter_t *luanf, struct sk_buff *skb)
{
	if (lunatik_getregistry(L, luanf->skb) != LUA_TUSERDATA) {
		pr_err("couldn't find skb\n");
		return NULL;
	}

	lunatik_object_t *object = lunatik_toobject(L, -1);
	if (unlikely(object == NULL)) {
		pr_err("couldn't get skb object\n");
		return NULL;
	}

	luaskb_reset(object, skb);
	return object;
}

static int luanetfilter_hook_cb(lua_State *L, luanetfilter_t *luanf, struct sk_buff *skb)
{
	lunatik_object_t *object = NULL;
	int ret = -1;

	if (!luanetfilter_pushcb(L, luanf) || (object = luanetfilter_pushskb(L, luanf, skb)) == NULL)
		goto out;

	if (lua_pcall(L, 1, 2, 0) != LUA_OK) {
		pr_err("%s\n", lua_tostring(L, -1));
		lua_pop(L, 1);
		goto clear;
	}

	if (!lua_isnil(L, -1))
		skb->mark = (u32)lua_tointeger(L, -1);
	ret = (int)lua_tointeger(L, -2);
clear:
	luaskb_clear(object);
out:
	return ret;
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

static unsigned int luanetfilter_hook(void *priv, struct sk_buff *skb, const struct nf_hook_state *state)
{
	luanetfilter_t *luanf = (luanetfilter_t *)priv;
	return luanetfilter_docall(luanf, skb);
}

static const luaL_Reg luanetfilter_mt[] = {
	{"__gc", lunatik_deleteobject},
	{NULL, NULL}
};

LUNATIK_OPENER(netfilter);
static const lunatik_class_t luanetfilter_class = {
	.name = "netfilter",
	.methods = luanetfilter_mt,
	.release = luanetfilter_release,
	.opener = luaopen_netfilter,
	.opt = LUNATIK_OPT_SOFTIRQ | LUNATIK_OPT_SINGLE,
};

/***
* Registers a Netfilter hook.
* @function register
* @tparam table opts Hook options: `hook` (function), `pf`, `hooknum`, `priority` (integers),
*   and optionally `mark` (integer, default 0).
* @treturn netfilter_hook Registered hook handle.
*/
static int luanetfilter_register(lua_State *L)
{
	luaL_checktype(L, 1, LUA_TTABLE);
	lunatik_object_t *object = lunatik_newobject(L, &luanetfilter_class, sizeof(luanetfilter_t), LUNATIK_OPT_NONE);
	luanetfilter_t *nf = (luanetfilter_t *)object->private;
	nf->runtime = NULL;

	struct nf_hook_ops *nfops = &nf->nfops;
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 5, 0)
	nfops->hook_ops_type = NF_HOOK_OP_UNDEFINED;
#endif
	nfops->hook = luanetfilter_hook;
	nfops->dev = NULL;
	nfops->priv = nf;
	lunatik_setinteger(L, 1, nfops, pf);
	lunatik_setinteger(L, 1, nfops, hooknum);
	lunatik_setinteger(L, 1, nfops, priority);
	lunatik_optinteger(L, 1, nf, mark, 0);

	if (nf_register_net_hook(&init_net, nfops) != 0)
		luaL_error(L, "failed to register netfilter hook");

	lunatik_setruntime(L, netfilter, nf);
	luaskb_attach(L, nf, skb);
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
	lunatik_object_t *runtime = nf->runtime;
	if (runtime == NULL)
		return;

	nf_unregister_net_hook(&init_net, &nf->nfops);
	lunatik_detach(runtime, nf, skb);
	lunatik_putobject(runtime);
	nf->runtime = NULL;
}

LUNATIK_CLASSES(netfilter, &luanetfilter_class);
LUNATIK_NEWLIB(netfilter, luanetfilter_lib, luanetfilter_classes);

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

