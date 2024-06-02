/*
* SPDX-FileCopyrightText: (c) 2024 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/module.h>
#include <linux/version.h>
#include <linux/types.h>
#include <linux/netfilter.h>
#include <linux/netfilter/x_tables.h>

#include <lua.h>
#include <lauxlib.h>
#include <lunatik.h>

#include "luadata.h"
#include "luarcu.h"
#include "luaxtable.h"

typedef enum luaxtable_type_e {
	LUAXTABLE_TMATCH,
	LUAXTABLE_TTARGET,
} luaxtable_type_t;

typedef struct luaxtable_s {
	lunatik_object_t *runtime;
	lunatik_object_t *skb;
	union {
		struct xt_match match;
		struct xt_target target;
	};
	luaxtable_type_t type;
} luaxtable_t;

static struct {
	lunatik_object_t *target;
	lunatik_object_t *match;
	bool match_fallback;
	unsigned int target_fallback;
} luaxtable_hooks = {NULL, NULL, false, XT_CONTINUE};

static int luaxtable_invoke(lua_State *L, luaxtable_t *xtable, const char *op, int nargs, int nret, int fallback)
{
	int ret = -1;
	int base = lua_gettop(L) - nargs;

	if (lunatik_getregistry(L, xtable) != LUA_TTABLE) {
		pr_err("%s: could not find ops table\n", op);
		goto err;
	}

	if (lua_getfield(L, -1, op) != LUA_TFUNCTION) {
		pr_err("%s isn't defined\n", op);
		goto err;
	}

	lua_insert(L, base + 1); /* op */
	lua_pop(L, 1); /* table */

	if (lua_pcall(L, nargs, nret, 0) != LUA_OK) {
		pr_err("%s error: %s\n", op, lua_tostring(L, -1));
		goto err;
	}
	if (nret == 1) {
		ret = luaL_optinteger(L, -1, 0);
		ret = ret < 0 ? fallback : ret;
	}
err:
	return ret;
}

static lunatik_object_t *luaxtable_getskb(lua_State *L, luaxtable_t *xtable)
{
	if (lunatik_getregistry(L, xtable->skb) != LUA_TUSERDATA)
		return NULL;

	return (lunatik_object_t *)lunatik_toobject(L, -1);
}

static int luaxtable_domatch(lua_State *L, luaxtable_t *xtable, const struct sk_buff *skb, struct xt_action_param *par)
{
	lunatik_object_t *data = luaxtable_getskb(L, xtable);
	if (data == NULL) {
		pr_err("could not find skb\n");
		return luaxtable_hooks.match_fallback;
	}

	luadata_reset(data, skb->data, skb_headlen(skb), LUADATA_OPT_READONLY);
	return luaxtable_invoke(L, xtable, "match", 1, 1, luaxtable_hooks.match_fallback);
}

static int luaxtable_dotarget(lua_State *L, luaxtable_t *xtable, struct sk_buff *skb, const struct xt_action_param *par)
{
	lunatik_object_t *data = luaxtable_getskb(L, xtable);
	if (data == NULL) {
		pr_err("could not find skb\n");
		return luaxtable_hooks.target_fallback;
	}

	luadata_reset(data, skb->data, skb_headlen(skb), LUADATA_OPT_KEEP);
	return luaxtable_invoke(L, xtable, "target", 1, 1, luaxtable_hooks.target_fallback);
}

