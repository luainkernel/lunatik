/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Manages Lunatik runtimes — isolated Lua states running in the kernel.
* @module lunatik
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/module.h>
#include <linux/mm.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include "lunatik.h"
#include "lunatik_sym.h"

/***
* Shared global environment; scripts exchange objects (e.g. RCU tables) through it.
* @field _ENV
* @within lunatik
*/

#ifdef LUNATIK_RUNTIME
lunatik_object_t *lunatik_env;
EXPORT_SYMBOL(lunatik_env);
EXPORT_SYMBOL(luaS_hash);	/* required by luarcu */

static inline void lunatik_setversion(lua_State *L)
{
	lua_pushstring(L, LUNATIK_VERSION);
	lua_setglobal(L, "_LUNATIK_VERSION");
}

#define lunatik_cankrealloc(p, n, f)	\
	(((f) == GFP_ATOMIC || (n) <= PAGE_SIZE) && (!is_vmalloc_addr(p) || (p) == NULL))

/***
* Isolated Lua state running within the Linux kernel.
* @type runtime
*/
static void *lunatik_alloc(void *ud, void *optr, size_t osize, size_t nsize)
{
	if (nsize == 0) {
		kvfree(optr);
		return NULL;
	}

	lunatik_object_t *runtime = (lunatik_object_t *)ud;
	gfp_t gfp = lunatik_gfp(runtime);

	if (lunatik_cankrealloc(optr, nsize, gfp))
		return krealloc(optr, nsize, gfp);

	void *nptr = gfp == GFP_KERNEL ? kvmalloc(nsize, gfp) : kmalloc(nsize, gfp);
	if (nptr == NULL) /* if shrinking, it's safe to return optr */
		return nsize <= osize ? optr : nptr;
	else if (optr != NULL) {
		memcpy(nptr, optr, min(osize, nsize));
		kvfree(optr);
	}
	return nptr;
}

static inline void lunatik_runerror(lua_State *L, const char *errmsg)
{
	if (L)
		lua_pushstring(L, errmsg);
	else
		pr_err("%s\n", errmsg);
}

static void lunatik_releaseruntime(void *private)
{
	lua_State *L = (lua_State *)private;
	lua_close(L);
}

int lunatik_stop(lunatik_object_t *runtime)
{
	void *private;

	lunatik_lock(runtime);
	private = runtime->private;
	runtime->private = NULL;
	lunatik_unlock(runtime);

	lunatik_releaseruntime(private);
	return lunatik_putobject(runtime);
}
EXPORT_SYMBOL(lunatik_stop);

static int lunatik_lruntime(lua_State *L);

LUNATIK_PRIVATECHECKER(lunatik_check, lua_State *);

static int lunatik_lcopyobjects(lua_State *L)
{
	lua_State *Lfrom = (lua_State *)lua_touserdata(L, 1);
	int ixfrom = lua_tointeger(L, 2);
	int nobjects = lua_tointeger(L, 3);
	int i;

	for (i = 0; i < nobjects; i++) {
		lunatik_object_t **pobject = lunatik_testobject(Lfrom, ixfrom + i);

		luaL_argcheck(L, pobject, i + 1, "invalid object");
		lunatik_pushobject(L, *pobject);
	}
	return nobjects;
}

static inline int lunatik_copyobjects(lua_State *Lto, lua_State *Lfrom, int ixfrom, int nobjects)
{
	lua_pushcfunction(Lto, lunatik_lcopyobjects);
	lua_pushlightuserdata(Lto, Lfrom);
	lua_pushinteger(Lto, ixfrom);
	lua_pushinteger(Lto, nobjects);

	return lua_pcall(Lto, 3, nobjects, 0);
}

static inline int lunatik_resume(lua_State *Lto, lua_State *Lfrom, int nargs)
{
	int nresults;
	int status = lua_resume(Lto, Lfrom, nargs, &nresults);
	return status == LUA_OK || status == LUA_YIELD ? nresults : -1;
}

/***
* Resumes a yielded runtime, analogous to `coroutine.resume`.
* @function resume
* @param ... values delivered to the script as return values of `coroutine.yield()`
* @treturn vararg values passed to the next `coroutine.yield()`, or returned by the script
* @raise if the runtime errors on resumption
*/
static int lunatik_lresume(lua_State *L)
{
	lua_State *Lto = lunatik_check(L, 1);
	int nargs = lua_gettop(L) - 1;
	int nresults = 0;

	if (lunatik_copyobjects(Lto, L, 2, nargs) != LUA_OK || (nresults = lunatik_resume(Lto, L, nargs) < 0)) {
		lua_pushfstring(L, "%s\n", lua_tostring(Lto, -1));
		lua_pop(Lto, 1); /* error message */
		lua_error(L);
	}

	int status = lunatik_copyobjects(L, Lto, nargs, nresults);
	lua_pop(Lto, nresults);
	if (status != LUA_OK)
		lua_error(L);
	return nresults;
}

static const luaL_Reg lunatik_lib[] = {
	{"runtime", lunatik_lruntime},
	{NULL, NULL}
};

static const luaL_Reg lunatik_stub_lib[] = {
	{NULL, NULL}
};

/***
* Stops the runtime and releases all associated kernel resources.
* @function stop
*/
static const luaL_Reg lunatik_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{"stop", lunatik_closeobject},
	{"resume", lunatik_lresume},
	{NULL, NULL}
};

