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
#include <linux/version.h>

#include <lua.h>
#include <lauxlib.h>

#define LUNATIK_VERSION	"Lunatik 4.2"

typedef u8 __bitwise lunatik_opt_t;
#define LUNATIK_OPT_IRQ		((__force lunatik_opt_t)(1U << 0))
#define LUNATIK_OPT_SOFTIRQ	(LUNATIK_OPT_IRQ | ((__force lunatik_opt_t)(1U << 1))) /* netfilter, XDP */
#define LUNATIK_OPT_HARDIRQ	(LUNATIK_OPT_IRQ | ((__force lunatik_opt_t)(1U << 2))) /* kprobes */
#define LUNATIK_OPT_MONITOR	((__force lunatik_opt_t)(1U << 3))
#define LUNATIK_OPT_SINGLE	((__force lunatik_opt_t)(1U << 4))
#define LUNATIK_OPT_EXTERNAL	((__force lunatik_opt_t)(1U << 5))
#define LUNATIK_OPT_NONE	((__force lunatik_opt_t)0)

#define lunatik_isirq(opt)		((opt) & LUNATIK_OPT_IRQ)
#define lunatik_issoftirq(opt)		((opt) & ((__force lunatik_opt_t)(1U << 1)))
#define lunatik_ishardirq(opt)		((opt) & ((__force lunatik_opt_t)(1U << 2)))
#define lunatik_ismonitor(opt)		((opt) & LUNATIK_OPT_MONITOR)
#define lunatik_issingle(opt)		((opt) & LUNATIK_OPT_SINGLE)
#define lunatik_isexternal(opt)		((opt) & LUNATIK_OPT_EXTERNAL)

#define lunatik_locker(o, mutex_op, softirq_op, hardirq_op, ...)	\
do {									\
	if (!lunatik_isirq((o)->opt))					\
		mutex_op(&(o)->mutex);					\
	else if (lunatik_ishardirq((o)->opt))				\
		hardirq_op(&(o)->spin, ##__VA_ARGS__);			\
	else								\
		softirq_op(&(o)->spin);					\
} while (0)

#define lunatik_newlock(o)   lunatik_locker((o), mutex_init, spin_lock_init, spin_lock_init);
#define lunatik_freelock(o)  lunatik_locker((o), mutex_destroy, (void), (void));
#define lunatik_lock(o)      lunatik_locker((o), mutex_lock, spin_lock_bh, spin_lock_irqsave, (o)->flags)
#define lunatik_unlock(o)    lunatik_locker((o), mutex_unlock, spin_unlock_bh, spin_unlock_irqrestore, (o)->flags)

#define lunatik_toruntime(L)	(*(lunatik_object_t **)lua_getextraspace(L))

#define lunatik_cannotsleep(L, s)	((s) && lunatik_isirq(lunatik_toruntime(L)->opt))
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
} while (0)

#define lunatik_run(runtime, handler, ret, ...)				\
do {									\
	lunatik_lock(runtime);						\
	if (unlikely(!lunatik_getstate(runtime)))			\
		ret = -ENXIO;						\
	else								\
		lunatik_handle(runtime, handler, ret, ## __VA_ARGS__);	\
	lunatik_unlock(runtime);					\
} while(0)

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
	unsigned long flags;
} lunatik_object_t;

extern lunatik_object_t *lunatik_env;

static inline int lunatik_trylock(lunatik_object_t *object)
{
	if (likely(!lunatik_ismonitor(object->opt)))
		return 1;
	if (lunatik_issoftirq(object->opt))
		return spin_trylock(&object->spin);
	if (lunatik_isirq(object->opt))
		return spin_trylock_irqsave(&object->spin, object->flags);
	return mutex_trylock(&object->mutex);
}

int lunatik_runtime(lunatik_object_t **pruntime, const char *script, lunatik_opt_t opt);
int lunatik_stop(lunatik_object_t *runtime);

static inline int lunatik_nop(lua_State *L)
{
	return 0;
}