#define LUAXTABLE_HOOK_CB(T, U, V, hook, huk) 				\
static T luaxtable_##hook(U skb, V par)					\
{									\
	int ret;							\
	const luaxtable_info_t *info = (const luaxtable_info_t *)par->huk##info;	\
	luaxtable_t *xtable = info->data;				\
									\
	lunatik_run(xtable->runtime, luaxtable_do##hook, ret, xtable, skb, par);	\
	return ret;							\
}

#define LUAXTABLE_CHECKER_CB(hook, hk, huk, HOOK)				\
static int luaxtable_##hook##_check(const struct xt_##hk##chk_param *par)	\
{										\
	int ret;								\
	luaxtable_t *xtable;							\
	lunatik_object_t *obj = luarcu_gettable(luaxtable_hooks.hook, par->hook->name, XT_EXTENSION_MAXNAMELEN);	\
	if (obj == NULL) {							\
		pr_err("could not find table for %s\n", par->hook->name);	\
		return -EINVAL;							\
	}									\
	xtable = (luaxtable_t *)obj->private;					\
	luaxtable_info_t *info = (luaxtable_info_t *)par->huk##info; 		\
	info->data = xtable;							\
										\
	lunatik_run(xtable->runtime, luaxtable_invoke, ret, xtable, "checkentry", 0, 1, -EINVAL);	\
	return ret;								\
}

#define LUAXTABLE_DESTROYER_CB(hook, hk, huk, HOOK)				\
static void luaxtable_##hook##_destroy(const struct xt_##hk##dtor_param *par)	\
{										\
	int ret;								\
	luaxtable_info_t *info = (luaxtable_info_t *)par->huk##info; 		\
	luaxtable_t *xtable = (luaxtable_t *)info->data;			\
										\
	lunatik_run(xtable->runtime, luaxtable_invoke, ret, xtable, "destroy", 0, 0, 0);	\
}

LUAXTABLE_HOOK_CB(bool, const struct  sk_buff *, struct xt_action_param *, match, match);
LUAXTABLE_HOOK_CB(unsigned int, struct sk_buff *, const struct xt_action_param *, target, targ);

LUAXTABLE_CHECKER_CB(match, mt, match, LUAXTABLE_TMATCH);
LUAXTABLE_CHECKER_CB(target, tg, targ, LUAXTABLE_TTARGET);

LUAXTABLE_DESTROYER_CB(match, mt, match, LUAXTABLE_TMATCH);
LUAXTABLE_DESTROYER_CB(target, tg, targ, LUAXTABLE_TTARGET);

static void luaxtable_release(void *private);

static const luaL_Reg luaxtable_mt[] = {
	{"__gc", lunatik_deleteobject},
	{NULL, NULL}
};

static const lunatik_class_t luaxtable_class = {
	.name = "xtable",
	.methods = luaxtable_mt,
	.release = luaxtable_release,
	.sleep = false,
};

static inline void luaxtable_setbuffer(lua_State *L, int idx, luaxtable_t *xtable)
{
	lunatik_require(L, data);
	xtable->skb = lunatik_checknull(L, luadata_new(NULL, 0, false, LUADATA_OPT_NONE));
	lunatik_cloneobject(L, xtable->skb);
	lunatik_setregistry(L, -1, xtable->skb);
	lua_pop(L, 1);
}

#define luaxtable_setinteger(L, idx, hook, field) 		\
do {								\
	lunatik_checkfield(L, idx, #field, LUA_TNUMBER);	\
	hook->field = lua_tointeger(L, -1);			\
	lua_pop(L, 1);						\
} while (0)

#define luaxtable_setstring(L, idx, hook, field, maxlen)        \
do {								\
	size_t len;						\
	lunatik_checkfield(L, idx, #field, LUA_TSTRING);	\
	const char *str = lua_tolstring(L, -1, &len);			\
	if (len > maxlen)					\
		luaL_error(L, "'%s' is too long", #field);	\
	strncpy((char *)hook->field, str, maxlen);		\
	lua_pop(L, 1);						\
} while (0)

static inline lunatik_object_t *luaxtable_new(lua_State *L, int idx, int hook)
{
	luaL_checktype(L, idx, LUA_TTABLE);
	lunatik_object_t *object = lunatik_newobject(L, &luaxtable_class , sizeof(luaxtable_t));
	luaxtable_t *xtable = (luaxtable_t *)object->private;

	xtable->type = hook;
	xtable->runtime = NULL;
	luaxtable_setbuffer(L, idx, xtable);
	return object;
}

static inline void luaxtable_register(lua_State *L, int idx, luaxtable_t *xtable, lunatik_object_t *object)
{
	xtable->runtime = lunatik_toruntime(L);
	lunatik_getobject(xtable->runtime);
	lunatik_registerobject(L, idx, object);
}

#define LUAXTABLE_NEWHOOK(hook, HOOK)					\
static int luaxtable_new##hook(lua_State *L) 				\
{									\
	lunatik_object_t *object = luaxtable_new(L, 1, HOOK); 		\
	luaxtable_t *xtable = (luaxtable_t *)object->private;		\
									\
	struct xt_##hook *hook = &xtable->hook;				\
	hook->me = THIS_MODULE;						\
									\
	luaxtable_setstring(L, 1, hook, name, XT_EXTENSION_MAXNAMELEN - 1);	\
	luaxtable_setinteger(L, 1, hook, revision);			\
	luaxtable_setinteger(L, 1, hook, family);			\
	luaxtable_setinteger(L, 1, hook, proto);			\
	lunatik_checkfield(L, 1, "checkentry", LUA_TFUNCTION);		\
	lunatik_checkfield(L, 1, "destroy", LUA_TFUNCTION);		\
	lunatik_checkfield(L, 1, #hook, LUA_TFUNCTION);			\
									\
	hook->usersize = 0;						\
	hook->hook##size = sizeof(luaxtable_info_t);			\
	hook->hook = luaxtable_##hook;					\
	hook->checkentry = luaxtable_##hook##_check;			\
	hook->destroy = luaxtable_##hook##_destroy;			\
									\
	if (luarcu_settable(luaxtable_hooks.hook, hook->name, XT_EXTENSION_MAXNAMELEN, object) != 0)	\
		luaL_error(L, "unable to set key : %s\n", hook->name);	\
									\
	if (xt_register_##hook(hook) != 0)				\
		luaL_error(L, "unable to register " #hook);		\
									\
	luaxtable_register(L, 1, xtable, object);			\
	return 1;							\
}

LUAXTABLE_NEWHOOK(match, LUAXTABLE_TMATCH);
LUAXTABLE_NEWHOOK(target, LUAXTABLE_TTARGET);

static const lunatik_reg_t luanetfilter_family[] = {
	{"UNSPEC", NFPROTO_UNSPEC},
	{"INET", NFPROTO_INET},
	{"IPV4", NFPROTO_IPV4},
	{"IPV6", NFPROTO_IPV6},
	{"ARP", NFPROTO_ARP},
	{"NETDEV", NFPROTO_NETDEV},
	{"BRIDGE", NFPROTO_BRIDGE},
	{NULL, 0}
};

static const lunatik_reg_t luanetfilter_action[] = {
	{"DROP", NF_DROP},
	{"ACCEPT", NF_ACCEPT},
	{"STOLEN", NF_STOLEN},
	{"QUEUE", NF_QUEUE},
	{"REPEAT", NF_REPEAT},
	{"STOP", NF_STOP},
	{"CONTINUE", XT_CONTINUE},
	{"RETURN", XT_RETURN},
	{NULL, 0}
};

static const lunatik_namespace_t luanetfilter_flags[] = {
	{"action", luanetfilter_action},
	{"family", luanetfilter_family},
	{NULL, NULL}
};

static const luaL_Reg luaxtable_lib[] = {
	{"match", luaxtable_newmatch},
	{"target", luaxtable_newtarget},
	{NULL, NULL}
};

static void luaxtable_release(void *private)
{
	luaxtable_t *xtable = (luaxtable_t *)private;
	if (!xtable->runtime) 
		return;

	switch (xtable->type) {
	case LUAXTABLE_TMATCH:
		xt_unregister_match(&xtable->match);
		break;
	case LUAXTABLE_TTARGET:
		xt_unregister_target(&xtable->target);
		break;
	}

	lunatik_putobject(xtable->runtime);
	xtable->runtime = NULL;
}

LUNATIK_NEWLIB(xtable, luaxtable_lib, &luaxtable_class, luanetfilter_flags);

static int __init luaxtable_init(void)
{
	luaxtable_hooks.match = luarcu_newtable(LUARCU_DEFAULT_SIZE, false);
	luaxtable_hooks.target = luarcu_newtable(LUARCU_DEFAULT_SIZE, false);
	return 0;
}

static void __exit luaxtable_exit(void)
{
	lunatik_putobject(luaxtable_hooks.match);
	lunatik_putobject(luaxtable_hooks.target);
}

module_init(luaxtable_init);
module_exit(luaxtable_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>");

