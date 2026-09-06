/*
* SPDX-FileCopyrightText: (c) 2024-2026 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Lua interface to the Linux Netfilter framework.
* @module netfilter
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/list.h>
#include <linux/netfilter.h>

#include <lunatik.h>

#include "luaskb.h"

typedef struct luanetfilter_hook_s {
	struct hlist_node node;
	lunatik_object_t *runtime;
	struct nf_hook_ops nfops;
	u32 mark;
} luanetfilter_hook_t;

/***
* Registered Netfilter hook. Garbage collecting this object unregisters the hook, or detaches
* the instance from the hook its percpu script shares.
* @type netfilter_hook
*/
typedef struct luanetfilter_s {
	luanetfilter_hook_t *hook;	/* NULL when the percpu object owns the hook */
	lunatik_object_t *runtime;
	lunatik_object_t *skb;
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
	lunatik_object_t *object = lunatik_getregistryobject(L, luanf->skb);

	if (unlikely(object == NULL)) {
		pr_err("couldn't find skb\n");
		return NULL;
	}

	luaskb_reset(object, skb);
	return object;
}

static int luanetfilter_hook_cb(lua_State *L, luanetfilter_hook_t *hook, struct sk_buff *skb)
{
	lunatik_object_t *object = NULL;
	int ret = -1;

	lunatik_object_t *handle = lunatik_getregistryobject(L, hook);
	if (handle == NULL) {
		pr_err("couldn't find hook\n");
		goto out;
	}

	luanetfilter_t *luanf = (luanetfilter_t *)handle->private;
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

static inline unsigned int luanetfilter_docall(luanetfilter_hook_t *hook, struct sk_buff *skb)
{
	int ret;
	int policy = NF_ACCEPT;

	if (likely(hook->mark != skb->mark))
		return policy;

	lunatik_run(hook->runtime, luanetfilter_hook_cb, ret, hook, skb);
	return (ret < 0 || ret > NF_MAX_VERDICT) ? policy : ret;
}

static unsigned int luanetfilter_hook(void *priv, struct sk_buff *skb, const struct nf_hook_state *state)
{
	return luanetfilter_docall((luanetfilter_hook_t *)priv, skb);
}

static luanetfilter_hook_t *luanetfilter_findhook(struct hlist_head *hooks, const luanetfilter_hook_t *spec)
{
	luanetfilter_hook_t *hook;

	hlist_for_each_entry(hook, hooks, node) {
		if (hook->mark == spec->mark && hook->nfops.pf == spec->nfops.pf &&
		    hook->nfops.hooknum == spec->nfops.hooknum && hook->nfops.priority == spec->nfops.priority)
			return hook;
	}
	return NULL;
}

static luanetfilter_hook_t *luanetfilter_newhook(lua_State *L, lunatik_object_t *runtime, const luanetfilter_hook_t *spec)
{
	luanetfilter_hook_t *hook = lunatik_checkalloc(L, sizeof(luanetfilter_hook_t));
	int ret;

	*hook = *spec;
	hook->nfops.priv = hook;
	hook->runtime = runtime;

	if ((ret = nf_register_net_hook(&init_net, &hook->nfops)) != 0) {
		lunatik_free(hook);
		lunatik_throw(L, ret);
	}
	return hook;
}

static void luanetfilter_freehook(luanetfilter_hook_t *hook)
{
	nf_unregister_net_hook(&init_net, &hook->nfops);
	lunatik_free(hook);
}

static void luanetfilter_stophooks(void *private)
{
	luanetfilter_hook_t *hook;
	struct hlist_node *next;

	hlist_for_each_entry_safe(hook, next, (struct hlist_head *)private, node) {
		hlist_del(&hook->node);
		luanetfilter_freehook(hook);
	}
}

static const lunatik_class_t luanetfilter_hooks_class = {
	.name = "netfilter.hooks",
	.release = luanetfilter_stophooks,
};

static void luanetfilter_checkspec(lua_State *L, int ix, luanetfilter_hook_t *spec)
{
	luaL_checktype(L, ix, LUA_TTABLE);
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 5, 0)
	spec->nfops.hook_ops_type = NF_HOOK_OP_UNDEFINED;
#endif
	lunatik_setinteger(L, ix, (&spec->nfops), pf);
	lunatik_setinteger(L, ix, (&spec->nfops), hooknum);
	lunatik_setinteger(L, ix, (&spec->nfops), priority);
	lunatik_optinteger(L, ix, spec, mark, 0);
}

static luanetfilter_hook_t *luanetfilter_sharehook(lua_State *L, lunatik_object_t *percpu, const luanetfilter_hook_t *spec)
{
	struct hlist_head *hooks = lunatik_percpudata(L, &luanetfilter_hooks_class, sizeof(struct hlist_head))->private;
	luanetfilter_hook_t *hook = luanetfilter_findhook(hooks, spec);

	if (hook == NULL) {
		hook = luanetfilter_newhook(L, percpu, spec);
		hlist_add_head(&hook->node, hooks);
	}
	else if (lunatik_getregistry(L, hook) != LUA_TNIL)
		luaL_error(L, "hook already registered");
	else
		lua_pop(L, 1);
	return hook;
}

static luanetfilter_hook_t *luanetfilter_ownhook(lua_State *L, luanetfilter_t *nf, const luanetfilter_hook_t *spec)
{
	nf->hook = luanetfilter_newhook(L, nf->runtime, spec);
	lunatik_getobject(nf->runtime); /* a percpu object is held by its data; a plain runtime is held here */
	return nf->hook;
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
* In a percpu script the instances share one hook: the first registration installs it, the
* others attach their callbacks, and a packet reaches the instance of the CPU it arrived on.
* @function register
* @tparam table opts Hook options: `hook` (function), `pf`, `hooknum`, `priority` (integers),
*   and optionally `mark` (integer, default 0).
* @treturn netfilter_hook Registered hook handle.
* @raise if the hook cannot be registered; in a percpu script, if this instance already
*   registered the same `pf`, `hooknum`, `priority` and `mark`, or if called after module load
*/
static int luanetfilter_register(lua_State *L)
{
	luanetfilter_hook_t spec = {.nfops = {.hook = luanetfilter_hook}};
	luanetfilter_checkspec(L, 1, &spec);
	lunatik_object_t *runtime = lunatik_checkruntime(L, luanetfilter_class.opt);
	lunatik_object_t *percpu = lunatik_getpercpu(L);

	lunatik_object_t *object = lunatik_newobject(L, &luanetfilter_class, sizeof(luanetfilter_t), LUNATIK_OPT_NONE);
	luanetfilter_t *nf = (luanetfilter_t *)object->private;
	nf->runtime = runtime;

	luanetfilter_hook_t *hook = percpu != NULL ? luanetfilter_sharehook(L, percpu, &spec) : luanetfilter_ownhook(L, nf, &spec);
	luaskb_attach(L, nf, skb);
	lunatik_registerobject(L, 1, object);
	lunatik_register(L, -1, hook); /* the callback finds this instance's registration by the hook they share */
	return 1;
}

static const luaL_Reg luanetfilter_lib[] = {
	{"register", luanetfilter_register},
	{NULL, NULL},
};

static void luanetfilter_release(void *private)
{
	luanetfilter_t *nf = (luanetfilter_t *)private;

	if (nf->hook != NULL) {
		luanetfilter_freehook(nf->hook);
		lunatik_putobject(nf->runtime);
	}
	lunatik_detach(nf->runtime, nf, skb);
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

