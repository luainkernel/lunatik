/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include "lunatik.h"
#include "lunatik_core.h"

void lunatik_freestring(struct kref *kref)
{
	lunatik_string_t *str = container_of(kref, lunatik_string_t, kref);
	kvfree_rcu(str, rcu); /* a reader that found the string under rcu_read_lock may still read its count */
}
EXPORT_SYMBOL(lunatik_freestring);

static inline lunatik_string_t *lunatik_newstring(lua_State *L, int ix)
{
	size_t len;
	const char *s = luaL_checklstring(L, ix, &len);
	lunatik_string_t *str = lunatik_checkalloc(L, struct_size(str, data, len + 1));
	kref_init(&str->kref);
	str->len = len;
	memcpy(str->data, s, len + 1);
	return str;
}

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
	case LUA_TSTRING:
		value->string = lunatik_newstring(L, ix);
		break;
	case LUA_TUSERDATA:
		value->object = lunatik_checkshareable(L, ix);
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
	case LUA_TSTRING: /* Lua puts the value's reference when it frees the string, a failed push's included */
		lua_pushexternalstring(L, value->string->data, value->string->len, lunatik_unholdstring, value->string);
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