#define LUNATIK_ALLOC(L, a, u)	void *u = NULL; lua_Alloc a = lua_getallocf(L, &u)
static inline const char *lunatik_pushstring(lua_State *L, char *s, size_t len)
{
	LUNATIK_ALLOC(L, alloc, ud);
	s[len] = '\0';
	return lua_pushexternalstring(L, s, len, alloc, ud);
}

static inline void *lunatik_realloc(lua_State *L, void *ptr, size_t size)
{
	LUNATIK_ALLOC(L, alloc, ud);
	return alloc(ud, ptr, LUA_TNONE, size);
}

#define lunatik_malloc(L, s)	lunatik_realloc((L), NULL, (s))
#define lunatik_free(p)		kfree(p)
#define lunatik_gfp(runtime)	((runtime)->gfp)

#define lunatik_enomem(L)	luaL_error((L), "not enough memory")

static inline void *lunatik_checknull(lua_State *L, void *ptr)
{
	if (ptr == NULL)
		lunatik_enomem(L);
	return ptr;
}

#define lunatik_checkalloc(L, s)	(lunatik_checknull((L), lunatik_malloc((L), (s))))
#define lunatik_checkzalloc(L, s)	(memset(lunatik_checkalloc((L), (s)), 0, (s)))

void lunatik_pusherrname(lua_State *L, int err);

static inline void lunatik_throw(lua_State *L, int ret)
{
	lunatik_pusherrname(L, ret);
	lua_error(L);
}

#define lunatik_tryret(L, ret, op, ...)		\
do {						\
	if ((ret = op(__VA_ARGS__)) < 0)	\
		lunatik_throw(L, ret);		\
} while (0)

#define lunatik_try(L, op, ...)				\
do {							\
	int ret;					\
	lunatik_tryret(L, ret, op, __VA_ARGS__);	\
} while (0)

static inline void lunatik_checkfield(lua_State *L, int idx, const char *field, int type)
{
	int _type = lua_getfield(L, idx, field);
	if (_type != type)
		luaL_error(L, "bad field '%s' (%s expected, got %s)", field,
			lua_typename(L, type), lua_typename(L, _type));
}

#define LUNATIK_ERR_NULLPTR	"null pointer dereference"
#define LUNATIK_ERR_SINGLE	"cannot share SINGLE object"
#define LUNATIK_ERR_METATABLE	"metatable not found"
#define LUNATIK_ERR_CONTEXT	"process-context class in interrupt-context runtime"
#define LUNATIK_ERR_RUNTIME	"runtime context mismatch"

#define lunatik_context(opt)	((opt) & (LUNATIK_OPT_SOFTIRQ | LUNATIK_OPT_HARDIRQ))

static inline lunatik_object_t *lunatik_checkruntime(lua_State *L, lunatik_opt_t opt)
{
	lunatik_object_t *runtime = lunatik_toruntime(L);
	if (lunatik_context(runtime->opt) != lunatik_context(opt))
		luaL_error(L, LUNATIK_ERR_RUNTIME);
	return runtime;
}

#define lunatik_setruntime(L, libname, priv)	((priv)->runtime = lunatik_checkruntime((L), lua##libname##_class.opt))
#define lunatik_monitormt(class, monitor)	((monitor) ? (void *)&(class)->opt : (void *)(class))

