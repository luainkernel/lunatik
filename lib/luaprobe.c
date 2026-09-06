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

typedef struct luaprobe_kprobe_s {
	struct hlist_node node;
	struct kprobe kp;
	lunatik_object_t *runtime;
} luaprobe_kprobe_t;

typedef struct luaprobe_spec_s {
	const char *symbol;	/* the Lua string, copied only when a kprobe is registered */
	void *addr;
} luaprobe_spec_t;

/***
* Represents a registered kprobe.
* @type probe
*/
typedef struct luaprobe_s {
	luaprobe_kprobe_t *kprobe;	/* NULL when the percpu object owns the kprobe */
	lunatik_object_t *runtime;
} luaprobe_t;

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
	lunatik_object_t *object = lunatik_getregistryobject(L, kprobe);

	if (object == NULL || lunatik_getregistry(L, object->private) != LUA_TTABLE) {
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

static bool luaprobe_matches(const struct kprobe *kp, const luaprobe_spec_t *spec)
{
	if (spec->symbol == NULL)
		return kp->addr == spec->addr;
	return kp->symbol_name != NULL && strcmp(kp->symbol_name, spec->symbol) == 0;
}

static luaprobe_kprobe_t *luaprobe_findkprobe(struct hlist_head *kprobes, const luaprobe_spec_t *spec)
{
	luaprobe_kprobe_t *kprobe;

	hlist_for_each_entry(kprobe, kprobes, node) {
		if (luaprobe_matches(&kprobe->kp, spec))
			return kprobe;
	}
	return NULL;
}

static luaprobe_kprobe_t *luaprobe_newkprobe(lua_State *L, lunatik_object_t *runtime, const luaprobe_spec_t *spec)
{
	luaprobe_kprobe_t *kprobe = lunatik_checkzalloc(L, sizeof(luaprobe_kprobe_t));
	struct kprobe *kp = &kprobe->kp;
	int ret;

	kprobe->runtime = runtime;
	kp->addr = spec->addr;
	kp->pre_handler = luaprobe_pre_handler;
	kp->post_handler = luaprobe_post_handler;

	if (spec->symbol != NULL && (kp->symbol_name = kstrdup(spec->symbol, lunatik_gfp(runtime))) == NULL) {
		lunatik_free(kprobe);
		lunatik_enomem(L);
	}

	if ((ret = register_kprobe(kp)) != 0) {
		kfree(kp->symbol_name);
		lunatik_free(kprobe);
		luaL_error(L, "failed to register probe (%d)", ret);
	}
	return kprobe;
}

static void luaprobe_freekprobe(luaprobe_kprobe_t *kprobe)
{
	unregister_kprobe(&kprobe->kp);
	kfree(kprobe->kp.symbol_name);
	lunatik_free(kprobe);
}

static void luaprobe_stopkprobes(void *private)
{
	luaprobe_kprobe_t *kprobe;
	struct hlist_node *next;

	hlist_for_each_entry_safe(kprobe, next, (struct hlist_head *)private, node) {
		hlist_del(&kprobe->node);
		luaprobe_freekprobe(kprobe);
	}
}

static const lunatik_class_t luaprobe_kprobes_class = {
	.name = "probe.kprobes",
	.release = luaprobe_stopkprobes,
};

static void luaprobe_release(void *private)
{
	luaprobe_t *probe = (luaprobe_t *)private;

	if (probe->kprobe != NULL)
		luaprobe_freekprobe(probe->kprobe);
	if (probe->runtime != NULL) /* NULL in a percpu runtime: the object's data holds the reference */
		lunatik_putobject(probe->runtime);
}

static const lunatik_class_t luaprobe_class;

#define LUAPROBE_ERR_SHARED	"the percpu object owns this probe"

/***
* Unregisters and stops the probe.
* @function stop
* @raise if the percpu object owns this probe, whose stop unregisters it
*/
static int luaprobe_stop(lua_State *L)
{
	lunatik_object_t *object = lunatik_checkobjectclass(L, 1, &luaprobe_class);
	luaprobe_t *probe = (luaprobe_t *)object->private;

	luaL_argcheck(L, probe->runtime != NULL, 1, LUAPROBE_ERR_SHARED);
	if (probe->kprobe != NULL) {
		void *key = probe->kprobe; /* freed below, but only ever a registry key */

		luaprobe_freekprobe(probe->kprobe);
		lunatik_unregister(L, key);
		probe->kprobe = NULL;
	}

	if (lunatik_toruntime(L) == probe->runtime)
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
	luaprobe_t *probe = (luaprobe_t *)object->private;
	bool enable = lua_toboolean(L, 2);

	luaL_argcheck(L, probe->runtime != NULL, 1, LUAPROBE_ERR_SHARED);
	luaL_argcheck(L, probe->kprobe != NULL, 1, LUNATIK_ERR_NULLPTR);
	if (enable)
		enable_kprobe(&probe->kprobe->kp);
	else
		disable_kprobe(&probe->kprobe->kp);

	return 0;
}

static int luaprobe_new(lua_State *L);

/***
* Creates and registers a new kprobe.
* In a percpu script the runtimes share one kprobe per symbol or address: the first
* registration installs it, the others attach their handlers, and it fires on the runtime
* of the CPU it hit.
* @function new
* @tparam string|lightuserdata symbol kernel symbol name or address
* @tparam table handlers table with optional `pre` and `post` callback functions;
*   each receives the symbol (string or lightuserdata) and a `dump` closure
* @treturn probe
* @raise if registration fails; in a percpu script, if this runtime already probed the same
*   symbol, or if called after module load
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
	.opt = LUNATIK_OPT_HARDIRQ | LUNATIK_OPT_SINGLE,
};

static luaprobe_kprobe_t *luaprobe_sharekprobe(lua_State *L, lunatik_object_t *percpu, const luaprobe_spec_t *spec)
{
	struct hlist_head *kprobes = lunatik_percpudata(L, &luaprobe_kprobes_class, sizeof(struct hlist_head))->private;
	luaprobe_kprobe_t *kprobe = luaprobe_findkprobe(kprobes, spec);

	if (kprobe == NULL) {
		kprobe = luaprobe_newkprobe(L, percpu, spec);
		hlist_add_head(&kprobe->node, kprobes);
	}
	else if (lunatik_getregistry(L, kprobe) != LUA_TNIL)
		luaL_error(L, "probe already registered");
	else
		lua_pop(L, 1);
	return kprobe;
}

static luaprobe_kprobe_t *luaprobe_ownkprobe(lua_State *L, luaprobe_t *probe, const luaprobe_spec_t *spec)
{
	lunatik_getobject(probe->runtime); /* a percpu object is held by its data; a plain runtime is held here */
	probe->kprobe = luaprobe_newkprobe(L, probe->runtime, spec);
	return probe->kprobe;
}

