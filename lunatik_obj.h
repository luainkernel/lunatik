/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef lunatik_obj_h
#define lunatik_obj_h

#include <linux/mutex.h>
#include <linux/spinlock.h>
#include <linux/slab.h>
#include <linux/kref.h>

#include <lua.h>
#include <lauxlib.h>

typedef u8 __bitwise lunatik_opt_t;
#define LUNATIK_OPT_SOFTIRQ	((__force lunatik_opt_t)(1U << 0))
#define LUNATIK_OPT_MONITOR	((__force lunatik_opt_t)(1U << 1))
#define LUNATIK_OPT_SINGLE	((__force lunatik_opt_t)(1U << 2))
#define LUNATIK_OPT_EXTERNAL	((__force lunatik_opt_t)(1U << 3))
#define LUNATIK_OPT_NONE	((__force lunatik_opt_t)0)

#define lunatik_issoftirq(opt)		((opt) & LUNATIK_OPT_SOFTIRQ)
#define lunatik_ismonitor(opt)		((opt) & LUNATIK_OPT_MONITOR)
#define lunatik_issingle(opt)		((opt) & LUNATIK_OPT_SINGLE)
#define lunatik_isexternal(opt)		((opt) & LUNATIK_OPT_EXTERNAL)

typedef struct lunatik_class_s {
	const char *name;
	const luaL_Reg *methods;
	void (*release)(void *);
	lunatik_opt_t opt;
} lunatik_class_t;

typedef struct lunatik_object_s {
	struct kref kref;
	const lunatik_class_t *class;
	void *private;
	union {
		struct mutex mutex;
		spinlock_t spin;
	};
	lunatik_opt_t opt;
	gfp_t gfp;
} lunatik_object_t;

#define lunatik_locker(o, mutex_op, spin_op)	\
do {						\
	if (!lunatik_issoftirq((o)->opt))	\
		mutex_op(&(o)->mutex);		\
	else					\
		spin_op(&(o)->spin);		\
} while (0)

#define lunatik_newlock(o)	lunatik_locker((o), mutex_init, spin_lock_init);
#define lunatik_freelock(o)	lunatik_locker((o), mutex_destroy, (void));
#define lunatik_lock(o)		lunatik_locker((o), mutex_lock, spin_lock_bh)
#define lunatik_unlock(o)	lunatik_locker((o), mutex_unlock, spin_unlock_bh)

#define lunatik_toruntime(L)	(*(lunatik_object_t **)lua_getextraspace(L))
#define lunatik_cannotsleep(L, s)	((s) && lunatik_issoftirq(lunatik_toruntime(L)->opt))
#define lunatik_getstate(runtime)	((lua_State *)runtime->private)

#define LUNATIK_ERR_NULLPTR	"null pointer dereference"
#define LUNATIK_ERR_SINGLE	"cannot share SINGLE object"
#define LUNATIK_ERR_METATABLE	"metatable not found"
#define LUNATIK_ERR_CONTEXT	"process-context class in interrupt-context runtime"
#define LUNATIK_ERR_RUNTIME	"runtime context mismatch"

#define lunatik_newpobject(L, n)	(lunatik_object_t **)lua_newuserdatauv((L), sizeof(lunatik_object_t *), (n))
#define lunatik_argchecknull(L, o, i)	luaL_argcheck((L), (o) != NULL, (i), LUNATIK_ERR_NULLPTR)
#define lunatik_checkobject(L, i)	(*lunatik_checkpobject((L), (i)))
#define lunatik_toobject(L, i)		(*(lunatik_object_t **)lua_touserdata((L), (i)))
#define lunatik_getobject(o)		kref_get(&(o)->kref)
#define lunatik_putobject(o)		kref_put(&(o)->kref, lunatik_releaseobject)
#define lunatik_monitormt(class, monitor)	((monitor) ? (void *)&(class)->opt : (void *)(class))

#define LUNATIK_OBJECTCHECKER(checker, T)			\
static inline T checker(lua_State *L, int ix)			\
{								\
	lunatik_object_t *object = lunatik_checkobject(L, ix);	\
	return (T)object->private;				\
}

#define LUNATIK_PRIVATECHECKER(checker, T, ...)			\
static inline T checker(lua_State *L, int ix)			\
{								\
	T private = (T)lunatik_toobject(L, ix)->private;	\
	/* avoid use-after-free */				\
	lunatik_argchecknull(L, private, ix);			\
	__VA_ARGS__						\
	return private;						\
}

static inline int lunatik_trylock(lunatik_object_t *object)
{
	return unlikely(lunatik_ismonitor(object->opt)) ?
		(lunatik_issoftirq(object->opt) ? spin_trylock(&object->spin) : mutex_trylock(&object->mutex)) : 1;
}

