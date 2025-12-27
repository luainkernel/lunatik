/*
* SPDX-FileCopyrightText: (c) 2023-2025 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* kprobes mechanism.
* This library allows Lua scripts to dynamically probe (instrument) kernel
* functions or specific instruction addresses. Callbacks can be registered
* to execute Lua code just before (pre-handler) and/or just after
* (post-handler) the probed instruction is executed.
*
* @module probe
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/kprobes.h>
#include <linux/string.h>

#include <lua.h>
#include <lauxlib.h>

#include <lunatik.h>

/***
* Represents a kernel probe (kprobe) object.
* This is a userdata object returned by `probe.new()`. It encapsulates a
* `struct kprobe` and the associated Lua callback handlers. This object
* can be used to enable, disable, or stop (unregister) the probe.
* @type probe
*/
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

/***
* Stops and unregisters the probe.
* This method is called on a probe object. Once stopped, the kprobe is
* disabled and unregistered from the kernel, and its handlers will no longer
* be called. The associated resources are released.
* @function stop
* @treturn nil
* @usage my_probe_object:stop()
*/
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

/***
* Enables or disables an already registered probe.
* This method is called on a probe object.
* @function enable
* @tparam boolean enable_flag If `true`, the probe is enabled. If `false`, the probe is disabled.
*   A disabled probe remains registered but its handlers will not be executed.
* @treturn nil
* @raise Error if the probe was not properly registered or has been stopped.
* @usage my_probe_object:enable(false) -- Disable the probe
*/
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

/***
* Creates and registers a new kernel probe.
* This function installs a kprobe at the specified kernel symbol or address.
* Lua callback functions can be provided to execute when the probe hits.
*
* @function new
* @tparam string|lightuserdata symbol_or_address The kernel symbol name (string)
*   or the absolute kernel address (lightuserdata) to probe.
*   Suitable symbol names are typically those exported by the kernel or other modules,
*   often visible in `/proc/kallsyms` (when viewed from userspace). The `syscall`
*   module (e.g., `syscall.numbers.openat`) can be used to get system call numbers.
*
*   For system call addresses, you can use `syscall.address(syscall.numbers.openat)`.
*   For other kernel symbols, `linux.lookup("symbol_name")` can provide the address.
*   Directly using addresses requires knowing the exact memory location, which can
*   vary between kernel builds and is generally less portable than using symbol names
*   or lookup functions.
* @tparam table handlers A table containing the callback functions for the probe.
*   It can have the following fields:
*
*   - `pre` (function, optional): A Lua function to be called just *before* the
*     probed instruction is executed.
*   - `post` (function, optional): A Lua function to be called just *after* the
*     probed instruction has executed.
*
*   Both `pre` and `post` handlers receive two arguments:
*
*   1. `target` (string|lightuserdata): The symbol name or address that was probed.
*   2. `dump_regs` (function): A closure that, when called without arguments,
*      will print the current CPU registers and stack trace to the system log.
*      This is useful for debugging.
*
* @treturn probe A new probe object. This object can be used to later `stop()` or `enable()`/`disable()` the probe.
* @raise Error if the probe cannot be registered (e.g., symbol not found, memory allocation failure, invalid address).
* @within probe
*/
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
	lunatik_object_t *object = lunatik_newobject(L, &luaprobe_class, sizeof(luaprobe_t), false);
	luaprobe_t *probe = (luaprobe_t *)object->private;
	struct kprobe *kp = &probe->kp;
	int ret;

	memset(probe, 0, sizeof(luaprobe_t));

	lunatik_setruntime(L, probe, probe);
	lunatik_getobject(probe->runtime);

	if (lua_islightuserdata(L, 1))
		kp->addr = lua_touserdata(L, 1);
	else {
		size_t symbol_len;
		const char *symbol_name = luaL_checklstring(L, 1, &symbol_len);

		if ((kp->symbol_name = kstrndup(symbol_name, symbol_len, lunatik_gfp(probe->runtime))) == NULL)
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

