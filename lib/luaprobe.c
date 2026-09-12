/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* kprobes interface.
* @module probe
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/kprobes.h>
#include <linux/list.h>
#include <linux/string.h>

#include <lunatik.h>

/***
* Represents a registered kprobe.
* @type probe
*/
typedef struct luaprobe_kprobe_s {
	struct hlist_node node;
	struct kref kref;	/* one reference per handle, plus the set's when the runtimes share it */
	struct kprobe kp;
	kprobe_opcode_t *addr;	/* the address asked for, NULL for a symbol: register_kprobe resolves kp.addr */
	lunatik_object_t *runtime;
} luaprobe_kprobe_t;

static void (*luaprobe_showregs)(struct pt_regs *);

static int luaprobe_dump(lua_State *L)
{
	struct pt_regs *regs = lua_touserdata(L, lua_upvalueindex(1));
	if (regs == NULL)
		luaL_error(L, LUNATIK_ERR_NULLPTR);

	luaprobe_showregs(regs);
	return 0;
}

static int luaprobe_handler(lua_State *L, luaprobe_kprobe_t *kprobe, const char *handler, struct pt_regs *regs)
{
	struct kprobe *kp = &kprobe->kp;
	const char *symbol = kp->symbol_name;

	if (lunatik_getregistry(L, kprobe) != LUA_TTABLE) {
		pr_err_ratelimited("couldn't find probe table\n");
		goto out;
	}

	lunatik_optcfunction(L, -1, handler, lunatik_nop);

	if (symbol != NULL)
		lua_pushstring(L, symbol);
	else
		lua_pushlightuserdata(L, kp->addr);

	lua_pushlightuserdata(L, regs);
	lua_pushcclosure(L, luaprobe_dump, 1);
	lua_pushvalue(L, -1); /* save dump() on the stack */
	lua_insert(L, -4); /* stack: dump, handler, symbol | addr, dump */

	if (lua_pcall(L, 2, 0, 0) != LUA_OK) /* handler(symbol | addr, dump) */
		pr_err_ratelimited("%s\n", lua_tostring(L, -1));

	lua_pushnil(L);
	lua_setupvalue(L, -2, 1); /* clean up regs */
out:
	return 0;
}

static int __kprobes luaprobe_pre_handler(struct kprobe *kp, struct pt_regs *regs)
{
	luaprobe_kprobe_t *kprobe = container_of(kp, luaprobe_kprobe_t, kp);
	int ret;

	lunatik_run(kprobe->runtime, luaprobe_handler, ret, kprobe, "pre", regs);
	(void)ret;
	return 0;
}

static void __kprobes luaprobe_post_handler(struct kprobe *kp, struct pt_regs *regs, unsigned long flags)
{
	luaprobe_kprobe_t *kprobe = container_of(kp, luaprobe_kprobe_t, kp);
	int ret;

	/* flags always seems to be zero; see: https://docs.kernel.org/trace/kprobes.html#api-reference */
	lunatik_run(kprobe->runtime, luaprobe_handler, ret, kprobe, "post", regs);
	(void)ret;
}

static void luaprobe_delete(luaprobe_kprobe_t *kprobe)
{
	struct kprobe *kp = &kprobe->kp;
	const char *symbol_name = kp->symbol_name;

	if (kp->pre_handler != NULL) {
		/* disarm picks the ftrace_ops from post_handler; clear handlers only after unregister */
		unregister_kprobe(kp);
		kp->pre_handler = NULL;
		kp->post_handler = NULL;
	}

	if (symbol_name != NULL) {
		kfree(symbol_name);
		kp->symbol_name = NULL;
	}
}

static bool luaprobe_match(const luaprobe_kprobe_t *kprobe, const luaprobe_kprobe_t *spec)
{
	const char *symbol = kprobe->kp.symbol_name;

	if (spec->kp.symbol_name == NULL)
		return kprobe->addr == spec->addr;
	return symbol != NULL && strcmp(symbol, spec->kp.symbol_name) == 0;
}

static luaprobe_kprobe_t *luaprobe_find(struct hlist_head *kprobes, const luaprobe_kprobe_t *spec)
{
	luaprobe_kprobe_t *kprobe;

	hlist_for_each_entry(kprobe, kprobes, node) {
		if (luaprobe_match(kprobe, spec))
			return kprobe;
	}
	return NULL;
}

