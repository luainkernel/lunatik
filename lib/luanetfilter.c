/*
* SPDX-FileCopyrightText: (c) 2024-2026 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Lua interface to the Linux Netfilter framework.
*
* A script that registers hooks runs in a softirq runtime, `lunatik run -c softirq <script>`; see
* [execution contexts](../topics/02-running-scripts.md.html#Execution_contexts). Hooks are
* registered in the initial network namespace only: packets of another namespace do not reach
* them.
*
* @module netfilter
* @usage
*   -- lunatik run -c softirq <script>: drops the locally generated IPv4 packets marked 0x10,
*   -- as `sudo ping -m 16 127.0.0.1` sends them
*   local netfilter = require("netfilter")
*   local nf        = require("linux.nf")
*
*   local MARK <const> = 0x10
*
*   local function drop(skb)
*     return nf.action.DROP
*   end
*
*   netfilter.register{
*     hook     = drop,
*     pf       = nf.proto.IPV4,
*     hooknum  = nf.inet.LOCAL_OUT,
*     priority = nf.ip.pri.FILTER,
*     mark     = MARK,
*   }
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
	bool marked;
} luanetfilter_hook_t;

typedef struct luanetfilter_s {
	luanetfilter_hook_t *hook;	/* NULL when the percpu object owns the hook */
	lunatik_object_t *runtime;
	lunatik_object_t *skb;
} luanetfilter_t;

static void luanetfilter_release(void *private);

static inline bool luanetfilter_pushcb(lua_State *L, luanetfilter_t *luanf)
{
	if (lunatik_getregistry(L, luanf) != LUA_TTABLE)
		return false; /* stopped: the packet takes the policy */

	if (lua_getfield(L, -1, "hook") != LUA_TFUNCTION) {
		pr_err_ratelimited("operation not defined\n");
		return false;
	}
	return true;
}

static inline lunatik_object_t *luanetfilter_pushskb(lua_State *L, luanetfilter_t *luanf, struct sk_buff *skb)
{
	lunatik_object_t *object = lunatik_getregistryobject(L, luanf->skb);

	if (unlikely(object == NULL)) {
		pr_err_ratelimited("couldn't find skb\n");
		return NULL;
	}

	luaskb_reset(object, skb);
	return object;
}

#define luanetfilter_isverdict(v)	((v) == NF_DROP || (v) == NF_ACCEPT || (v) == NF_QUEUE)

static int luanetfilter_hook_cb(lua_State *L, luanetfilter_hook_t *hook, struct sk_buff *skb)
{
	lunatik_object_t *object = NULL;
	int ret = -1;

	lunatik_object_t *handle = lunatik_getregistryobject(L, hook);
	if (handle == NULL) {
		pr_err_ratelimited("couldn't find hook\n");
		goto out;
	}

	luanetfilter_t *luanf = (luanetfilter_t *)handle->private;
	if (!luanetfilter_pushcb(L, luanf) || (object = luanetfilter_pushskb(L, luanf, skb)) == NULL)
		goto out;

	if (lua_pcall(L, 1, 2, 0) != LUA_OK) {
		pr_err_ratelimited("%s\n", lunatik_errmsg(L));
		lua_pop(L, 1);
		goto clear;
	}

	if (!lua_isnil(L, -1))
		skb->mark = (u32)lua_tointeger(L, -1);
	lua_Integer verdict = lua_tointeger(L, -2);
	if (lua_type(L, -2) == LUA_TNUMBER && luanetfilter_isverdict(verdict))
		ret = (int)verdict;
	else if (!lua_isnil(L, -2))
		pr_err_ratelimited("invalid verdict\n");
clear:
	luaskb_clear(object);
out:
	return ret;
}

static inline unsigned int luanetfilter_docall(luanetfilter_hook_t *hook, struct sk_buff *skb)
{
	int ret;
	int policy = NF_ACCEPT;

	if (hook->marked && likely(hook->mark != skb->mark))
		return policy;

	lunatik_run(hook->runtime, luanetfilter_hook_cb, ret, hook, skb);
	return ret < 0 ? policy : ret;
}

static unsigned int luanetfilter_hook(void *priv, struct sk_buff *skb, const struct nf_hook_state *state)
{
	return luanetfilter_docall((luanetfilter_hook_t *)priv, skb);
}

