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

#ifndef lunatik_h
#define lunatik_h

#include <linux/mutex.h>
#include <linux/spinlock.h>
#include <linux/slab.h>

#include <lua.h>
#include <lauxlib.h>

#define lunatik_locker(extra, mutex_op, spin_op)	\
do {							\
	if (extra->sleep)				\
		mutex_op(&extra->lock.mutex);		\
	else						\
		spin_op(&extra->lock.spin);		\
} while(0)

#define lunatik_getextra(L)	((lunatik_extra_t *)lua_getextraspace(L))
#define lunatik_lock(L)		lunatik_locker(lunatik_getextra(L), mutex_lock, spin_lock)
#define lunatik_unlock(L)	lunatik_locker(lunatik_getextra(L), mutex_unlock, spin_unlock)

int lunatik_runtime(lua_State **runtime, const char *entrypoint, bool sleep);
void lunatik_stop(lua_State **runtime);
int luaopen_lunatik(lua_State *L);

#define lunatik_run(L, handler, ret, ...)	\
do {						\
	int n;					\
	lunatik_lock(L);			\
	n = lua_gettop(L);			\
	ret = handler(L, ## __VA_ARGS__);	\
	lua_settop(L, n);			\
	lunatik_unlock(L);			\
} while(0)

#define LUNATIK_NEWLIB(libname, MT)				\
int luaopen_##libname(lua_State *L)				\
{								\
	luaL_newlib(L, libname##_lib);				\
	luaL_newmetatable(L, MT);				\
	luaL_setfuncs(L, libname##_mt, 0);			\
	lua_pushvalue(L, -1);  /* push lib */			\
	lua_setfield(L, -2, "__index");  /* mt.__index = lib */	\
	lua_pop(L, 1);  /* pop mt */				\
	return 1;						\
}								\
EXPORT_SYMBOL(luaopen_##libname)

#endif