static luaprobe_kprobe_t *luaprobe_register(lua_State *L, lunatik_object_t *runtime, const luaprobe_kprobe_t *spec)
{
	luaprobe_kprobe_t *kprobe = lunatik_checkalloc(L, sizeof(luaprobe_kprobe_t));
	struct kprobe *kp = &kprobe->kp;
	int ret;

	*kprobe = *spec;
	kprobe->runtime = runtime;
	kref_init(&kprobe->kref);

	if (kp->symbol_name != NULL) {
		kp->symbol_name = kstrdup(kp->symbol_name, lunatik_gfp(lunatik_toruntime(L)));
		if (kp->symbol_name == NULL) {
			lunatik_free(kprobe);
			lunatik_enomem(L);
		}
	}

	if ((ret = register_kprobe(kp)) != 0) {
		kfree(kp->symbol_name);
		lunatik_free(kprobe);
		luaL_error(L, "failed to register probe (%d)", ret);
	}
	return kprobe;
}

static void luaprobe_free(struct kref *kref)
{
	luaprobe_kprobe_t *kprobe = container_of(kref, luaprobe_kprobe_t, kref);

	luaprobe_delete(kprobe);
	lunatik_free(kprobe);
}

#define luaprobe_put(kprobe)	kref_put(&(kprobe)->kref, luaprobe_free)

#define luaprobe_isshared(kprobe)	lunatik_ispercpu((kprobe)->runtime->opt)

static void luaprobe_disarm(luaprobe_kprobe_t *kprobe)
{
	luaprobe_delete(kprobe); /* the set unregisters before its runtimes close, however many handles remain */
	luaprobe_put(kprobe);
}

LUNATIK_PERCPUDATA(luaprobe_kprobes, "probe.kprobes", luaprobe_kprobe_t, luaprobe_disarm);

static void luaprobe_release(void *private)
{
	luaprobe_kprobe_t *kprobe = (luaprobe_kprobe_t *)private;
	lunatik_object_t *runtime = kprobe->runtime;
	bool owned = !luaprobe_isshared(kprobe); /* the percpu object outlives the runtimes it closes */

	luaprobe_put(kprobe);
	if (owned)
		lunatik_putobject(runtime);
}

static const lunatik_class_t luaprobe_class;

#define LUAPROBE_ERR_SHARED	"the percpu object owns this probe"

/***
* Unregisters and stops the probe.
* @function stop
* @raise if the percpu object owns this probe
*/
static int luaprobe_stop(lua_State *L)
{
	lunatik_object_t *object = lunatik_checkobjectclass(L, 1, &luaprobe_class);
	luaprobe_kprobe_t *kprobe = (luaprobe_kprobe_t *)object->private;

	luaL_argcheck(L, !luaprobe_isshared(kprobe), 1, LUAPROBE_ERR_SHARED);
	luaprobe_delete(kprobe);

	if (lunatik_toruntime(L) == kprobe->runtime)
		lunatik_unregisterobject(L, object);
	return 0;
}

/***
* Enables or disables the probe.
* @function enable
* @tparam boolean flag true to enable, false to disable
* @raise if the probe has been stopped, or if the percpu object owns this probe
*/
static int luaprobe_enable(lua_State *L)
{
	lunatik_object_t *object = lunatik_checkobjectclass(L, 1, &luaprobe_class);
	luaprobe_kprobe_t *kprobe = (luaprobe_kprobe_t *)object->private;
	bool enable = lua_toboolean(L, 2);

	luaL_argcheck(L, !luaprobe_isshared(kprobe), 1, LUAPROBE_ERR_SHARED);
	struct kprobe *kp = &kprobe->kp;

	if (kp->pre_handler == NULL)
		return luaL_argerror(L, 1, LUNATIK_ERR_NULLPTR);

	if (enable)
		enable_kprobe(kp);
	else
		disable_kprobe(kp);

	return 0;
}

static int luaprobe_new(lua_State *L);

