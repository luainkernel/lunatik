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

lunatik_object_t *lunatik_newobject(lua_State *L, const lunatik_class_t *class, size_t size, lunatik_opt_t opt)
{
	lunatik_object_t **pobject = lunatik_newpobject(L, 1);
	lunatik_object_t *object = lunatik_checkalloc(L, sizeof(lunatik_object_t));

	/* SOFTIRQ runtime requires a SOFTIRQ class */
	lunatik_checkclass(L, class);

	lunatik_setobject(object, class, opt);
	lunatik_setclass(L, class, lunatik_ismonitor(object->opt));

	object->private = lunatik_isexternal(class->opt) ? NULL : lunatik_checkzalloc(L, size);

	*pobject = object;
	return object;
}
EXPORT_SYMBOL(lunatik_newobject);

lunatik_object_t *lunatik_createobject(const lunatik_class_t *class, size_t size, lunatik_opt_t opt)
{
	gfp_t gfp = lunatik_isirq(opt | class->opt) ? GFP_ATOMIC : GFP_KERNEL;
	lunatik_object_t *object = (lunatik_object_t *)kzalloc(sizeof(lunatik_object_t), gfp);

	if (object == NULL)
		return NULL;

	lunatik_setobject(object, class, opt);
	if ((object->private = kzalloc(size, gfp)) == NULL) {
		lunatik_putobject(object);
		return NULL;
	}
	return object;
}
EXPORT_SYMBOL(lunatik_createobject);


void lunatik_cloneobject(lua_State *L, lunatik_object_t *object)
{
	const lunatik_class_t *class = object->class;

	if (lunatik_issingle(object->opt))
		luaL_error(L, "'%s': %s", class->name, LUNATIK_ERR_SINGLE);

	lunatik_require(L, class->name);
	lunatik_object_t **pobject = lunatik_newpobject(L, 1);

	lunatik_checkclass(L, class);
	lunatik_setclass(L, class, lunatik_ismonitor(object->opt));
	*pobject = object;
}
EXPORT_SYMBOL(lunatik_cloneobject);

static inline void lunatik_releaseprivate(const lunatik_class_t *class, void *private)
{
	void (*release)(void *) = class->release;

	if (release)
		release(private);
	if (!lunatik_isexternal(class->opt))
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
	lua_remove(L, -2); /* fixed error */
	lua_error(L);
}

static int lunatik_monitor(lua_State *L)
{
	int ret, n = lua_gettop(L);
	lunatik_object_t *object = lunatik_checkobject(L, 1);

	lua_pushvalue(L, lua_upvalueindex(1)); /* method */
	lua_insert(L, 1); /* stack: method, object, args */

	lua_gc(L, LUA_GCSTOP);
	lunatik_lock(object);
	ret = lua_pcall(L, n, LUA_MULTRET, 0);
	lunatik_unlock(object);
	lua_gc(L, LUA_GCRESTART);

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

