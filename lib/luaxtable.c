/*
* SPDX-FileCopyrightText: (c) 2024-2025 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Netfilter Xtables extensions.
* This library allows Lua scripts to define custom Netfilter match and target
* extensions for `iptables`. These extensions can then be used in `iptables`
* rules to implement complex packet filtering and manipulation logic in Lua.
*
* When an `iptables` rule using a Lua-defined extension is encountered, the
* corresponding Lua callback function (`match` or `target`) is executed in the
* kernel.
*
* @module xtable
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/module.h>
#include <linux/version.h>
#include <linux/types.h>
#include <linux/netfilter/x_tables.h>

#include <lua.h>
#include <lauxlib.h>
#include <lunatik.h>

#include "luadata.h"
#include "luarcu.h"
#include "luaxtable.h"
#include "luanetfilter.h"

typedef enum luaxtable_type_e {
	LUAXTABLE_TMATCH,
	LUAXTABLE_TTARGET,
} luaxtable_type_t;

/***
* Represents a registered Xtables match or target extension.
* This is a userdata object returned by `xtable.match()` or `xtable.target()`.
* It encapsulates the kernel structures (`struct xt_match` or `struct xt_target`)
* and the Lunatik runtime information necessary to invoke the Lua callbacks.
* The primary way to interact with this object from Lua is to let it be garbage
* collected, which will unregister the extension from the kernel.
* @type xtable_extension
*/
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

static int luaxtable_docall(lua_State *L, luaxtable_t *xtable, luaxtable_info_t *info, const char *op, int nargs, int nret)
{
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
	lua_pushlstring(L, info->userargs, LUAXTABLE_USERDATA_SIZE); /* userargs */

	if (lua_pcall(L, nargs + 1, nret, 0) != LUA_OK) {
		pr_err("%s error: %s\n", op, lua_tostring(L, -1));
		goto err;
	}
	return 0;
err:
	return -1;
}

static inline lunatik_object_t *luaxtable_getskb(lua_State *L, luaxtable_t *xtable)
{
	if (lunatik_getregistry(L, xtable->skb) != LUA_TUSERDATA)
		return NULL;

	return (lunatik_object_t *)lunatik_toobject(L, -1);
}

static int luaxtable_pushparams(lua_State *L, const struct xt_action_param *par, luaxtable_t *xtable, struct sk_buff *skb, uint8_t opt)
{
	lunatik_object_t *data = luaxtable_getskb(L, xtable);
	if (unlikely(data == NULL || skb_linearize(skb) != 0)) {
		pr_err("could not get skb\n");
		return -1;
	}
        luadata_reset(data, skb->data, skb->len, opt);

	lua_newtable(L);
	lua_pushboolean(L, par->hotdrop);
	lua_setfield(L, -2, "hotdrop");
	lua_pushinteger(L, par->thoff);
	lua_setfield(L, -2, "thoff");
	lua_pushinteger(L, par->fragoff);
	lua_setfield(L, -2, "fragoff");
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(4, 10, 0))
	lua_pushinteger(L, xt_hooknum(par));
#else
	lua_pushinteger(L, par->hooknum);
#endif
	lua_setfield(L, -2, "hooknum");
	lua_pushvalue(L, -1); /* param table */
	lua_insert(L, lua_gettop(L) - 2); /* stack: (...), param, skb, param */
	return 0;
}

#define luaxtable_call(L, op, xtable, skb, par, info, opt)	\
	((luaxtable_pushparams(L, par, xtable, skb, opt) == -1) || (luaxtable_docall(L, xtable, info, op, 2, 1) == -1))

static int luaxtable_domatch(lua_State *L, luaxtable_t *xtable, const struct sk_buff *skb, struct xt_action_param *par, int fallback)
{
	if (luaxtable_call(L, "match", xtable, (struct sk_buff *)skb, par, (luaxtable_info_t *)par->matchinfo, LUADATA_OPT_READONLY) != 0)
		return fallback;

	int ret = lua_toboolean(L, -1);
	lua_getfield(L, -2, "hotdrop");
	par->hotdrop = lua_toboolean(L, -1);
	return ret;
}

