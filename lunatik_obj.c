/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <lua.h>
#include <lauxlib.h>

#include "lunatik.h"

#ifdef LUNATIK_RUNTIME

#define lunatik_ismetamethod(reg)          \
	((!strncmp(reg->name, "__", 2)) ||     \
	(reg)->func == lunatik_deleteobject || \
	(reg)->func == lunatik_closeobject)

lunatik_object_t *lunatik_newobject(lua_State *L, const lunatik_class_t *class, size_t size)
{
	lunatik_object_t **pobject = lunatik_newpobject(L, 1);
	lunatik_object_t *object = lunatik_checkalloc(L, sizeof(lunatik_object_t));

	lunatik_checkclass(L, class);
	lunatik_setobject(object, class, class->sleep);
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
	lunatik_require(L, object->class->name);
	lunatik_object_t **pobject = lunatik_newpobject(L, 1);
	const lunatik_class_t *class = object->class;

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

	if (private != NULL)
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

inline static void lunatik_fixerror(lua_State *L, const char *method)
{
	if (method) {
		const char *error = lua_tostring(L, -1);
		luaL_gsub(L, error, "?", method);
		lua_remove(L, -2); /* error */
	}
	luaL_traceback(L, L, lua_tostring(L, -1), 1);
	lua_remove(L, -2); /* fixed error */
	lua_error(L);
}

static int lunatik_monitor(lua_State *L)
{
	int ret, n = lua_gettop(L);
	lunatik_object_t *object = lunatik_checkobject(L, 1);

	lua_pushvalue(L, lua_upvalueindex(1)); /* method */
	lua_insert(L, 1); /* stack: method, object, args */

	lunatik_lock(object);
	ret = lua_pcall(L, n, LUA_MULTRET, 0);
	lunatik_unlock(object);

	if (ret != LUA_OK) {
		const char *method = lua_tostring(L, lua_upvalueindex(2));
		lunatik_fixerror(L, method);
	}
	return lua_gettop(L);
}

void lunatik_monitorobject(lua_State *L, const lunatik_class_t *class)
{
	const luaL_Reg *reg;
	for (reg = class->methods; reg->name != NULL; reg++) {
		if (!lunatik_ismetamethod(reg)) {
			lua_getfield(L, -1, reg->name);
			lua_pushstring(L, reg->name);
			lua_pushcclosure(L, lunatik_monitor, 2); /* stack: mt, method, method name*/
			lua_setfield(L, -2, reg->name);
		}
	}
}
EXPORT_SYMBOL(lunatik_monitorobject);

#endif /* LUNATIK_RUNTIME */

