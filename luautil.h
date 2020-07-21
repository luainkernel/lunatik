/*
 * Copyright (C) 2020	Matheus Rodrigues <matheussr61@gmail.com>
 * Copyright (C) 2017-2019  CUJO LLC
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#ifndef _LUA_UTIL_H
#define _LUA_UTIL_H

#include "lua/lua.h"
#include "lua/lauxlib.h"

#ifndef LUNATIK_UNUSED

typedef const struct {} luaU_id[1];

static inline int luaU_pushudata(lua_State *L, void *ud)
{
	return lua_rawgetp(L, LUA_REGISTRYINDEX, ud) == LUA_TUSERDATA;
}

static inline void luaU_registerudata(lua_State *L, int v)
{
	void *ud = lua_touserdata(L, v);
	lua_pushvalue(L, v);
	lua_rawsetp(L, LUA_REGISTRYINDEX, ud);
}

static inline void luaU_unregisterudata(lua_State *L, void *ud)
{
	lua_pushnil(L);
	lua_rawsetp(L, LUA_REGISTRYINDEX, ud);
}

static inline void luaU_setregval(lua_State *L, luaU_id id, void *v)
{
	if (v) lua_pushlightuserdata(L, v);
	else lua_pushnil(L);
	lua_rawsetp(L, LUA_REGISTRYINDEX, id);
}

static inline void *luaU_getregval(lua_State *L, luaU_id id)
{
	void *v;

	lua_rawgetp(L, LUA_REGISTRYINDEX, id);
	v = lua_touserdata(L, -1);
	lua_pop(L, 1);

	return v;
}
#endif /*LUNATIK_UNUSED*/

#define luaU_setenv(L, env, st) { \
	st **penv = (st **)lua_getextraspace(L); \
	*penv = env; }

#ifndef LUNATIK_UNUSED
#define luaU_getenv(L, st)	(*((st **)lua_getextraspace(L)))

static inline int luaU_pusherr(lua_State *L, const char *err)
{
	lua_pushnil(L);
	lua_pushstring(L, err);
	return 2;
}
#endif /* _LUA_UTIL_H */

#define luaU_dostring(L, b, s, n) \
	(luaL_loadbufferx(L, b, s, n, "t") || luaU_pcall(L, 0, 0))

int luaU_pcall(lua_State *L, int nargs, int nresults);

#endif /* LUNATIK_UNUSED */
