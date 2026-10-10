/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <lua.h>
#include <lauxlib.h>

#include "lunatik.h"
#include "lunatik_core.h"

#ifdef LUNATIK_RUNTIME

#define lunatik_iswrapped(reg)							\
	(strncmp((reg)->name, "__", 2) ?					\
		strcmp((reg)->name, "close") && strcmp((reg)->name, "stop") :	\
		!strcmp((reg)->name, "__tostring"))

lunatik_object_t *lunatik_newobject(lua_State *L, const lunatik_class_t *class, size_t size, lunatik_opt_t opt)
{
	/* SOFTIRQ runtime requires a SOFTIRQ class */
	lunatik_checkclass(L, class);
	bool monitor = lunatik_ismonitor(lunatik_inheritopt(class, opt));
	lunatik_checkmetatable(L, class, monitor);

	lunatik_object_t **pobject = lunatik_newpobject(L, 1);
	lunatik_object_t *object = lunatik_checkalloc(L, sizeof(lunatik_object_t));

	lunatik_setobject(object, class, opt);
	*pobject = object; /* before setclass exposes it to __gc */
	lunatik_setclass(L, class, monitor);
	if (lunatik_isclosing(lunatik_toruntime(L))) /* where no __gc runs */
		lunatik_holdobject(L, object);

	object->private = lunatik_isexternal(class->opt) ? NULL : lunatik_checkzalloc(L, size);
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

	lunatik_checkclass(L, class);
	if (!lunatik_hasclass(L, class)) {
		__module_get(class->owner); /* the object being cloned holds it */
		lunatik_holdmodule(L, class->owner); /* no require of this state holds what the metatables call */
		lunatik_require(L, class);
	}
	lunatik_object_t **pobject = lunatik_newpobject(L, 1);

	lunatik_setclass(L, class, lunatik_ismonitor(object->opt));
	*pobject = object;
	if (lunatik_isclosing(lunatik_toruntime(L))) {
		lunatik_getobject(object); /* the state's, which a failed hold drops */
		lunatik_holdobject(L, object);
		lunatik_putobject(object); /* the one the caller hands over or takes, which no __gc drops */
	}
}
EXPORT_SYMBOL(lunatik_cloneobject);

static inline void lunatik_releaseprivate(const lunatik_class_t *class, void *private)
{
	lunatik_release_t release = class->release;

	if (release)
		release(private);
	if (!lunatik_isexternal(class->opt))
		lunatik_free(private);
}

static void lunatik_closelocked(lunatik_object_t *object)
{
	void *private = object->private;

	object->private = NULL;
	lunatik_unlock(object);

	if (private != NULL)
		lunatik_releaseprivate(object->class, private);
}

void lunatik_closeprivate(lunatik_object_t *object)
{
	lunatik_lock(object);
	lunatik_closelocked(object);
}
EXPORT_SYMBOL(lunatik_closeprivate);

int lunatik_closekillable(lunatik_object_t *object)
{
	int ret = lunatik_lockkillable(object);

	if (ret == 0)
		lunatik_closelocked(object);
	return ret;
}

int lunatik_closeobject(lua_State *L)
{
	lunatik_object_t *object = lunatik_checkobject(L, 1);

	luaL_argcheck(L, luaL_getmetafield(L, 1, "__close") != LUA_TNIL &&
		lua_tocfunction(L, -1) == lunatik_closeobject, 1, "object of another class");
	lunatik_closeprivate(object);
	return 0;
}
EXPORT_SYMBOL(lunatik_closeobject);

static void lunatik_freeobject(lunatik_object_t *object)
{
	void *private = object->private;

	if (private != NULL)
		lunatik_releaseprivate(object->class, private);

	module_put(object->class->owner); /* release runs in the module */
	lunatik_freelock(object);
	kfree_rcu(object, rcu); /* a reader that found the object under rcu_read_lock may still read its count */
}

static void lunatik_freedeferred(struct work_struct *work)
{
	lunatik_object_t *object = container_of(work, lunatik_object_t, defer.work);

	irq_work_sync(&object->defer.irq); /* the first hop writes the item after it queues this work */
	lunatik_freeobject(object);
}

void lunatik_releaseobject(struct kref *kref)
{
	lunatik_object_t *object = container_of(kref, lunatik_object_t, kref);

	if (lunatik_isatomic()) {
		lunatik_initdefer(&object->defer, lunatik_freedeferred);
		lunatik_defer(&object->defer);
	}
	else
		lunatik_freeobject(object);
}
EXPORT_SYMBOL(lunatik_releaseobject);

bool lunatik_trygetobject(lunatik_object_t *object)
{
	return kref_get_unless_zero(&object->kref);
}
EXPORT_SYMBOL(lunatik_trygetobject);

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
	lunatik_object_t *runtime = lunatik_toruntime(L);

	lunatik_checkowner(L, object); /* the runtime's resume runs Lua that can reach this handle again */
	lua_pushvalue(L, lua_upvalueindex(1)); /* method */
	lua_insert(L, 1); /* stack: method, object, args */

	lunatik_try(L, lunatik_lockkillable, object);
	gfp_t gfp = lunatik_gfp(runtime);
	runtime->gfp = lunatik_gfp(object); /* the method allocates under the object's lock */
	int running = lua_gc(L, LUA_GCISRUNNING);
	lua_gc(L, LUA_GCSTOP);
	ret = lua_pcall(L, n, LUA_MULTRET, 0);
	lunatik_unlock(object);
	runtime->gfp = gfp;
	if (running)
		lua_gc(L, LUA_GCRESTART);

	if (ret != LUA_OK) {
		const char *method = lua_tostring(L, lua_upvalueindex(2));
		luaL_gsub(L, lua_tostring(L, -1), "?", method);
		lua_error(L);
	}
	return lua_gettop(L);
}

void lunatik_monitorobject(lua_State *L, const lunatik_class_t *class)
{
	const luaL_Reg *reg;
	for (reg = class->methods; reg->name != NULL; reg++) {
		if (lunatik_iswrapped(reg)) {
			lua_getfield(L, -1, reg->name);
			lua_pushstring(L, reg->name);
			lua_pushcclosure(L, lunatik_monitor, 2); /* stack: mt, method, method name*/
			lua_setfield(L, -2, reg->name);
		}
	}
}
EXPORT_SYMBOL(lunatik_monitorobject);

#endif /* LUNATIK_RUNTIME */

