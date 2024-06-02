/*
* Copyright (c) 2024 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
*
* Permission is hereby granted, free of charge, to any person obtaining
* a copy of this software and associated documentation files (the
* "Software"), to deal in the Software without restriction, including
* without limitation the rights to use, copy, modify, merge, publish,
* distribute, sublicense, and/or sell copies of the Software, and to
* permit persons to whom the Software is furnished to do so, subject to
* the following conditions:
*
* The above copyright notice and this permission notice shall be
* included in all copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
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


static int luaxtable_invoke(lua_State *L, luaxtable_t *xtable, struct sk_buff *skb, const char *op, int nret)
{
	int ret = -1;
	int nargs = 0;
	lunatik_object_t *data = NULL;

	if (lunatik_getregistry(L, xtable) != LUA_TTABLE) {
		pr_err("%s: could not find ops table\n", op);
		goto err;
	}

	if (lua_getfield(L, -1, op) != LUA_TFUNCTION) {
		pr_err("%s isn't defined\n", op);
		goto err;
	}

	if (skb != NULL ){
		if (lunatik_getregistry(L, xtable->skb) != LUA_TUSERDATA) {
			pr_err("%s: could not find skb\n", op);
			goto err;
		}

		data = (lunatik_object_t *)lunatik_toobject(L, -1);
		if (skb_is_nonlinear(skb))
			pr_err("fragemented skb found!\n");

		luadata_reset(data, skb->data, skb_headlen(skb));
		nargs = 1;
	}

	if (lua_pcall(L, nargs, nret, 0) != LUA_OK) {
		pr_err("%s error: %s\n", op, lua_tostring(L, -1));
		ret = -ECANCELED;
		goto err;
	}
	if (nret != 0)
		ret = luaL_optinteger(L, -1, 0);

err:
	if (data)
		luadata_clear(data);
	return ret;
}

#define LUAXTABLE_HOOK_CB(T, U, V, hook, huk) 				\
static T luaxtable_##hook(U skb, V par)					\
{									\
	const luaxtable_info_t *info = (const luaxtable_info_t *)par->huk##info;	\
	luaxtable_t *xtable = info->data;				\
	int ret;							\
									\
	/* TODO: handle const type in luadata */			\
	lunatik_run(xtable->runtime, luaxtable_invoke, ret, xtable, (struct sk_buff *)skb, #hook, 1);	\
	return ret < 0 ? luaxtable_hooks.hook##_fallback : ret;			\
}

#define LUAXTABLE_CHECKER_CB(hook, hk, huk, HOOK)					\
static int luaxtable_##hook##_check(const struct xt_##hk##chk_param *par)	\
{										\
	int ret = -EINVAL;							\
										\
	luaxtable_t *xtable;							\
	lunatik_object_t *obj = luarcu_gettable(luaxtable_hooks.hook, par->hook->name, XT_EXTENSION_MAXNAMELEN);	\
	if (obj == NULL) {							\
		pr_err("could not find table for %s\n", par->hook->name);	\
		return -1;							\
	}									\
	xtable = (luaxtable_t *)obj->private;					\
	luaxtable_info_t *info = (luaxtable_info_t *)par->huk##info; 		\
	info->data = xtable;							\
										\
	lunatik_run(xtable->runtime, luaxtable_invoke, ret, xtable, NULL, "checkentry", 1);	\
	return ret;								\
}

#define LUAXTABLE_DESTROYER_CB(hook, hk, huk, HOOK)				\
static void luaxtable_##hook##_destroy(const struct xt_##hk##dtor_param *par)	\
{										\
	int ret;								\
	luaxtable_info_t *info = (luaxtable_info_t *)par->huk##info; 		\
	luaxtable_t *xtable = (luaxtable_t *)info->data;			\
										\
	lunatik_run(xtable->runtime, luaxtable_invoke, ret, xtable, NULL, "destroy", 0);	\
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

static inline void luaxtable_setbuf(lua_State *L, int idx, luaxtable_t *xtable)
{
	lunatik_require(L, data);
	xtable->skb = lunatik_checknull(L, luadata_new(NULL, 0, false));
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
	luaxtable_setbuf(L, idx, xtable);
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