static inline void lunatik_setobject(lunatik_object_t *object, const lunatik_class_t *class, lunatik_opt_t opt)
{
	lunatik_opt_t inherited = opt | class->opt;
	kref_init(&object->kref);
	object->private = NULL;
	object->class = class;
	object->opt = lunatik_issingle(opt) ? inherited & ~LUNATIK_OPT_MONITOR : inherited;
	object->gfp = lunatik_issoftirq(object->opt) ? GFP_ATOMIC : GFP_KERNEL;
	lunatik_newlock(object);
}

lunatik_object_t *lunatik_newobject(lua_State *L, const lunatik_class_t *class, size_t size, lunatik_opt_t opt);
lunatik_object_t *lunatik_createobject(const lunatik_class_t *class, size_t size, lunatik_opt_t opt);
void lunatik_cloneobject(lua_State *L, lunatik_object_t *object);
void lunatik_releaseobject(struct kref *kref);
int lunatik_closeobject(lua_State *L);
int lunatik_deleteobject(lua_State *L);
void lunatik_monitorobject(lua_State *L, const lunatik_class_t *class);

static inline lunatik_object_t *lunatik_checkruntime(lua_State *L, lunatik_opt_t opt)
{
	lunatik_object_t *runtime = lunatik_toruntime(L);
	if (lunatik_issoftirq(runtime->opt) != lunatik_issoftirq(opt))
		luaL_error(L, LUNATIK_ERR_RUNTIME);
	return runtime;
}

#define lunatik_setruntime(L, libname, priv)	((priv)->runtime = lunatik_checkruntime((L), lua##libname##_class.opt))

static inline void lunatik_checkclass(lua_State *L, const lunatik_class_t *class)
{
	if (lunatik_cannotsleep(L, !lunatik_issoftirq(class->opt)))
		luaL_error(L, "'%s': %s", class->name, LUNATIK_ERR_CONTEXT);
}

static inline void lunatik_setclass(lua_State *L, const lunatik_class_t *class, bool monitor)
{
	lua_pushlightuserdata(L, lunatik_monitormt(class, monitor));
	if (lua_rawget(L, LUA_REGISTRYINDEX) == LUA_TNIL)
		luaL_error(L, "'%s': %s", class->name, LUNATIK_ERR_METATABLE);
	lua_setmetatable(L, -2);
	lua_pushlightuserdata(L, (void *)class);
	lua_setiuservalue(L, -2, 1); /* pop class */
}

static inline void lunatik_pushobject(lua_State *L, lunatik_object_t *object)
{
	lunatik_cloneobject(L, object);
	lunatik_getobject(object);
}

static inline bool lunatik_hasindex(lua_State *L, int index)
{
	bool hasindex = lua_getfield(L, index, "__index") != LUA_TNIL;
	lua_pop(L, 1);
	return hasindex;
}

static inline void lunatik_newclass(lua_State *L, const lunatik_class_t *class, bool monitored)
{
	lua_pushlightuserdata(L, lunatik_monitormt(class, monitored));
	lua_newtable(L); /* mt = {} */
	luaL_setfuncs(L, class->methods, 0);
	if (monitored)
		lunatik_monitorobject(L, class);
	if (!lunatik_hasindex(L, -1)) {
		lua_pushvalue(L, -1);  /* push mt */
		lua_setfield(L, -2, "__index");  /* mt.__index = mt */
	}
	lua_rawset(L, LUA_REGISTRYINDEX); /* registry[key] = mt */
}

static inline lunatik_class_t *lunatik_getclass(lua_State *L, int ix)
{
	if (lua_isuserdata(L, ix) && lua_getiuservalue(L, ix, 1) != LUA_TNONE) {
		lunatik_class_t *class = (lunatik_class_t *)lua_touserdata(L, -1);
		lua_pop(L, 1); /* class */
		return class;
	}
	return NULL;
}

static inline bool lunatik_isobject(lua_State *L, int ix, lunatik_object_t *object)
{
	lunatik_class_t *class = lunatik_getclass(L, ix);
	return class && object && object->class == class;
}

static inline lunatik_object_t **lunatik_testobject(lua_State *L, int ix)
{
	lunatik_object_t **pobject = (lunatik_object_t **)lua_touserdata(L, ix);
	return (pobject && lunatik_isobject(L, ix, *pobject)) ? pobject : NULL;
}

static inline lunatik_object_t **lunatik_checkpobject(lua_State *L, int ix)
{
	lunatik_object_t **pobject = lunatik_testobject(L, ix);
	luaL_argcheck(L, pobject, ix, "invalid object");
	return pobject;
}

static inline void lunatik_registerobject(lua_State *L, int ix, lunatik_object_t *object)
{
	lunatik_register(L, ix, object->private); /* private */
	lunatik_register(L, -1, object); /* prevent object from being GC'ed (unless stopped) */
}

static inline void lunatik_unregisterobject(lua_State *L, lunatik_object_t *object)
{
	lunatik_unregister(L, object->private); /* remove private */
	lunatik_unregister(L, object); /* remove object, now it might be GC'ed */
}

#endif /* lunatik_obj_h */