static const lunatik_class_t lunatik_class = {
	.name = "lunatik",
	.methods = lunatik_mt,
	.release = lunatik_releaseruntime,
	.opt = LUNATIK_OPT_MONITOR | LUNATIK_OPT_EXTERNAL,
};

/* used for luaL_requiref() */
int luaopen_lunatik(lua_State *L);
int luaopen_lunatik_stub(lua_State *L);

static inline void lunatik_setready(lua_State *L)
{
	lua_pushboolean(L, true);
	lua_rawsetp(L, LUA_REGISTRYINDEX, L);
}

static int lunatik_runscript(lua_State *L)
{
	const char *script = lua_pushfstring(L, "%s%s.lua", LUA_ROOT, lua_touserdata(L, 1));
	int scriptix = lua_gettop(L);

	lunatik_setversion(L);

	if (!(lunatik_isirq(lunatik_toruntime(L)->opt))) {
		luaL_openlibs(L);
		luaL_requiref(L, "lunatik", luaopen_lunatik, 0);
	}
	else {
		luaL_openselectedlibs(L, ~LUA_IOLIBK, 0);
		luaL_requiref(L, "lunatik", luaopen_lunatik_stub, 0);
	}

	if (lunatik_env != NULL) {
		lunatik_pushobject(L, lunatik_env);
		lua_setfield(L, -2, "_ENV");
	}
	lua_pop(L, 1); /* lunatik library */

	if (lunatik_loadfile(L, script, NULL) != LUA_OK)
		lua_error(L);

	lua_call(L, 0, 1);
	lua_remove(L, scriptix);
	lunatik_setready(L);
	return 1; /* callback */
}

static int lunatik_newruntime(lunatik_object_t **pruntime, lua_State *Lfrom, const char *script, lunatik_opt_t opt)
{
	lunatik_object_t *runtime;
	lua_State *L;

	if ((L = luaL_newstate()) == NULL) {
		lunatik_runerror(Lfrom, "failed to allocate Lua state");
		return -ENOMEM;
	}

	if ((runtime = kmalloc(sizeof(lunatik_object_t), GFP_KERNEL)) == NULL) {
		lunatik_runerror(Lfrom, "failed to allocate runtime");
		lua_close(L);
		return -ENOMEM;
	}

	lunatik_setobject(runtime, &lunatik_class, opt);
	lunatik_toruntime(L) = runtime;

	runtime->gfp = GFP_KERNEL; /* might use kvmalloc while running in process */
	lua_setallocf(L, lunatik_alloc, runtime);

	lua_pushcfunction(L, lunatik_runscript);
	lua_pushlightuserdata(L, (void *)script);
	if (lua_pcall(L, 1, 1, 0) != LUA_OK) {
		lunatik_runerror(Lfrom, lua_tostring(L, -1));
		lua_close(L); /* hooks hold extra krefs; putobject alone won't reach 0 */
		lunatik_putobject(runtime);
		return -ENOEXEC;
	}

	if (lunatik_isirq(opt))
		runtime->gfp = GFP_ATOMIC;

	runtime->private = L; /* NULL until here: lunatik_run returns -ENXIO during init */
	*pruntime = runtime;
	return 0;
}

int lunatik_runtime(lunatik_object_t **pruntime, const char *script, lunatik_opt_t opt)
{
	return lunatik_newruntime(pruntime, NULL, script, opt);
}
EXPORT_SYMBOL(lunatik_runtime);

/***
* Creates a new Lunatik runtime executing the given script.
* @function runtime
* @tparam string script script name (e.g., `"mymod"` loads `/lib/modules/lua/mymod.lua`)
* @tparam[opt="process"] string context execution context: `"process"` (sleepable,
*   GFP\_KERNEL, mutex), `"softirq"` (atomic, GFP\_ATOMIC, spinlock), or `"irq"`
*   (atomic, GFP\_ATOMIC, spinlock with IRQs disabled).
*   Use `"softirq"` for hooks that fire in softirq context (netfilter, XDP).
*   Use `"hardirq"` for hooks that fire in hardirq context (kprobes).
* @treturn runtime
* @raise if allocation fails or the script errors on load
* @within lunatik
*/
static int lunatik_lruntime(lua_State *L)
{
	static const char *const contexts[] = {"process", "softirq", "hardirq", NULL};
	static const lunatik_opt_t opts[] = {LUNATIK_OPT_NONE, LUNATIK_OPT_SOFTIRQ, LUNATIK_OPT_HARDIRQ};
	const char *script = luaL_checkstring(L, 1);
	int context = luaL_checkoption(L, 2, "process", contexts);
	lunatik_opt_t opt = opts[context];

	lunatik_object_t **pruntime = lunatik_newpobject(L, 1);
	if (lunatik_newruntime(pruntime, L, script, opt) != 0)
		lua_error(L);
	lunatik_setclass(L, &lunatik_class, true);
	return 1;
}

static const lunatik_class_t *lunatik_classes[] = { &lunatik_class, NULL };

LUNATIK_NEWLIB(lunatik, lunatik_lib, lunatik_classes);
LUNATIK_NEWLIB(lunatik_stub, lunatik_stub_lib, NULL);
#endif /* LUNATIK_RUNTIME */

static int __init lunatik_init(void)
{
	return 0;
}

static void __exit lunatik_exit(void)
{
}

module_init(lunatik_init);
module_exit(lunatik_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ringzero.com.br>");