static luanetfilter_hook_t *luanetfilter_find(struct hlist_head *hooks, const luanetfilter_hook_t *spec)
{
	luanetfilter_hook_t *hook;

	hlist_for_each_entry(hook, hooks, node) {
		if (hook->marked == spec->marked && hook->mark == spec->mark && hook->nfops.pf == spec->nfops.pf &&
		    hook->nfops.hooknum == spec->nfops.hooknum && hook->nfops.priority == spec->nfops.priority)
			return hook;
	}
	return NULL;
}

static luanetfilter_hook_t *luanetfilter_register(lua_State *L, lunatik_object_t *runtime, const luanetfilter_hook_t *spec)
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

static void luanetfilter_free(luanetfilter_hook_t *hook)
{
	nf_unregister_net_hook(&init_net, &hook->nfops);
	lunatik_free(hook);
}

LUNATIK_PERCPUDATA(luanetfilter_hooks, "netfilter.hooks", luanetfilter_hook_t, luanetfilter_free);

static void luanetfilter_checkspec(lua_State *L, int ix, luanetfilter_hook_t *spec)
{
	luaL_checktype(L, ix, LUA_TTABLE);
	lunatik_setinteger(L, ix, (&spec->nfops), pf, 0, U8_MAX);
	lunatik_setinteger(L, ix, (&spec->nfops), hooknum, 0, UINT_MAX);
	lunatik_setinteger(L, ix, (&spec->nfops), priority, INT_MIN, INT_MAX);
	spec->marked = lunatik_optfield(L, ix, "mark", LUA_TNUMBER);
	spec->mark = spec->marked ? lunatik_checkfieldinteger(L, "mark", 0, U32_MAX) : 0;
	lua_pop(L, 1);
}

static luanetfilter_hook_t *luanetfilter_share(lua_State *L, lunatik_object_t *percpu, const luanetfilter_hook_t *spec)
{
	struct hlist_head *hooks = lunatik_percpudata(L, &luanetfilter_hooks_class, sizeof(struct hlist_head))->private;
	luanetfilter_hook_t *hook = luanetfilter_find(hooks, spec);

	if (hook == NULL) {
		hook = luanetfilter_register(L, percpu, spec);
		hlist_add_head(&hook->node, hooks);
	}
	else if (lunatik_getregistry(L, hook) != LUA_TNIL)
		luaL_error(L, "hook already registered");
	else
		lua_pop(L, 1);
	return hook;
}

static luanetfilter_hook_t *luanetfilter_own(lua_State *L, luanetfilter_t *nf, const luanetfilter_hook_t *spec)
{
	nf->hook = luanetfilter_register(L, nf->runtime, spec);
	lunatik_getobject(nf->runtime); /* a percpu object is held by its data; a plain runtime is held here */
	return nf->hook;
}

/***
* A registered Netfilter hook.
* Returned by `netfilter.register`.
* @type netfilter_hook
*/

static const lunatik_class_t luanetfilter_class;

LUNATIK_PRIVATECHECKER(luanetfilter_check, luanetfilter_t *, &luanetfilter_class);

/***
* Stops the hook's callback.
* A packet the hook sees afterwards takes the `ACCEPT` policy without reaching Lua. The hook
* stays registered until the runtime closes, since unregistering it sleeps and a stop may come
* from a callback; in a percpu script this stops the callback of this runtime alone. Calling it
* again does nothing, and a to-be-closed variable holding the hook stops it the same way.
* @function stop
* @treturn nil
* @usage hook:stop()
*/
static int luanetfilter_stop(lua_State *L)
{
	lunatik_unregister(L, luanetfilter_check(L, 1)); /* the ops table the callback is read from */
	return 0;
}

static const luaL_Reg luanetfilter_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"__close", luanetfilter_stop},
	{"stop", luanetfilter_stop},
	{NULL, NULL}
};

static const lunatik_class_t luanetfilter_class = {
	.name = "netfilter",
	.methods = luanetfilter_mt,
	.release = luanetfilter_release,
	.opt = LUNATIK_OPT_SOFTIRQ | LUNATIK_OPT_SINGLE,
	.owner = THIS_MODULE,
};

