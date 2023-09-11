/*
* Copyright (c) 2023 ring-0 Ltda.
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

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include "lunatik.h"
#include "lunatik_sym.h"

#ifdef LUNATIK_RUNTIME

static inline void lunatik_setversion(lua_State *L)
{
	lua_pushstring(L, LUNATIK_VERSION);
	lua_setglobal(L, "_LUNATIK_VERSION");
}

#define lunatik_gfp(runtime)	(runtime->sleep ? GFP_KERNEL : GFP_ATOMIC)

/* based on l_alloc() @ lua/lauxlib.c */
static void *lunatik_alloc(void *ud, void *ptr, size_t osize, size_t nsize)
{
	lunatik_runtime_t *runtime;
	(void)osize;  /* not used */
	if (nsize == 0) {
		kfree(ptr);
		return NULL;
	}
	runtime = (lunatik_runtime_t *)ud;
	return krealloc(ptr, nsize, lunatik_gfp(runtime));
}

static inline lunatik_runtime_t *lunatik_new(lua_State *L, bool sleep)
{
	lunatik_runtime_t *runtime;
	/* runtime creation are only allowed from process context */
	if ((runtime = (lunatik_runtime_t *)kmalloc(sizeof(lunatik_runtime_t), GFP_KERNEL)) == NULL)
		return NULL;
	runtime->sleep = sleep;
	runtime->ready = false;
	runtime->L = L;
	lunatik_toruntime(L) = runtime;
	lunatik_locker(runtime, mutex_init, spin_lock_init);
	kref_init(&runtime->kref);
	return runtime;
}

static inline void lunatik_runerror(lua_State *L, lua_State *parent, const char *errmsg)
{
	if (parent)
		lua_pushstring(parent, errmsg);
	else
		pr_err("%s\n", errmsg);
}

int luaopen_lunatik(lua_State *L); /* used for luaL_requiref() */

static int lunatik_newruntime(lunatik_runtime_t **pruntime, lua_State *parent, const char *script, bool sleep)
{
	lunatik_runtime_t *runtime;
	lua_State *L;
	const char *filename;
	int base;

	if ((L = luaL_newstate()) == NULL) {
		lunatik_runerror(L, parent, "failed to allocate Lua state");
		return -ENOMEM;
	}

	if ((runtime = lunatik_new(L, sleep)) == NULL) {
		lunatik_runerror(L, parent, "failed to allocate runtime");
		lua_close(L);
		return -ENOMEM;
	}

	base = lua_gettop(L);
	lunatik_setversion(L);
	luaL_openlibs(L);
	luaL_requiref(L, "lunatik", luaopen_lunatik, 0);
	lua_pop(L, 1); /* lunatik library */

	filename = lua_pushfstring(L, "%s%s.lua", LUA_ROOT, script);
	if (luaL_dofile(L, filename) != LUA_OK) {
		lunatik_runerror(L, parent, lua_tostring(L, -1));
		lua_close(L);
		lunatik_put(runtime);
		return -EINVAL;
	}

	lua_setallocf(L, lunatik_alloc, runtime);
	lua_settop(L, base);
	runtime->ready = true;
	*pruntime = runtime;
        return 0;
}

int lunatik_runtime(lunatik_runtime_t **pruntime, const char *script, bool sleep)
{
	return lunatik_newruntime(pruntime, NULL, script, sleep);
}
EXPORT_SYMBOL(lunatik_runtime);

int lunatik_stop(lunatik_runtime_t *runtime)
{
	lunatik_lock(runtime);
	lua_close(runtime->L);
	runtime->L = NULL;
	lunatik_unlock(runtime);
	return lunatik_put(runtime);
}
EXPORT_SYMBOL(lunatik_stop);

#define LUNATIK_MT	"runtime"

#define lunatik_checkpruntime(L, n)	((lunatik_runtime_t **)luaL_checkudata((L), (n), LUNATIK_MT))

lunatik_runtime_t *lunatik_checkruntime(lua_State *L, int arg)
{
	lunatik_runtime_t **pruntime = lunatik_checkpruntime(L, 1);
	lunatik_runtime_t *runtime = *pruntime;

	luaL_argcheck(L, runtime != NULL, arg, "invalid runtime");
	return runtime;
}
EXPORT_SYMBOL(lunatik_checkruntime);

static int lunatik_lruntime(lua_State *L)
{
	lunatik_runtime_t **pruntime;
	const char *script;
	bool sleep;

	script = luaL_checkstring(L, 1);
	sleep = (bool)(lua_gettop(L) >= 2 ? lua_toboolean(L, 2) : true);

	pruntime = (lunatik_runtime_t **)lua_newuserdatauv(L, sizeof(lunatik_runtime_t *), 0);
	if (lunatik_newruntime(pruntime, L, script, sleep) != 0)
		lua_error(L);
	luaL_setmetatable(L, LUNATIK_MT);
	return 1;
}

static int lunatik_lstop(lua_State *L)
{
	lunatik_runtime_t **pruntime = lunatik_checkpruntime(L, 1);
	lunatik_runtime_t *runtime = *pruntime;

	if (runtime != NULL) {
		lunatik_stop(runtime);
		*pruntime = NULL;
	}
	return 0;
}

static const luaL_Reg lunatik_lib[] = {
	{"runtime", lunatik_lruntime},
	{"stop", lunatik_lstop},
	{NULL, NULL}
};

static const luaL_Reg lunatik_mt[] = {
	{"__gc", lunatik_lstop},
	{"__close", lunatik_lstop},
	{"stop", lunatik_lstop},
	{NULL, NULL}
};

static const lunatik_class_t lunatik_class = {
	.name = LUNATIK_MT,
	.methods = lunatik_mt,
};

LUNATIK_NEWLIB(lunatik, lunatik_lib, &lunatik_class, NULL, true);
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
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ring-0.io>");