/***
* Creates and registers a new kprobe.
* In a percpu script the runtimes share one kprobe per symbol or address: the first
* registration installs it, the others attach their handlers, and a call reaches the
* runtime of the CPU it ran on.
* @function new
* @tparam string|lightuserdata symbol kernel symbol name or address
* @tparam table handlers table with optional `pre` and `post` callback functions;
*   each receives the symbol (string or lightuserdata) and a `dump` closure
* @treturn probe
* @raise if registration fails; in a percpu script, if this runtime already probed the same
*   symbol or address, or if called after module load
*/
static const luaL_Reg luaprobe_lib[] = {
	{"new", luaprobe_new},
	{NULL, NULL}
};

static const luaL_Reg luaprobe_mt[] = {
	{"__gc",   lunatik_deleteobject},
	{"stop",   luaprobe_stop},
	{"enable", luaprobe_enable},
	{NULL, NULL}
};

LUNATIK_OPENER(probe);
static const lunatik_class_t luaprobe_class = {
	.name = "probe",
	.methods = luaprobe_mt,
	.release = luaprobe_release,
	.opener = luaopen_probe,
	.opt = LUNATIK_OPT_HARDIRQ | LUNATIK_OPT_SINGLE | LUNATIK_OPT_EXTERNAL,
};

static void luaprobe_checkspec(lua_State *L, int ix, luaprobe_kprobe_t *spec)
{
	if (lua_islightuserdata(L, ix))
		spec->addr = spec->kp.addr = lua_touserdata(L, ix);
	else
		spec->kp.symbol_name = luaL_checkstring(L, ix); /* anchored at ix until luaprobe_register copies it */
}

static luaprobe_kprobe_t *luaprobe_share(lua_State *L, lunatik_object_t *percpu, const luaprobe_kprobe_t *spec)
{
	struct hlist_head *kprobes = lunatik_percpudata(L, &luaprobe_kprobes_class, sizeof(struct hlist_head))->private;
	luaprobe_kprobe_t *kprobe = luaprobe_find(kprobes, spec);

	if (kprobe == NULL) {
		kprobe = luaprobe_register(L, percpu, spec);
		hlist_add_head(&kprobe->node, kprobes);
	}
	else if (lunatik_getregistry(L, kprobe) != LUA_TNIL)
		luaL_error(L, "probe already registered");
	else
		lua_pop(L, 1);

	kref_get(&kprobe->kref);
	return kprobe;
}

static luaprobe_kprobe_t *luaprobe_own(lua_State *L, lunatik_object_t *runtime, const luaprobe_kprobe_t *spec)
{
	luaprobe_kprobe_t *kprobe = luaprobe_register(L, runtime, spec);

	lunatik_getobject(runtime); /* a percpu object is held by its data; a plain runtime is held here */
	return kprobe;
}

static int luaprobe_new(lua_State *L)
{
	luaprobe_kprobe_t spec = {.kp = {.pre_handler = luaprobe_pre_handler, .post_handler = luaprobe_post_handler}};
	luaprobe_checkspec(L, 1, &spec);
	luaL_checktype(L, 2, LUA_TTABLE); /* handlers */
	lunatik_object_t *runtime = lunatik_checkruntime(L, LUNATIK_OPT_HARDIRQ);
	lunatik_object_t *percpu = lunatik_getpercpu(L);

	lunatik_object_t *object = lunatik_newobject(L, &luaprobe_class, 0, LUNATIK_OPT_NONE);

	object->private = percpu != NULL ? luaprobe_share(L, percpu, &spec) : luaprobe_own(L, runtime, &spec);

	lunatik_registerobject(L, 2, object); /* the handler finds this runtime's handlers by the kprobe they share */
	return 1; /* object */
}

LUNATIK_CLASSES(probe, &luaprobe_class);
LUNATIK_NEWLIB(probe, luaprobe_lib, luaprobe_classes);

static int __init luaprobe_init(void)
{
	if ((luaprobe_showregs = (void (*)(struct pt_regs *))lunatik_lookup("show_regs")) == NULL)
		return -ENXIO;
	return 0;
}

static void __exit luaprobe_exit(void)
{
}

module_init(luaprobe_init);
module_exit(luaprobe_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ringzero.com.br>");