static inline void lunatik_checkclass(lua_State *L, const lunatik_class_t *class)
{
	if (lunatik_cannotsleep(L, !lunatik_isirq(class->opt)))
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

static inline void lunatik_setobject(lunatik_object_t *object, const lunatik_class_t *class, lunatik_opt_t opt)
{
	lunatik_opt_t inherited = opt | class->opt;
	kref_init(&object->kref);
	object->private = NULL;
	object->class = class;
	object->opt = lunatik_issingle(opt) ? inherited & ~LUNATIK_OPT_MONITOR : inherited;
	object->gfp = lunatik_isirq(object->opt) ? GFP_ATOMIC : GFP_KERNEL;
	lunatik_newlock(object);
}

lunatik_object_t *lunatik_newobject(lua_State *L, const lunatik_class_t *class, size_t size, lunatik_opt_t opt);
lunatik_object_t *lunatik_createobject(const lunatik_class_t *class, size_t size, lunatik_opt_t opt);
void lunatik_cloneobject(lua_State *L, lunatik_object_t *object);
void lunatik_releaseobject(struct kref *kref);
int lunatik_closeobject(lua_State *L);
int lunatik_deleteobject(lua_State *L);
void lunatik_monitorobject(lua_State *L, const lunatik_class_t *class);

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

#define LUNATIK_CLASSES(name, ...)	\
static const lunatik_class_t *lua##name##_classes[] = { __VA_ARGS__, NULL }

static inline void lunatik_newclasses(lua_State *L, const lunatik_class_t **classes)
{
	for (; *classes; classes++) {
		const lunatik_class_t *cls = *classes;
		lunatik_checkclass(L, cls);
		if (lunatik_ismonitor(cls->opt))
			lunatik_newclass(L, cls, true);
		lunatik_newclass(L, cls, false);
	}
}

#define LUNATIK_NEWLIB(libname, funcs, classes)					\
int luaopen_##libname(lua_State *L);						\
int luaopen_##libname(lua_State *L)						\
{										\
	const lunatik_class_t **clss = classes; /* avoid -Waddress */		\
	luaL_newlib(L, funcs);							\
	if (clss)								\
		lunatik_newclasses(L, clss);					\
	return 1;								\
}										\
EXPORT_SYMBOL_GPL(luaopen_##libname)

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

#define lunatik_getregistry(L, key)	lua_rawgetp((L), LUA_REGISTRYINDEX, (key))

#define lunatik_setstring(L, idx, hook, field, maxlen)		\
do {								\
	size_t len;						\
	lunatik_checkfield(L, idx, #field, LUA_TSTRING);	\
	const char *str = lua_tolstring(L, -1, &len);		\
	if (len > maxlen)					\
		luaL_error(L, "'%s' is too long", #field);	\
	strncpy((char *)hook->field, str, maxlen);		\
	lua_pop(L, 1);						\
} while (0)

#define lunatik_setinteger(L, idx, hook, field) 		\
do {								\
	lunatik_checkfield(L, idx, #field, LUA_TNUMBER);	\
	hook->field = lua_tointeger(L, -1);			\
	lua_pop(L, 1);						\
} while (0)

#define lunatik_optinteger(L, idx, priv, field, opt)			\
do {									\
	lua_getfield(L, idx, #field);					\
	priv->field = lua_isnil(L, -1) ? opt : lua_tointeger(L, -1);	\
	lua_pop(L, 1);							\
} while (0)

static inline void lunatik_optcfunction(lua_State *L, int idx, const char *field, lua_CFunction default_func)
{
	if (lua_getfield(L, idx, field) != LUA_TFUNCTION) {
		lua_pop(L, 1);
		lua_pushcfunction(L, default_func);
	}
}

#define lunatik_checkbounds(L, idx, val, min, max)	\
	luaL_argcheck(L, val >= min && val <= max, idx, "out of bounds")

static inline lua_Integer lunatik_checkinteger(lua_State *L, int idx, lua_Integer min, lua_Integer max)
{
	lua_Integer v = luaL_checkinteger(L, idx);
	lunatik_checkbounds(L, idx, v, min, max);
	return v;
}

static inline void lunatik_register(lua_State *L, int ix, void *key)
{
	lua_pushvalue(L, ix);
	lua_rawsetp(L, LUA_REGISTRYINDEX, key); /* pop value */
}

static inline void lunatik_unregister(lua_State *L, void *key)
{
	lua_pushnil(L);
	lua_rawsetp(L, LUA_REGISTRYINDEX, key); /* pop nil */
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

#define lunatik_attach(L, obj, field, new_fn, ...)	\
do {							\
	obj->field = new_fn((L), ##__VA_ARGS__);	\
	lunatik_register((L), -1, obj->field);		\
	lua_pop((L), 1);				\
} while (0)

#define lunatik_detach(runtime, obj, field)			\
do {								\
	lua_State *L = lunatik_getstate(runtime);		\
	if (L != NULL) /* might be called on lunatik_stop */	\
		lunatik_unregister(L, obj->field);		\
	obj->field = NULL;					\
} while (0)

#include "lunatik_val.h"

#endif

