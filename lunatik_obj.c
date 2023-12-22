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
#include <lua.h>
#include <lauxlib.h>

#include "lunatik.h"

#ifdef LUNATIK_RUNTIME

lunatik_object_t *lunatik_newobject(lua_State *L, const lunatik_class_t *class, size_t size)
{
	lunatik_object_t **pobject = lunatik_newpobject(L, 1);
	lunatik_object_t *object = lunatik_checkalloc(L, sizeof(lunatik_object_t));

	lunatik_setobject(L, object, class, class->sleep);
	lunatik_setclass(L, class);

	object->private = class->pointer ? NULL : lunatik_checkalloc(L, size);

	*pobject = object;
	return object;
}
EXPORT_SYMBOL(lunatik_newobject);

lunatik_object_t **lunatik_checkpobject(lua_State *L, int ix)
{
	lunatik_object_t **pobject;
	lunatik_class_t *class;

	luaL_argcheck(L, lua_isuserdata(L, ix) && lua_getiuservalue(L, ix, 1) != LUA_TNONE &&
		(class = (lunatik_class_t *)lua_touserdata(L, -1)) != NULL, ix, "object expected");
	pobject = (lunatik_object_t **)luaL_checkudata(L, ix, class->name);
	lunatik_checknull(L, *pobject, ix);
	lua_pop(L, 1); /* class */
	return pobject;
}
EXPORT_SYMBOL(lunatik_checkpobject);

void lunatik_cloneobject(lua_State *L, lunatik_object_t *object)
{
	lunatik_object_t **pobject = lunatik_newpobject(L, 1);
	const lunatik_class_t *class = object->class;

	lunatik_setclass(L, class);
	*pobject = object;
}
EXPORT_SYMBOL(lunatik_cloneobject);

static inline void lunatik_releaseprivate(lunatik_object_t *object)
{
	const lunatik_class_t *class = object->class;
	void (*release)(void *) = class->release;

	if (release)
		release(object->private);
	if (!class->pointer)
		lunatik_free(object->private);
}

int lunatik_closeobject(lua_State *L)
{
	lunatik_object_t *object = lunatik_checkobject(L, 1);

	lunatik_checknull(L, object->private, 1);
	lunatik_releaseprivate(object);
	object->private = NULL;
	return 0;
}
EXPORT_SYMBOL(lunatik_closeobject);

void lunatik_releaseobject(struct kref *kref)
{
	lunatik_object_t *object = container_of(kref, lunatik_object_t, kref);

	if (object->private != NULL)
		lunatik_releaseprivate(object);

	lunatik_freelock(object);
	kfree(object);
}
EXPORT_SYMBOL(lunatik_releaseobject);

int lunatik_deleteobject(lua_State *L)
{
	lunatik_object_t **pobject = lunatik_checkpobject(L, 1);
	lunatik_object_t *object = *pobject;

	if (object != NULL) {
		lunatik_putobject(object);
		*pobject = NULL;
	}
	return 0;
}
EXPORT_SYMBOL(lunatik_deleteobject);

static int lunatik_monitor(lua_State *L)
{
	int ret, n = lua_gettop(L);
	lunatik_object_t *object = lunatik_checkobject(L, 1);

	lua_pushvalue(L, lua_upvalueindex(1)); /* method */
	lua_insert(L, 1); /* stack: method, object, args */

	lunatik_lock(object);
	ret = lua_pcall(L, n, LUA_MULTRET, 0);
	lunatik_unlock(object);

	if (ret != LUA_OK)
		lua_error(L);
	return lua_gettop(L);
}

int lunatik_monitorobject(lua_State *L)
{
	lua_getmetatable(L, 1);
	lua_insert(L, 2); /* stack: object, metatable, key */
	if (lua_rawget(L, 2) == LUA_TFUNCTION && lua_tocfunction(L, -1) != lunatik_deleteobject)
		lua_pushcclosure(L, lunatik_monitor, 1);
	return 1;
}
EXPORT_SYMBOL(lunatik_monitorobject);

#endif /* LUNATIK_RUNTIME */

