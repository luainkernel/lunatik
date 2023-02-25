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

#include <lua.h>
#include <lauxlib.h>

#define lunatik_mutex(L)	((struct mutex *)lua_getextraspace(L))
#define lunatik_lock(L)		(mutex_lock(lunatik_mutex(L)))
#define lunatik_unlock(L)	(mutex_unlock(lunatik_mutex(L)))

static inline lua_State *lunatik_newstate(void)
{
	lua_State *L;
	if ((L = luaL_newstate()) != NULL)
		mutex_init(lunatik_mutex(L));
	return L;
}

static inline void lunatik_close(lua_State *L)
{
	mutex_destroy(lunatik_mutex(L));
	lua_close(L);
}

#define lunatik_run(L, handler, ret, ...)	\
do {						\
	int n;					\
	lunatik_lock(L);			\
	n = lua_gettop(L);			\
	ret = handler(L, ## __VA_ARGS__);	\
	lua_settop(L, n);			\
	lunatik_unlock(L);			\
} while(0)

#endif