static int luaxtable_dotarget(lua_State *L, luaxtable_t *xtable, struct sk_buff *skb, const struct xt_action_param *par, int fallback)
{
	if (luaxtable_call(L, "target", xtable,  skb, par, (luaxtable_info_t *)par->targinfo, LUADATA_OPT_NONE) != 0)
		return fallback;

	int ret = lua_tointeger(L, -1);
	return ret >= 0 && ret <= NF_MAX_VERDICT ? ret : fallback;
}

#define LUAXTABLE_HOOK_CB(hook, huk, U, V, T) 				\
static T luaxtable_##hook(U skb, V par)					\
{									\
	int ret;							\
	const luaxtable_info_t *info = (const luaxtable_info_t *)par->huk##info;	\
	luaxtable_t *xtable = info->data;				\
									\
	lunatik_run(xtable->runtime, luaxtable_do##hook, ret, xtable, skb, par, luaxtable_hooks.hook##_fallback);	\
	return ret;							\
}

#define LUAXTABLE_CHECKER_CB(hook, hk, huk, HOOK)				\
static int luaxtable_##hook##_check(const struct xt_##hk##chk_param *par)	\
{										\
	int ret;								\
	luaxtable_t *xtable;							\
	lunatik_object_t *obj = luarcu_gettable(luaxtable_hooks.hook, par->hook->name, XT_EXTENSION_MAXNAMELEN);	\
	if (obj == NULL) {							\
		pr_err("could not find hook (%s)\n", par->hook->name);		\
		return -EINVAL;							\
	}									\
	xtable = (luaxtable_t *)obj->private;					\
	luaxtable_info_t *info = (luaxtable_info_t *)par->huk##info; 		\
	info->data = xtable;							\
										\
	lunatik_run(xtable->runtime, luaxtable_docall, ret, xtable, info, "checkentry", 0, 1);	\
	return ret != 0 ? -EINVAL : 0;						\
}

#define LUAXTABLE_DESTROYER_CB(hook, hk, huk, HOOK)				\
static void luaxtable_##hook##_destroy(const struct xt_##hk##dtor_param *par)	\
{										\
	int ret;								\
	luaxtable_info_t *info = (luaxtable_info_t *)par->huk##info; 		\
	luaxtable_t *xtable = (luaxtable_t *)info->data;			\
										\
	lunatik_run(xtable->runtime, luaxtable_docall, ret, xtable, info, "destroy", 0, 0);	\
}

LUAXTABLE_HOOK_CB(match, match, const struct  sk_buff *, struct xt_action_param *, bool);
LUAXTABLE_HOOK_CB(target, targ, struct sk_buff *, const struct xt_action_param *, unsigned int);

LUAXTABLE_CHECKER_CB(match, mt, match, LUAXTABLE_TMATCH);
LUAXTABLE_CHECKER_CB(target, tg, targ, LUAXTABLE_TTARGET);

LUAXTABLE_DESTROYER_CB(match, mt, match, LUAXTABLE_TMATCH);
LUAXTABLE_DESTROYER_CB(target, tg, targ, LUAXTABLE_TTARGET);

static void luaxtable_release(void *private);

/***
* Creates and registers a new Xtables match extension.
* The Lua functions provided in `opts` will be called by the kernel
* when `iptables` rules using this match are evaluated.
* @function match
* @tparam table opts A table containing the configuration for the match extension.
*   It **must** include the following fields:
*
*   - `name` (string): The unique name for this match extension (e.g., "myluamatch"). This name is used in `iptables -m <name>`.
*   - `revision` (integer): The revision number of this match extension.
*   - `family` (netfilter.family): The protocol family this match applies to (e.g., `netfilter.family.INET`).
*   - `proto` (socket.ipproto, optional, default: 0): The specific IP protocol this match applies to (e.g., `socket.ipproto.TCP`). Use 0 for any protocol.
*   - `hooks` (integer): A bitmask indicating the Netfilter hooks where this match can be used (e.g., `1 << netfilter.inet_hooks.LOCAL_OUT`). Multiple hooks can be OR'd. Note: `netfilter.netdev_hooks` are not available for legacy Xtables.
*   - `match` (function): The Lua function to be called to evaluate if a packet matches.
*     Its signature is `function(skb, par, userargs) -> boolean`.
*
*     - `skb` (data): A read-only `data` object representing the packet's socket buffer.
*     - `par` (table): A read-only table containing parameters related to the packet and hook:
*       - `hotdrop` (boolean): `true` if an earlier rule already marked the packet for unconditional drop.
*       - `thoff` (integer): Offset to the transport header within the `skb`.
*       - `fragoff` (integer): Fragment offset (0 if not a fragment or is the first fragment).
*       - `hooknum` (integer): The Netfilter hook number (e.g., `NF_INET_LOCAL_OUT`).
*     - `userargs` (string): A string containing any arguments passed to this match from the `iptables` rule command line.
*
*     The function should return `true` if the packet matches, `false` otherwise.
*   - `checkentry` (function): A Lua function called when an `iptables` rule using this match is added or modified.
*     Its signature is `function(userargs)`.

*     - `userargs` (string): The arguments string from the `iptables` rule.

*     This function should validate the `userargs`. If validation fails, it should call `error()`.
*   - `destroy` (function): A Lua function called when an `iptables` rule using this match is deleted.
*     Its signature is `function(userargs)`.
*
*     - `userargs` (string): The arguments string from the `iptables` rule.
*
*     This function can be used for cleanup.
* @treturn xtable_extension A userdata object representing the registered match extension.
*   This object should be kept referenced as long as the extension is needed;
*   when it's garbage collected, the extension is unregistered.
* @raise Error if registration fails (e.g., name conflict, invalid parameters, memory allocation failure).
* @see netfilter.family
* @see socket.ipproto
* @see netfilter.inet_hooks
* @see netfilter.bridge_hooks
* @see netfilter.arp_hooks
* @usage
*   local xtable = require("xtable")
*   local nf = require("netfilter")
*
*   local my_match_opts = {
*     name = "myluamatch",
*     revision = 0,
*     family = nf.family.INET,
*     hooks = (1 << nf.inet_hooks.PREROUTING) | (1 << nf.inet_hooks.INPUT),
*     match = function(skb, par, userargs)
*       print("Matching packet with userargs:", userargs)
*       return skb:getuint8(9) == 6 -- Check if protocol is TCP
*     end,
*     checkentry = function(userargs) print("Checking:", userargs) end,
*     destroy = function(userargs) print("Destroying:", userargs) end
*   }
*   local match_ext = xtable.match(my_match_opts)
*   -- To use in iptables: iptables -A INPUT -m myluamatch --somearg "hello" -j ACCEPT
*/

/***
* Creates and registers a new Xtables target extension.
* The Lua function provided in `opts` will be called by the kernel
* for packets that reach an `iptables` rule using this target.
* @function target
* @tparam table opts A table containing the configuration for the target extension.
*   It **must** include the following fields:
*
*   - `name` (string): The unique name for this target extension (e.g., "MYLUATARGET"). This name is used in `iptables -j <NAME>`.
*   - `revision` (integer): The revision number of this target extension.
*   - `family` (netfilter.family): The protocol family this target applies to (e.g., `netfilter.family.INET`).
*   - `proto` (socket.ipproto, optional, default: 0): The specific IP protocol this target applies to (e.g., `socket.ipproto.UDP`). Use 0 for any protocol.
*   - `hooks` (integer): A bitmask indicating the Netfilter hooks where this target can be used.
*   - `target` (function): The Lua function to be called to process a packet.
*     Its signature is `function(skb, par, userargs) -> netfilter.action_verdict`.
*     - `skb` (data): A read-write `data` object representing the packet's socket buffer. Modifications to this `skb` can alter the packet.
*     - `par` (table): A read-only table containing parameters related to the packet and hook (same structure as for `xtable.match`).
*     - `userargs` (string): A string containing any arguments passed to this target from the `iptables` rule command line.
*
*     The function should return an integer verdict, typically one of the constants from the `netfilter.action` table (e.g., `netfilter.action.DROP`, `netfilter.action.ACCEPT`).
*   - `checkentry` (function): A Lua function called when an `iptables` rule using this target is added or modified. Its signature is `function(userargs)`. (See `xtable.match` for details).
*   - `destroy` (function): A Lua function called when an `iptable`s rule using this target is deleted. Its signature is `function(userargs)`. (See `xtable.match` for details).
* @treturn xtable_extension A userdata object representing the registered target extension.
* @raise Error if registration fails.
* @see netfilter.action
* @usage
*   local my_target_opts = {
*     name = "MYLUATARGET",
*     revision = 0,
*     family = nf.family.INET,
*     hooks = (1 << nf.inet_hooks.FORWARD),
*     target = function(skb, par, userargs)
*       print("Targeting packet with userargs:", userargs)
*       -- Example: Modify TTL (byte at offset 8 in IP header)
*       -- skb:setuint8(8, skb:getuint8(8) - 1)
*       return nf.action.ACCEPT
*     end,
*     checkentry = function(userargs) print("Checking target:", userargs) end,
*     destroy = function(userargs) print("Destroying target:", userargs) end
*   }
*   local target_ext = xtable.target(my_target_opts)
*   -- To use in iptables: iptables -A FORWARD -j MYLUATARGET --someoption "value"
*/
static const luaL_Reg luaxtable_mt[] = {
	{"__gc", lunatik_deleteobject},
	{NULL, NULL}
};

static const lunatik_class_t luaxtable_class = {
	.name = "xtable",
	.methods = luaxtable_mt,
	.release = luaxtable_release,
	.flags = false,
};

static inline lunatik_object_t *luaxtable_new(lua_State *L, int idx, int hook)
{
	luaL_checktype(L, idx, LUA_TTABLE);
	lunatik_object_t *object = lunatik_newobject(L, &luaxtable_class , sizeof(luaxtable_t));
	luaxtable_t *xtable = (luaxtable_t *)object->private;

	xtable->type = hook;
	xtable->runtime = NULL;
	luadata_attach(L, xtable, skb);
	return object;
}

static inline void luaxtable_register(lua_State *L, int idx, luaxtable_t *xtable, lunatik_object_t *object)
{
	lunatik_setruntime(L, xtable, xtable);
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
	lunatik_setstring(L, 1, hook, name, XT_EXTENSION_MAXNAMELEN - 1);	\
	lunatik_setinteger(L, 1, hook, revision);			\
	lunatik_setinteger(L, 1, hook, family);			\
	lunatik_setinteger(L, 1, hook, proto);			\
	lunatik_setinteger(L, 1, hook, hooks);			\
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
		luaL_error(L, "unable to hook: %s\n", hook->name);	\
									\
	if (xt_register_##hook(hook) != 0)				\
		luaL_error(L, "unable to register " #hook);		\
									\
	luaxtable_register(L, 1, xtable, object);			\
	return 1;							\
}

LUAXTABLE_NEWHOOK(match, LUAXTABLE_TMATCH);
LUAXTABLE_NEWHOOK(target, LUAXTABLE_TTARGET);


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

#define luaxtable_inithook(hook)	(luaxtable_hooks.hook = luarcu_newtable(LUARCU_DEFAULT_SIZE, false))
#define luaxtable_puthook(hook)		(lunatik_putobject(luaxtable_hooks.hook))

static int __init luaxtable_init(void)
{
	if (luaxtable_inithook(match) == NULL)
		goto err;
	if (luaxtable_inithook(target) == NULL)
		goto put;
	return 0;
put:
	luaxtable_puthook(match);
err:
	return -ENOMEM;
}

static void __exit luaxtable_exit(void)
{
	luaxtable_puthook(match);
	luaxtable_puthook(target);
}

module_init(luaxtable_init);
module_exit(luaxtable_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>");