/***
* Registers a Netfilter hook.
* In a percpu script the runtimes share one hook: the first registration installs it, the
* others attach their callbacks, and a packet reaches the runtime of the CPU it arrived on.
* @function register
* @tparam table opts Hook options: `hook` (function), `pf`, `hooknum`, `priority` (integers),
*   and optionally `mark` (integer), a prefilter that keeps a packet out of Lua: given a
*   `mark`, 0 included, only a packet whose `skb:mark()` equals it reaches the callback, and
*   the hook accepts every other packet; without a `mark`, the callback runs for every
*   packet. `pf` takes a `linux.nf.proto` value, `hooknum` a hook of that family, as
*   `linux.nf.inet`, `linux.nf.arp` or `linux.nf.br` list them, and `priority` a
*   `linux.nf.ip.pri` or `linux.nf.br.pri` value.
*
*   `hook(skb)` returns the packet's verdict, `DROP`, `ACCEPT` or `QUEUE` of `linux.nf.action`,
*   and optionally a mark to set on the packet. A callback that returns no verdict, or that
*   raises, accepts the packet; one that returns any other value, `STOLEN`, `REPEAT` and `STOP`
*   included, accepts it too and logs `invalid verdict`.
* @treturn netfilter_hook the hook, which `netfilter.register` keeps for its runtime: dropping it
*   stops nothing, and the callback runs until `stop` or the end of the runtime. The hook stays
*   registered until the runtime closes, and the one hook a percpu script's runtimes share until
*   the percpu set stops.
* @raise "not allowed once the runtime is armed" past the script body; `runtime context mismatch`
*   outside a softirq runtime; `not allowed while the runtime closes` from a finalizer that runs at
*   its close; `bad field '<field>' (number expected, got <type>)` if `pf`, `hooknum` or
*   `priority` is missing or not a number, or if `mark` is present and not a number;
*   `bad field '<field>' (out of bounds)` if `pf` is negative or past 8 bits, `hooknum` or `mark`
*   negative or past 32 bits, or `priority` past an `int`; if the hook cannot be registered; in a
*   percpu script, if this runtime already registered the same `pf`, `hooknum`, `priority` and
*   `mark`, or the same three both times without a `mark`
* @usage
*   local netfilter = require("netfilter")
*   local nf        = require("linux.nf")
*
*   local QUARANTINED <const> = 2 -- ifindex
*
*   local function quarantine(skb)
*     return skb:ifindex() == QUARANTINED and nf.action.DROP or nf.action.ACCEPT
*   end
*
*   netfilter.register{
*     hook     = quarantine,
*     pf       = nf.proto.INET,
*     hooknum  = nf.inet.PRE_ROUTING,
*     priority = nf.ip.pri.FILTER,
*   }
* @within netfilter
*/
static int luanetfilter_lregister(lua_State *L)
{
	lunatik_checkarmed(L);
	luanetfilter_hook_t spec = {.nfops = {.hook = luanetfilter_hook}};
	luanetfilter_checkspec(L, 1, &spec);
	lunatik_object_t *runtime = lunatik_checkruntime(L, luanetfilter_class.name, luanetfilter_class.opt);
	lunatik_object_t *percpu = lunatik_getpercpu(L);

	lunatik_object_t *object = lunatik_newobject(L, &luanetfilter_class, sizeof(luanetfilter_t), LUNATIK_OPT_NONE);
	luanetfilter_t *nf = (luanetfilter_t *)object->private;
	nf->runtime = runtime;

	luanetfilter_hook_t *hook = percpu != NULL ? luanetfilter_share(L, percpu, &spec) : luanetfilter_own(L, nf, &spec);
	lunatik_attach(L, nf, skb, luaskb_attach, false);
	lunatik_registerobject(L, 1, object);
	lunatik_register(L, -1, hook); /* the callback finds this runtime's registration by the hook they share */
	return 1;
}

static const luaL_Reg luanetfilter_lib[] = {
	{"register", luanetfilter_lregister},
	{NULL, NULL},
};

static void luanetfilter_release(void *private)
{
	luanetfilter_t *nf = (luanetfilter_t *)private;

	if (nf->hook != NULL) {
		luanetfilter_free(nf->hook);
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
MODULE_VERSION(LUNATIK_RELEASE);
MODULE_AUTHOR("Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>");

