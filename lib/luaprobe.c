/*
* SPDX-FileCopyrightText: (c) 2023-2024 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/kprobes.h>
#include <linux/string.h>

#include <lua.h>
#include <lauxlib.h>

#include <lunatik.h>

typedef struct luaprobe_s {
	struct kprobe kp;
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

static int luaprobe_handler(lua_State *L, luaprobe_t *probe, const char *handler, struct pt_regs *regs)
{
	struct kprobe *kp = &probe->kp;
	const char *symbol = kp->symbol_name;

	if (lunatik_getregistry(L, probe) != LUA_TTABLE) {
		pr_err("couldn't find probe table\n");
		goto out;
	}

	if (lua_getfield(L, -1, handler) != LUA_TFUNCTION) {
		pr_err("%s handler isn't defined\n", handler);
		goto out;
	}

	if (symbol != NULL)
		lua_pushstring(L, symbol);
	else
		lua_pushlightuserdata(L, kp->addr);

	lua_pushlightuserdata(L, regs);
	lua_pushcclosure(L, luaprobe_dump, 1);
	lua_pushvalue(L, -1); /* save dump() on the stack */
	lua_insert(L, -4); /* stack: dump, handler, symbol | addr, dump */

	if (lua_pcall(L, 2, 0, 0) != LUA_OK) /* handler(symbol | addr, dump) */
		pr_err("%s\n", lua_tostring(L, -1));

	lua_pushnil(L);
	lua_setupvalue(L, -2, 1); /* clean up regs */
out:
	return 0;
}

static int __kprobes luaprobe_pre_handler(struct kprobe *kp, struct pt_regs *regs)
{
	luaprobe_t *probe = container_of(kp, luaprobe_t, kp);
	int ret;

	lunatik_run(probe->runtime, luaprobe_handler, ret, probe, "pre", regs);
	return ret;
}

static void __kprobes luaprobe_post_handler(struct kprobe *kp, struct pt_regs *regs, unsigned long flags)
{
	luaprobe_t *probe = container_of(kp, luaprobe_t, kp);
	int ret;

	/* flags always seems to be zero; see:https://docs.kernel.org/trace/kprobes.html#api-reference */
	lunatik_run(probe->runtime, luaprobe_handler, ret, probe, "post", regs);
	(void)ret;
}

static void luaprobe_delete(luaprobe_t *probe)
{
	struct kprobe *kp = &probe->kp;
	const char *symbol_name = kp->symbol_name;

	if (kp->pre_handler != NULL) {
		disable_kprobe(kp);
		kp->pre_handler = NULL;
		kp->post_handler = NULL;
		unregister_kprobe(kp);
	}

	if (symbol_name != NULL) {
		kfree(symbol_name);
		kp->symbol_name = NULL;
	}
}

static void luaprobe_release(void *private)
{
	luaprobe_t *probe = (luaprobe_t *)private;

	/* device might have never been stopped */
	luaprobe_delete(probe);
	lunatik_putobject(probe->runtime);
}

static int luaprobe_stop(lua_State *L)
{
	lunatik_object_t *object = lunatik_checkobject(L, 1);
	luaprobe_t *probe = (luaprobe_t *)object->private;

	lunatik_lock(object);
	luaprobe_delete(probe);
	lunatik_unlock(object);

	if (lunatik_toruntime(L) == probe->runtime)
		lunatik_unregisterobject(L, object);
	return 0;
}

static int luaprobe_enable(lua_State *L)
{
	lunatik_object_t *object = lunatik_checkobject(L, 1);
	luaprobe_t *probe = (luaprobe_t *)object->private;
	struct kprobe *kp = &probe->kp;
	bool enable = lua_toboolean(L, 2);

	lunatik_lock(object);
	kp = &probe->kp;

	if (kp->pre_handler == NULL)
		goto err;

	if (enable)
		enable_kprobe(kp);
	else
		disable_kprobe(kp);
	lunatik_unlock(object);
	return 0;
err:
	lunatik_unlock(object);
	return luaL_argerror(L, 1, LUNATIK_ERR_NULLPTR);
}

static int luaprobe_new(lua_State *L);

static const luaL_Reg luaprobe_lib[] = {
	{"new", luaprobe_new},
	{NULL, NULL}
};

static const luaL_Reg luaprobe_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"stop", luaprobe_stop},
	{"enable", luaprobe_enable},
	{NULL, NULL}
};

static const lunatik_class_t luaprobe_class = {
	.name = "probe",
	.methods = luaprobe_mt,
	.release = luaprobe_release,
	.sleep = true,
};

static int luaprobe_new(lua_State *L)
{
	lunatik_object_t *object = lunatik_newobject(L, &luaprobe_class, sizeof(luaprobe_t));
	lunatik_object_t *runtime = lunatik_toruntime(L);
	luaprobe_t *probe = (luaprobe_t *)object->private;
	struct kprobe *kp = &probe->kp;
	int ret;

	memset(probe, 0, sizeof(luaprobe_t));

	probe->runtime = runtime;
	lunatik_getobject(runtime);

	if (lua_islightuserdata(L, 1))
		kp->addr = lua_touserdata(L, 1);
	else {
		size_t symbol_len;
		const char *symbol_name = luaL_checklstring(L, 1, &symbol_len);

		if ((kp->symbol_name = kstrndup(symbol_name, symbol_len, lunatik_gfp(runtime))) == NULL)
			luaL_error(L, "out of memory");
	}

	luaL_checktype(L, 2, LUA_TTABLE); /* handlers */

	kp->pre_handler = luaprobe_pre_handler;
	kp->post_handler = luaprobe_post_handler;

	if ((ret = register_kprobe(kp)) != 0) {
		kp->pre_handler = NULL; /* shouldn't unregister on release() */
		luaL_error(L, "failed to register probe (%d)", ret);
	}

	lunatik_registerobject(L, 2, object);
	return 1; /* object */
}

LUNATIK_NEWLIB(probe, luaprobe_lib, &luaprobe_class, NULL);

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
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ring-0.io>");

