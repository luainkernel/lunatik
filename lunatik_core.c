/*
* Copyright (c) 2023-2024 ring-0 Ltda.
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
lunatik_object_t *lunatik_runtimes;
EXPORT_SYMBOL(lunatik_runtimes);

static inline void lunatik_setversion(lua_State *L)
{
	lua_pushstring(L, LUNATIK_VERSION);
	lua_setglobal(L, "_LUNATIK_VERSION");
}

/* based on l_alloc() @ lua/lauxlib.c */
static void *lunatik_alloc(void *ud, void *ptr, size_t osize, size_t nsize)
{
	lunatik_object_t *runtime;
	(void)osize;  /* not used */
	if (nsize == 0) {
		kfree(ptr);
		return NULL;
	}
	runtime = (lunatik_object_t *)ud;
	return krealloc(ptr, nsize, lunatik_gfp(runtime));
}

static inline void lunatik_runerror(lua_State *L, lua_State *parent, const char *errmsg)
{
	if (parent)
		lua_pushstring(parent, errmsg);
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

static int lunatik_lruntimes(lua_State *L)
{
	lunatik_pushobject(L, lunatik_runtimes);
	return 1;
}

static const luaL_Reg lunatik_lib[] = {
	{"runtime", lunatik_lruntime},
	{"runtimes", lunatik_lruntimes},
	{NULL, NULL}
};

static const luaL_Reg lunatik_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{"stop", lunatik_closeobject},
	{NULL, NULL}
};

static const lunatik_class_t lunatik_class = {
	.name = "lunatik",
	.methods = lunatik_mt,
	.release = lunatik_releaseruntime,
	.sleep = true,
	.pointer = true,
};

int luaopen_lunatik(lua_State *L); /* used for luaL_requiref() */

static inline void lunatik_setready(lua_State *L)
{
	lua_pushboolean(L, true);
	lua_rawsetp(L, LUA_REGISTRYINDEX, L);
}

static int lunatik_newruntime(lunatik_object_t **pruntime, lua_State *parent, const char *script, bool sleep)
{
	lunatik_object_t *runtime;
	lua_State *L;
	const char *filename;

	if ((L = luaL_newstate()) == NULL) {
		lunatik_runerror(L, parent, "failed to allocate Lua state");
		return -ENOMEM;
	}

	if ((runtime = lunatik_malloc(L, sizeof(lunatik_object_t))) == NULL) {
		lunatik_runerror(L, parent, "failed to allocate runtime");
		lua_close(L);
		return -ENOMEM;
	}

	lunatik_setobject(runtime, &lunatik_class, sleep);
	lunatik_toruntime(L) = runtime;
	runtime->private = L;

	lunatik_setversion(L);
	luaL_openlibs(L);
	if (sleep) {
		luaL_requiref(L, "lunatik", luaopen_lunatik, 0);
		lua_pop(L, 1); /* lunatik library */
	}

	filename = lua_pushfstring(L, "%s%s.lua", LUA_ROOT, script);
	if (luaL_dofile(L, filename) != LUA_OK) {
		lunatik_runerror(L, parent, lua_tostring(L, -1));
		lunatik_putobject(runtime);
		return -EINVAL;
	}

	lua_setallocf(L, lunatik_alloc, runtime);
	lunatik_setready(L);
	*pruntime = runtime;
        return 0;
}

int lunatik_runtime(lunatik_object_t **pruntime, const char *script, bool sleep)
{
	return lunatik_newruntime(pruntime, NULL, script, sleep);
}
EXPORT_SYMBOL(lunatik_runtime);

static int lunatik_lruntime(lua_State *L)
{
	lunatik_object_t **pruntime;
	const char *script;
	bool sleep;

	script = luaL_checkstring(L, 1);
	sleep = (bool)(lua_gettop(L) >= 2 ? lua_toboolean(L, 2) : true);

	pruntime = lunatik_newpobject(L, 1);
	if (lunatik_newruntime(pruntime, L, script, sleep) != 0)
		lua_error(L);
	lunatik_setclass(L, &lunatik_class);
	return 1;
}

LUNATIK_NEWLIB(lunatik, lunatik_lib, &lunatik_class, NULL);
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

