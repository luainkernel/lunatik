/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef lunatik_h
#define lunatik_h

#include <linux/mutex.h>
#include <linux/spinlock.h>
#include <linux/slab.h>
#include <linux/kref.h>

#include <lua.h>
#include <lauxlib.h>

#define LUNATIK_VERSION	"Lunatik 3.6"

#define lunatik_locker(o, mutex_op, spin_op)	\
do {						\
	if ((o)->sleep)				\
		mutex_op(&(o)->mutex);		\
	else					\
		spin_op(&(o)->spin);		\
} while(0)

#define lunatik_newlock(o)	lunatik_locker((o), mutex_init, spin_lock_init);
#define lunatik_freelock(o)	lunatik_locker((o), mutex_destroy, (void));
#define lunatik_lock(o)		lunatik_locker((o), mutex_lock, spin_lock_bh)
#define lunatik_unlock(o)	lunatik_locker((o), mutex_unlock, spin_unlock_bh)

#define lunatik_toruntime(L)	(*(lunatik_object_t **)lua_getextraspace(L))

#define lunatik_cannotsleep(L, s)	((s) && !lunatik_toruntime(L)->sleep)
#define lunatik_getstate(runtime)	((lua_State *)runtime->private)

static inline bool lunatik_isready(lua_State *L)
{
	bool ready;
	lua_rawgetp(L, LUA_REGISTRYINDEX, L);
	ready = lua_toboolean(L, -1);
	lua_pop(L, 1);
	return ready;
}

