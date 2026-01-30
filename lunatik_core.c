/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Core Lunatik module.
* Provides functionalities to create and manage Lunatik runtimes,
* which are isolated Lua environments running within the Linux kernel.
* This module exposes the `lunatik` global table in Lua, which can be
* used to create new runtimes. Runtime objects themselves have methods
* to control their execution (e.g., `resume`, `stop`).
*
* If a global Lunatik environment (`lunatik_env`) is configured at the C level,
* it can be exposed to Lua scripts as `lunatik._ENV`. This allows for a shared
* environment across multiple scripts or runtimes.
*
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
* Shared environment
* @field _ENV points to a shared global Lunatik runtime object. Scripts can
* share RCU tables or other Lunatik objects through this mechanism.
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
* Represents a Lunatik runtime environment.
* This is a userdata object returned by `lunatik.runtime()`. It encapsulates an
* isolated Lua state running within the Linux kernel. Each runtime can be
* configured as sleepable (allowing blocking operations, using `GFP_KERNEL`
* for allocations and mutexes for synchronization) or non-sleepable/atomic
* (prohibiting blocking operations, using `GFP_ATOMIC` for allocations and
* spinlocks for synchronization).
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
		lunatik_object_t *object = lunatik_testobject(Lfrom, ixfrom + i);

		luaL_argcheck(L, object != NULL, i + 1, "invalid object");
		lunatik_pushobject(L, object);
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
* Resumes a Lunatik runtime that has yielded.
* This function is used to continue the execution of a Lua script within a
* Lunatik runtime from the point where it last yielded. It's analogous to
* Lua's `coroutine.resume`.
* The `resume` method is called on a Lunatik runtime object.
* @function resume
* @param ... Arguments to pass to the Lua script upon resumption. These arguments will be received by the `coroutine.yield()` call that suspended the script.
* @treturn vararg Values returned by the `coroutine.yield()` call if the script yielded again, or values returned by the script if it completed.
* @raise Error if the runtime cannot be resumed or if an error occurs within the resumed script. The error message will be propagated from the Lua C API error.
* @usage
*   -- Assuming 'rt' is a Lunatik runtime object that has yielded.
*   local success, res_or_err = pcall(function() return rt:resume("arg_to_script") end)
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
* Stops and releases a Lunatik runtime environment.
* This method is called on a Lunatik runtime object. Once stopped, the runtime
* cannot be resumed or used further. It ensures that the associated Lua state
* is closed and all kernel resources are freed.
*
* This method provides an explicit way to release the runtime.
* @function stop
* @treturn nil Does not return any value to Lua.
* @raise Error May raise an error if the underlying C function encounters a critical issue during cleanup and calls `lua_error`.
* @usage
*   -- Assuming 'rt' is a Lunatik runtime object:
*   rt:stop()
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
	.sleep = true,
	.shared = true,
	.pointer = true,
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
	luaL_openlibs(L);

	if (lunatik_toruntime(L)->sleep)
		luaL_requiref(L, "lunatik", luaopen_lunatik, 0);
	else
		luaL_requiref(L, "lunatik", luaopen_lunatik_stub, 0);

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

static int lunatik_newruntime(lunatik_object_t **pruntime, lua_State *Lfrom, const char *script, bool sleep)
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

	lunatik_setobject(runtime, &lunatik_class, sleep);
	lunatik_toruntime(L) = runtime;
	runtime->private = L;

	runtime->gfp = GFP_KERNEL; /* might use kvmalloc while running in process */
	lua_setallocf(L, lunatik_alloc, runtime);

	lua_pushcfunction(L, lunatik_runscript);
	lua_pushlightuserdata(L, (void *)script);
	if (lua_pcall(L, 1, 1, 0) != LUA_OK) {
		lunatik_runerror(Lfrom, lua_tostring(L, -1));
		lunatik_putobject(runtime);
		return -ENOEXEC;
	}

	if (!sleep)
		runtime->gfp = GFP_ATOMIC;

	*pruntime = runtime;
        return 0;
}

int lunatik_runtime(lunatik_object_t **pruntime, const char *script, bool sleep)
{
	return lunatik_newruntime(pruntime, NULL, script, sleep);
}
EXPORT_SYMBOL(lunatik_runtime);

/***
* Creates and starts a new Lunatik runtime environment.
* A Lunatik runtime is an isolated Lua state that can execute Lua scripts
* within the kernel. Each runtime operates independently.
*
* The userdata object returned by `lunatik.runtime()` encapsulates an
* isolated Lua state running within the Linux kernel. Each runtime can be
* configured as sleepable (allowing blocking operations, using `GFP_KERNEL`
* for allocations and mutexes for synchronization) or non-sleepable/atomic
* (prohibiting blocking operations, using `GFP_ATOMIC` for allocations and
* spinlocks for synchronization).

* @function runtime
* @tparam string script The name of the Lua script to load and execute (e.g., "myscript").
*   The system will look for "myscript.lua" in the Lua root path.
* @tparam[opt=true] boolean sleep If `true` (default),
*   the runtime can sleep (e.g., for I/O operations) and uses `GFP_KERNEL` for allocations.
*   If `false`, the runtime operates in an atomic context, cannot sleep, and uses `GFP_ATOMIC` for allocations.
*   This is crucial for runtimes used in contexts that cannot sleep, like Netfilter hooks.
* @treturn runtime A Lunatik runtime object. This object can be used to interact with the runtime, for example,
*   to resume it if it yields or to stop it.
* @raise Error if the Lua state or runtime cannot be allocated, or if the script fails to load or execute.
* @within lunatik
*/
static int lunatik_lruntime(lua_State *L)
{
	const char *script = luaL_checkstring(L, 1);
	bool sleep = (bool)(lua_gettop(L) >= 2 ? lua_toboolean(L, 2) : true);

	lunatik_object_t **pruntime = lunatik_newpobject(L, 1);
	if (lunatik_newruntime(pruntime, L, script, sleep) != 0)
		lua_error(L);
	lunatik_setclass(L, &lunatik_class);
	return 1;
}

LUNATIK_NEWLIB(lunatik, lunatik_lib, &lunatik_class, NULL);
LUNATIK_NEWLIB(lunatik_stub, lunatik_stub_lib, NULL, NULL);
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

