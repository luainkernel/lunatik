/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include "lunatik.h"

static void lunatik_releasestring(struct kref *kref)
{
	lunatik_string_t *s = container_of(kref, lunatik_string_t, kref);
	kfree(s);
}

static inline void lunatik_getstring(lunatik_value_t *value)
{
	kref_get(&value->string->kref);
}

static inline void lunatik_putstring(lunatik_value_t *value)
{
	kref_put(&value->string->kref, lunatik_releasestring);
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
	case LUA_TUSERDATA:
		value->object = lunatik_checkobject(L, ix);
		if (!value->object->clone)
			luaL_argerror(L, ix, "cannot share non-clonable object");
		break;
	case LUA_TSTRING: {
		size_t len;
		const char *str = lua_tolstring(L, ix, &len);
		lunatik_string_t *s = kmalloc(sizeof(lunatik_string_t) + len + 1, GFP_ATOMIC);
		if (!s)
			luaL_error(L, "not enough memory");
		kref_init(&s->kref);
		s->len = len;
		memcpy(s->str, str, len + 1);
		value->string = s;
		break;
	}
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
	case LUA_TSTRING:
		lunatik_pushstring(L, value->string->str, value->string->len);
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