static int luaprobe_new(lua_State *L)
{
	luaprobe_spec_t spec = {NULL, NULL};
	lunatik_object_t *runtime = lunatik_checkruntime(L, LUNATIK_OPT_HARDIRQ);
	lunatik_object_t *percpu = lunatik_getpercpu(L);

	if (lua_islightuserdata(L, 1))
		spec.addr = lua_touserdata(L, 1);
	else
		spec.symbol = luaL_checkstring(L, 1);
	luaL_checktype(L, 2, LUA_TTABLE); /* handlers */

	lunatik_object_t *object = lunatik_newobject(L, &luaprobe_class, sizeof(luaprobe_t), LUNATIK_OPT_NONE);
	luaprobe_t *probe = (luaprobe_t *)object->private;
	probe->runtime = percpu != NULL ? NULL : runtime; /* a runtime's handle owns no reference */

	luaprobe_kprobe_t *kprobe = percpu != NULL ? luaprobe_sharekprobe(L, percpu, &spec) :
		luaprobe_ownkprobe(L, probe, &spec);

	/* a probe that raised before this leaves nothing registered; the handler bails until both are */
	lunatik_registerobject(L, 2, object);
	lunatik_register(L, -1, kprobe); /* the handler finds this runtime's handlers by the kprobe they share */
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