#define lunatik_handle(runtime, handler, ret, ...)	\
do {							\
	lua_State *L = lunatik_getstate(runtime);	\
	int n = lua_gettop(L);				\
	ret = handler(L, ## __VA_ARGS__);		\
	lua_settop(L, n);				\
} while(0)

#define lunatik_run(runtime, handler, ret, ...)				\
do {									\
	lunatik_lock(runtime);						\
	if (unlikely(!lunatik_getstate(runtime)))			\
		ret = -ENXIO;						\
	else								\
		lunatik_handle(runtime, handler, ret, ## __VA_ARGS__);	\
	lunatik_unlock(runtime);					\
} while(0)

typedef struct lunatik_reg_s {
	const char *name;
	lua_Integer value;
} lunatik_reg_t;

typedef struct lunatik_namespace_s {
	const char *name;
	const lunatik_reg_t *reg;
} lunatik_namespace_t;

typedef struct lunatik_class_s {
	const char *name;
	const luaL_Reg *methods;
	void (*release)(void *);
	bool sleep;
	bool pointer;
} lunatik_class_t;

typedef struct lunatik_object_s {
	struct kref kref;
	const lunatik_class_t *class;
	void *private;
	union {
		struct mutex mutex;
		spinlock_t spin;
	};
	bool sleep;
	gfp_t gfp;
} lunatik_object_t;

extern lunatik_object_t *lunatik_env;

static inline int lunatik_trylock(lunatik_object_t *object)
{
	return object->sleep ? mutex_trylock(&object->mutex) : spin_trylock_bh(&object->spin);
}

int lunatik_runtime(lunatik_object_t **pruntime, const char *script, bool sleep);
int lunatik_stop(lunatik_object_t *runtime);

static inline void *lunatik_realloc(lua_State *L, void *ptr, size_t size)
{
	void *ud = NULL;
	lua_Alloc alloc = lua_getallocf(L, &ud);
	return alloc(ud, ptr, LUA_TNONE, size);
}

#define lunatik_malloc(L, s)	lunatik_realloc((L), NULL, (s))
#define lunatik_free(p)		kfree(p)
#define lunatik_gfp(runtime)	((runtime)->gfp)

static inline void *lunatik_checknull(lua_State *L, void *ptr)
{
	if (ptr == NULL)
		luaL_error(L, "not enough memory");
	return ptr;
}

#define lunatik_checkalloc(L, s)	(lunatik_checknull((L), lunatik_malloc((L), (s))))

static inline void lunatik_checkfield(lua_State *L, int idx, const char *field, int type)
{
	int _type = lua_getfield(L, idx, field);
	if (_type != type)
		luaL_error(L, "bad field '%s' (%s expected, got %s)", field,
			lua_typename(L, type), lua_typename(L, _type));
}

static inline lunatik_object_t *lunatik_checkruntime(lua_State *L, bool sleep)
{
	lunatik_object_t *runtime = lunatik_toruntime(L);
	if (runtime->sleep != sleep)
		luaL_error(L, "cannot use %ssleepable runtime in this context", runtime->sleep ? "" : "non-");
	return runtime;
}

#define lunatik_setruntime(L, libname, priv)	((priv)->runtime = lunatik_checkruntime((L), lua##libname##_class.sleep))

static inline void lunatik_checkclass(lua_State *L, const lunatik_class_t *class)
{
	if (lunatik_cannotsleep(L, class->sleep))
		luaL_error(L, "cannot use '%s' class on non-sleepable runtime", class->name);
}

static inline void lunatik_setclass(lua_State *L, const lunatik_class_t *class)
{
	if (luaL_getmetatable(L, class->name) == LUA_TNIL)
		luaL_error(L, "metatable not found (%s)", class->name);
	lua_setmetatable(L, -2);
	lua_pushlightuserdata(L, (void *)class);
	lua_setiuservalue(L, -2, 1); /* pop class */
}

static inline void lunatik_setobject(lunatik_object_t *object, const lunatik_class_t *class, bool sleep)
{
	kref_init(&object->kref);
	object->private = NULL;
	object->class = class;
	object->sleep = sleep;
	object->gfp = sleep ? GFP_KERNEL : GFP_ATOMIC;
	lunatik_newlock(object);
}

lunatik_object_t *lunatik_newobject(lua_State *L, const lunatik_class_t *class, size_t size);
lunatik_object_t *lunatik_createobject(const lunatik_class_t *class, size_t size, bool sleep);
lunatik_object_t **lunatik_checkpobject(lua_State *L, int ix);
void lunatik_cloneobject(lua_State *L, lunatik_object_t *object);
void lunatik_releaseobject(struct kref *kref);
int lunatik_closeobject(lua_State *L);
int lunatik_deleteobject(lua_State *L);
int lunatik_monitorobject(lua_State *L);

#define LUNATIK_ERR_NULLPTR	"null-pointer dereference"

#define lunatik_newpobject(L, n)	(lunatik_object_t **)lua_newuserdatauv((L), sizeof(lunatik_object_t *), (n))
#define lunatik_argchecknull(L, o, i)	luaL_argcheck((L), (o) != NULL, (i), LUNATIK_ERR_NULLPTR)
#define lunatik_checkobject(L, i)	(*lunatik_checkpobject((L), (i)))
#define lunatik_toobject(L, i)		(*(lunatik_object_t **)lua_touserdata((L), (i)))
#define lunatik_getobject(o)		kref_get(&(o)->kref)
#define lunatik_putobject(o)		kref_put(&(o)->kref, lunatik_releaseobject)

static inline void lunatik_require(lua_State *L, const char *libname)
{
	lua_getglobal(L, "require");
	lua_pushstring(L, libname);
	lua_call(L, 1, 0);
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

static inline void lunatik_newclass(lua_State *L, const lunatik_class_t *class)
{
	luaL_newmetatable(L, class->name); /* mt = {} */
	luaL_setfuncs(L, class->methods, 0);
	if (!lunatik_hasindex(L, -1)) {
		lua_pushvalue(L, -1);  /* push mt */
		lua_setfield(L, -2, "__index");  /* mt.__index = mt */
	}
	lua_pop(L, 1);  /* pop mt */
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

#define lunatik_isobject(L, ix)	(lunatik_getclass((L), (ix)) != NULL)

static inline lunatik_object_t *lunatik_testobject(lua_State *L, int ix)
{
	lunatik_object_t **pobject;
	lunatik_class_t *class = lunatik_getclass(L, ix);
	return class != NULL && (pobject = luaL_testudata(L, ix, class->name)) != NULL ? *pobject : NULL;
}

static void inline lunatik_newnamespaces(lua_State *L, const lunatik_namespace_t *namespaces)
{
	for (; namespaces->name; namespaces++) {
		const lunatik_reg_t *reg;
		lua_newtable(L); /* namespace = {} */
		for (reg = namespaces->reg; reg->name; reg++) {
			lua_pushinteger(L, reg->value);
			lua_setfield(L, -2, reg->name); /* namespace[name] = value */
		}
		lua_setfield(L, -2, namespaces->name); /* lib.namespace = namespace */
	}
}

#define LUNATIK_NEWLIB(libname, funcs, class, namespaces)			\
int luaopen_##libname(lua_State *L);						\
int luaopen_##libname(lua_State *L)						\
{										\
	const lunatik_class_t *cls = class; /* avoid -Waddress */		\
	const lunatik_namespace_t *nss = namespaces; /* avoid -Waddress */	\
	luaL_newlib(L, funcs);							\
	if (cls) {								\
		lunatik_checkclass(L, cls);					\
		lunatik_newclass(L, cls);					\
	}									\
	if (nss)								\
		lunatik_newnamespaces(L, nss);					\
	return 1;								\
}										\
EXPORT_SYMBOL_GPL(luaopen_##libname)

#define LUNATIK_LIB(libname)		\
int luaopen_##libname(lua_State *L);	\

#define LUNATIK_OBJECTCHECKER(checker, T)			\
static inline T checker(lua_State *L, int ix)			\
{								\
	lunatik_object_t *object = lunatik_checkobject(L, ix);	\
	return (T)object->private;				\
}

#define LUNATIK_PRIVATECHECKER(checker, T)			\
static inline T checker(lua_State *L, int ix)			\
{								\
	T private = (T)lunatik_toobject(L, ix)->private;	\
	/* avoid use-after-free */				\
	lunatik_argchecknull(L, private, ix);			\
	return private;						\
}

#define lunatik_getregistry(L, key)	lua_rawgetp((L), LUA_REGISTRYINDEX, (key))

static inline void lunatik_setregistry(lua_State *L, int ix, void *key)
{
	lua_pushvalue(L, ix);
	lua_rawsetp(L, LUA_REGISTRYINDEX, key); /* pop value */
}

static inline void lunatik_registerobject(lua_State *L, int ix, lunatik_object_t *object)
{
	lunatik_setregistry(L, ix, object->private); /* private */
	lunatik_setregistry(L, -1, object); /* prevent object from being GC'ed (unless stopped) */
}

static inline void lunatik_unregisterobject(lua_State *L, lunatik_object_t *object)
{
	lua_pushnil(L);
	lunatik_setregistry(L, -1, object->private); /* remove private */
	lunatik_setregistry(L, -1, object); /* remove object, now it might be GC'ed */
	lua_pop(L, 1); /* pop nil */
}

#endif

