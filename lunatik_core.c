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
/* based on l_alloc() @ lua/lauxlib.c */
static void *lunatik_alloc(void *ud, void *ptr, size_t osize, size_t nsize)
{
	lunatik_extra_t *extra;
	(void)osize;  /* not used */

	if (nsize == 0) {
		kfree(ptr);
		return NULL;
	}
	extra = (lunatik_extra_t *)ud;
	return krealloc(ptr, nsize, extra->sleep ? GFP_KERNEL : GFP_ATOMIC);
}

/* based on luaL_openlibs() @ lua/linit.c */
static inline void lunatik_openlibs(lua_State *L, const luaL_Reg *libs)
{
	const luaL_Reg *lib;
	for (lib = libs; lib->func; lib++) {
		luaL_requiref(L, lib->name, lib->func, 1);
		lua_pop(L, 1);  /* remove lib */
	}
}

static inline void lunatik_setup(lua_State *L, bool sleep)
{
	lunatik_extra_t *extra;

	extra = lunatik_getextra(L);
	extra->sleep = sleep;
	lunatik_locker(extra, mutex_init, spin_lock_init);
	lua_setallocf(L, lunatik_alloc, extra);
}

int lunatik_runtime(lua_State **runtime, const luaL_Reg *libs, const char *entrypoint, bool sleep)
{
	lua_State *L;
	const char *filename;
	int base;

	if ((L = luaL_newstate()) == NULL)
		return -ENOMEM;

	base = lua_gettop(L);
	if (libs)
		lunatik_openlibs(L, libs);

	filename = lua_pushfstring(L, "%s%s", LUA_ROOT, entrypoint);
	if (luaL_dofile(L, filename) != LUA_OK) {
		pr_err("%s\n", lua_tostring(L, -1));
		lua_close(L);
		return -EINVAL;
	}

	lunatik_setup(L, sleep);
	lua_settop(L, base);
	*runtime = L;
        return 0;
}
EXPORT_SYMBOL(lunatik_runtime);

void lunatik_stop(lua_State **runtime)
{
	lua_State *L;
	lunatik_extra_t *extra;

	L = *runtime;
	extra = lunatik_getextra(L);
	if (extra->sleep)
		mutex_destroy(&extra->lock.mutex);
	lua_close(L);
	*runtime = NULL;
}
EXPORT_SYMBOL(lunatik_stop);

#define LUNATIK_MT	"lunatik"

static int lunatik_lruntime(lua_State *L)
{
	lua_State **runtime;
	const char *entrypoint;
	bool sleep;
	int ret;

	entrypoint = luaL_checkstring(L, 1);
	sleep = (bool)lua_toboolean(L, 2);
	/* TODO: pass libs as argument as well */

	runtime = (lua_State **)lua_newuserdatauv(L, sizeof(lua_State *), 0);
	if ((ret = lunatik_runtime(runtime, NULL, entrypoint, sleep)) != 0)
		/* TODO: get error message from runtime state */
		luaL_error(L, "failed to run '%s': (%d)", entrypoint, ret);
	luaL_setmetatable(L, LUNATIK_MT);
	return 1;
}

static int lunatik_lstop(lua_State *L)
{
	lua_State **runtime;

	runtime = (lua_State **)luaL_checkudata(L, 1, LUNATIK_MT);
	lunatik_stop(runtime);
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

/* TODO: move this to a new API (e.g., lunatik_opener) */
int luaopen_lunatik(lua_State *L)
{
	luaL_newlib(L, lunatik_lib);
	luaL_newmetatable(L, LUNATIK_MT);
	luaL_setfuncs(L, lunatik_mt, 0);
	lua_pushvalue(L, -1);  /* push lib */
	lua_setfield(L, -2, "__index");  /* mt.__index = lib */
	lua_pop(L, 1);  /* pop mt */
	return 1;

}
EXPORT_SYMBOL(luaopen_lunatik);
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

