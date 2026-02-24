/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include "lunatik.h"

void lunatik_checkvalue(lua_State *L, int ix, lunatik_value_t *value)
{
	value->type = lua_type(L, ix);
	switch (value->type) {
	case LUA_TNIL:
		break;
	case LUA_TBOOLEAN:
		value->boolean = lua_toboolean(L, ix);
		break;
	case LUA_TNUMBER:
		value->integer = lua_tointeger(L, ix);
		break;
	case LUA_TUSERDATA:
		value->object = lunatik_checkobject(L, ix);
		break;
	default:
		luaL_argerror(L, ix, "unsupported type");
		break;
	}
}
EXPORT_SYMBOL(lunatik_checkvalue);

static int lunatik_doclone(lua_State *L)
{
	lunatik_object_t *object = (lunatik_object_t *)lua_touserdata(L, 1);
	lunatik_cloneobject(L, object);
	return 1;
}

void lunatik_pushvalue(lua_State *L, lunatik_value_t *value)
{
	switch (value->type) {
	case LUA_TNIL:
		lua_pushnil(L);
		break;
	case LUA_TBOOLEAN:
		lua_pushboolean(L, value->boolean);
		break;
	case LUA_TNUMBER:
		lua_pushinteger(L, value->integer);
		break;
	case LUA_TUSERDATA:
		lua_pushcfunction(L, lunatik_doclone);
		lua_pushlightuserdata(L, value->object);
		if (lua_pcall(L, 1, 1, 0) != LUA_OK) {
			lunatik_putobject(value->object);
			lua_error(L);
		}
		break;
	}
}
EXPORT_SYMBOL(lunatik_pushvalue);

