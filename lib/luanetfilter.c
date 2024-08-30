/*
* SPDX-FileCopyrightText: (c) 2024 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
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

typedef struct luanetfilter_s {
	lunatik_object_t *runtime;
	lunatik_object_t *skb;
	struct nf_hook_ops nfops;
} luanetfilter_t;

static void luanetfilter_release(void *private);

static int luanetfilter_hook_cb(lua_State *L, luanetfilter_t *luanf, struct sk_buff *skb)
{
	int ret = -1;
	if (lunatik_getregistry(L, luanf) != LUA_TTABLE) {
		pr_err("lunatik hook: could not find ops table\n");
		goto err;
	}

	if (lua_getfield(L, -1, "hook") != LUA_TFUNCTION) {
		pr_err("luanetfilter hook: operation not defined");
		goto err;
	}

	if (lunatik_getregistry(L, luanf->skb) != LUA_TUSERDATA) {
		pr_err("luanetfilter hook: could not find skb");
		goto err;
	}
	lunatik_object_t *data = (lunatik_object_t *)lunatik_toobject(L, -1);
	luadata_reset(data, skb->data, skb_headlen(skb), LUADATA_OPT_NONE);

	if (lua_pcall(L, 1, 1, 0) != LUA_OK) {
		pr_err("luanetfilter hook: pcall error %s\n", lua_tostring(L, -1));
		goto err;
	}
	ret = lua_tointeger(L, -1);
err:
	return ret;
}

static inline unsigned int luanetfilter_docall(luanetfilter_t *luanf, struct sk_buff *skb)
{
	int ret;
	if (!luanf || !luanf->runtime) {
		pr_err("lunatik: netfilter runtime not found\n");
		return NF_ACCEPT;
	}

	lunatik_run(luanf->runtime, luanetfilter_hook_cb, ret, luanf, skb);
	return (ret < 0 || ret > NF_MAX_VERDICT) ? NF_ACCEPT : ret;
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

#define luanetfilter_setinteger(L, idx, hook, field) 		\
do {								\
	lunatik_checkfield(L, idx, #field, LUA_TNUMBER);	\
	hook->field = lua_tointeger(L, -1);			\
	lua_pop(L, 1);						\
} while (0)

static inline void luanetfilter_newbuffer(lua_State *L, int idx, luanetfilter_t *luanf)
{
	lunatik_require(L, data);
	luanf->skb = lunatik_checknull(L, luadata_new(NULL, 0, false, LUADATA_OPT_NONE));
	lunatik_cloneobject(L, luanf->skb);
	lunatik_setregistry(L, -1, luanf->skb);
	lua_pop(L, 1); /* skb */
}

static int luanetfilter_register(lua_State *L)
{
	luaL_checktype(L, 1, LUA_TTABLE);
	lunatik_object_t *object = lunatik_newobject(L, &luanetfilter_class , sizeof(luanetfilter_t));
	luanetfilter_t *nf = (luanetfilter_t *)object->private;
	luanetfilter_newbuffer(L, 1, nf);
	nf->runtime = NULL;

	struct nf_hook_ops *nfops = &nf->nfops;
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(5, 14, 0))
	nfops->hook_ops_type = NF_HOOK_OP_UNDEFINED;
#endif
	nfops->hook = luanetfilter_hook;
	nfops->dev = NULL;
	nfops->priv = nf;
	luanetfilter_setinteger(L, 1, nfops, pf);
	luanetfilter_setinteger(L, 1, nfops, hooknum);
	luanetfilter_setinteger(L, 1, nfops, priority);

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(4, 13, 0))
	if (nf_register_net_hook(&init_net, nfops) != 0)
		luaL_error(L, "failed to register netfilter hook");
#else
	if (nf_register_hook(nfops) != 0)
		luaL_error(L, "failed to register netfilter hook");
#endif
	nf->runtime = lunatik_toruntime(L);
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

