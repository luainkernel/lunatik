/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include "lunatik.h"

void lunatik_freestring(struct kref *kref)
{
	kfree(container_of(kref, lunatik_string_t, kref));
}
EXPORT_SYMBOL(lunatik_freestring);

static void *lunatik_string_alloc(void *ud, void *ptr, size_t osize, size_t nsize)
{
	if (nsize == 0)
		lunatik_putstring((lunatik_string_t *)ud);
	return NULL;
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
	case LUA_TSTRING: {
		size_t len;
		const char *s = lua_tolstring(L, ix, &len);
		lunatik_string_t *str = kmalloc(sizeof(*str) + len + 1, GFP_ATOMIC);
		if (unlikely(!str))
			luaL_argerror(L, ix, "not enough memory");
		kref_init(&str->kref);
		str->len = len;
		memcpy(str->data, s, len + 1);
		value->string = str;
		break;
	}
	case LUA_TUSERDATA:
		value->object = lunatik_checkobject(L, ix);
		if (lunatik_issingle(value->object->opt))
			luaL_argerror(L, ix, LUNATIK_ERR_SINGLE);
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
	case LUA_TSTRING: {
		lunatik_string_t *s = value->string;
		lunatik_getstring(s); /* for Lua's GC; released via lunatik_string_alloc */
		lua_pushexternalstring(L, s->data, s->len, lunatik_string_alloc, s);
		break;
	}
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

