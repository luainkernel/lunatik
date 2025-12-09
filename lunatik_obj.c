/*
* SPDX-FileCopyrightText: (c) 2023-2024 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
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

	lunatik_checkclass(L, class);
	lunatik_setobject(object, class, lunatik_class_issleepable(class));
	lunatik_setclass(L, class);

	object->private = class->pointer ? NULL : lunatik_checkalloc(L, size);

	*pobject = object;
	return object;
}
EXPORT_SYMBOL(lunatik_newobject);

lunatik_object_t *lunatik_createobject(const lunatik_class_t *class, size_t size, bool sleep)
{
	gfp_t gfp = sleep ? GFP_KERNEL : GFP_ATOMIC;
	lunatik_object_t *object = (lunatik_object_t *)kmalloc(sizeof(lunatik_object_t), gfp);

	if (object == NULL)
		return NULL;

	lunatik_setobject(object, class, sleep);
	if ((object->private = kmalloc(size, gfp)) == NULL) {
		lunatik_putobject(object);
		return NULL;
	}
	return object;
}
EXPORT_SYMBOL(lunatik_createobject);

lunatik_object_t **lunatik_checkpobject(lua_State *L, int ix)
{
	lunatik_object_t **pobject;
	lunatik_class_t *class= lunatik_getclass(L, ix);

	luaL_argcheck(L, class != NULL, ix, "object expected");
	pobject = (lunatik_object_t **)luaL_checkudata(L, ix, class->name);
	lunatik_argchecknull(L, *pobject, ix);
	return pobject;
}
EXPORT_SYMBOL(lunatik_checkpobject);

void lunatik_cloneobject(lua_State *L, lunatik_object_t *object)
{
	const lunatik_class_t *class = object->class;

	if (class->flags & LUNATIK_CLASS_NOSHARE)
		luaL_error(L, "%s objects cannot be shared across runtimes",class->name);

	lunatik_require(L, object->class->name);
	lunatik_object_t **pobject = lunatik_newpobject(L, 1);

	lunatik_checkclass(L, class);
	lunatik_setclass(L, class);
	*pobject = object;
}
EXPORT_SYMBOL(lunatik_cloneobject);

static inline void lunatik_releaseprivate(const lunatik_class_t *class, void *private)
{
	void (*release)(void *) = class->release;

	if (release)
		release(private);
	if (!class->pointer)
		lunatik_free(private);
}

int lunatik_closeobject(lua_State *L)
{
	lunatik_object_t *object = lunatik_checkobject(L, 1);
	void *private;

	lunatik_lock(object);
	private = object->private;
	object->private = NULL;
	lunatik_unlock(object);

	lunatik_argchecknull(L, private, 1);
	lunatik_releaseprivate(object->class, private);
	return 0;
}
EXPORT_SYMBOL(lunatik_closeobject);

void lunatik_releaseobject(struct kref *kref)
{
	lunatik_object_t *object = container_of(kref, lunatik_object_t, kref);
	void *private = object->private;

	if (private != NULL)
		lunatik_releaseprivate(object->class, private);

	lunatik_freelock(object);
	kfree(object);
}
EXPORT_SYMBOL(lunatik_releaseobject);

int lunatik_deleteobject(lua_State *L)
{
	lunatik_object_t **pobject = lunatik_checkpobject(L, 1);
	lunatik_object_t *object = *pobject;

	BUG_ON(!object);
	lunatik_putobject(object);
	*pobject = NULL;
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
	if (lua_rawget(L, 2) == LUA_TFUNCTION) {
		lua_CFunction method = lua_tocfunction(L, -1);

		if (likely(method != lunatik_deleteobject && method != lunatik_closeobject))
			lua_pushcclosure(L, lunatik_monitor, 1);
	}
	return 1;
}
EXPORT_SYMBOL(lunatik_monitorobject);

#endif /* LUNATIK_RUNTIME */

