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

#define LUNATIK_VERSION	"Lunatik 4.1"

#define lunatik_locker(o, mutex_op, spin_op)	\
do {						\
	if ((o)->sleep)				\
		mutex_op(&(o)->mutex);		\
	else					\
		spin_op(&(o)->spin);		\
} while (0)

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
	bool shared;
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
	bool shared;
} lunatik_object_t;

extern lunatik_object_t *lunatik_env;

static inline int lunatik_trylock(lunatik_object_t *object)
{
	return unlikely(object->shared) ? (object->sleep ? mutex_trylock(&object->mutex) : spin_trylock(&object->spin)) : 1;
}

int lunatik_runtime(lunatik_object_t **pruntime, const char *script, bool sleep);
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

static inline lunatik_object_t *lunatik_checkruntime(lua_State *L, bool sleep)
{
	lunatik_object_t *runtime = lunatik_toruntime(L);
	if (runtime->sleep != sleep)
		luaL_error(L, "cannot use %ssleepable runtime in this context", runtime->sleep ? "" : "non-");
	return runtime;
}

#define lunatik_setruntime(L, libname, priv)	((priv)->runtime = lunatik_checkruntime((L), lua##libname##_class.sleep))

#include "lunatik_obj.h"
#include "lunatik_val.h"

#endif

