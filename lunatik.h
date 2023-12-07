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

#ifndef lunatik_h
#define lunatik_h

#include <linux/mutex.h>
#include <linux/spinlock.h>
#include <linux/slab.h>
#include <linux/kref.h>

#include <lua.h>
#include <lauxlib.h>

#define LUNATIK_VERSION	"Lunatik 3.3"

typedef struct lunatik_runtime_s {
	lua_State *L;
	struct kref kref;
	union {
		struct mutex mutex;
		spinlock_t spin;
	};
	bool sleep;
	bool ready;
} lunatik_runtime_t;

#define lunatik_locker(runtime, mutex_op, spin_op)	\
do {							\
	if ((runtime)->sleep)				\
		mutex_op(&(runtime)->mutex);		\
	else						\
		spin_op(&(runtime)->spin);		\
} while(0)

#define lunatik_lockinit(o)	lunatik_locker((o), mutex_init, spin_lock_init);
#define lunatik_lockrelease(o)	lunatik_locker((o), mutex_destroy, (void));
#define lunatik_lock(runtime)	lunatik_locker(runtime, mutex_lock, spin_lock)
#define lunatik_unlock(runtime)	lunatik_locker(runtime, mutex_unlock, spin_unlock)
#define lunatik_toruntime(L)	(*(lunatik_runtime_t **)lua_getextraspace(L))

static inline bool lunatik_islocked(lunatik_runtime_t *runtime)
{
	return runtime->sleep ? mutex_is_locked(&runtime->mutex) : spin_is_locked(&runtime->spin);
}

int lunatik_runtime(lunatik_runtime_t **pruntime, const char *script, bool sleep);
int lunatik_stop(lunatik_runtime_t *runtime);

lunatik_runtime_t *lunatik_checkruntime(lua_State *L, int arg);

static inline void lunatik_release(struct kref *kref)
{
	lunatik_runtime_t *runtime = container_of(kref, lunatik_runtime_t, kref);
	lunatik_lockrelease(runtime);
	kfree(runtime);
}

#define lunatik_put(runtime)	kref_put(&(runtime)->kref, lunatik_release)
#define lunatik_get(runtime)	kref_get(&(runtime)->kref)

#define lunatik_getsleep(L)	(lunatik_toruntime(L)->sleep)
#define lunatik_getready(L)	(lunatik_toruntime(L)->ready)

#define lunatik_cansleep(L)	(!lunatik_getready(L) || lunatik_getsleep(L))

#define lunatik_handle(runtime, handler, ret, ...)	\
do {							\
	lua_State *L = runtime->L;			\
	int n = lua_gettop(L);				\
	ret = handler(L, ## __VA_ARGS__);		\
	lua_settop(L, n);				\
} while(0)

#define lunatik_run(runtime, handler, ret, ...)				\
do {									\
	lunatik_lock(runtime);						\
	if (unlikely(!runtime->L))					\
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
} lunatik_class_t;

// XXX rutime must be an object ;-)

typedef struct lunatik_object_s {
	struct kref kref;
	const lunatik_class_t *class;
	bool sleep;
	union {
		struct mutex mutex;
		spinlock_t spin;
	};
	void *private;
} lunatik_object_t;

static inline void *lunatik_realloc(lua_State *L, void *ptr, size_t size)
{
	void *ud = NULL;
	lua_Alloc alloc = lua_getallocf(L, &ud);
	return alloc(ud, ptr, LUA_TNONE, size);
}

#define lunatik_free(p)	kfree(p)

static inline void *lunatik_checkalloc(lua_State *L, size_t size)
{
	void *ptr = lunatik_realloc(L, NULL, size);
	if (ptr == NULL)
		luaL_error(L, "not enough memory");
	return ptr;
}

lunatik_object_t *lunatik_newobject(lua_State *L, const lunatik_class_t *class, size_t size);
lunatik_object_t **lunatik_checkpobject(lua_State *L, int ix);
void lunatik_cloneobject(lua_State *L, lunatik_object_t *object);
// XXX mudar de volta s/free/release/
void lunatik_freeobject(struct kref *kref);
int lunatik_closeobject(lua_State *L);

#define lunatik_checknull(L, o, i)	luaL_argcheck((L), (o) != NULL, (i), "null-pointer dereference")
#define lunatik_checkobject(L, i)	(*lunatik_checkpobject((L), (i)))
#define lunatik_getobject(o)		kref_get(&(o)->kref)
#define lunatik_putobject(o)		kref_put(&(o)->kref, lunatik_freeobject)

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

static void inline lunatik_newnamespaces(lua_State *L, const lunatik_namespace_t *namespaces)
{
	if (namespaces != NULL) {
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
}

#define LUNATIK_NEWLIB(libname, funcs, class, namespaces)					\
int luaopen_##libname(lua_State *L)								\
{												\
	if (!lunatik_getsleep(L) && (class)->sleep)						\
		luaL_error(L, "cannot require '" #libname "' on non-sleepable runtime");	\
	luaL_newlib(L, funcs);									\
	if ((class)->name != NULL)								\
		lunatik_newclass(L, class);							\
	lunatik_newnamespaces(L, namespaces);							\
	return 1;										\
}												\
EXPORT_SYMBOL(luaopen_##libname)

#define LUNATIK_OBJECTCHECKER(checker, T)			\
static inline T checker(lua_State *L, int ix)			\
{								\
	lunatik_object_t *object = lunatik_checkobject(L, ix);	\
	lunatik_checknull(L, object->private, ix);		\
	return (T)object->private;				\
}

// XXX nao precisamos mais destes templates!!
#define LUNATIK_OBJECTDELETER(deleter)					\
static int deleter(lua_State *L)					\
{									\
	lunatik_object_t **pobject = lunatik_checkpobject(L, 1);	\
	lunatik_object_t *object = *pobject;				\
	if (object != NULL) {						\
		lunatik_putobject(object);				\
		*pobject = NULL;					\
	}								\
	return 0;							\
}

#define LUNATIK_OBJECTMONITOR(monitor)					\
static int monitor##closure(lua_State *L)				\
{									\
	int ret, n = lua_gettop(L);					\
	lunatik_object_t *object = lunatik_checkobject(L, 1);		\
	lua_pushvalue(L, lua_upvalueindex(1)); /* method */		\
	lua_insert(L, 1); /* stack: method, object, args */		\
	lunatik_lock(object);						\
	ret = lua_pcall(L, n, LUA_MULTRET, 0);				\
	lunatik_unlock(object);						\
	if (ret != LUA_OK)						\
		lua_error(L);						\
	return lua_gettop(L);						\
}									\
static int monitor(lua_State *L)					\
{									\
	lua_getmetatable(L, 1);						\
	lua_insert(L, 2); /* stack: object, metatable, key */		\
	if (lua_rawget(L, 2) == LUA_TFUNCTION) /* method */		\
		lua_pushcclosure(L, monitor##closure, 1);		\
	return 1;							\
}

#endif

