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

#define LUNATIK_VERSION	"Lunatik 3.1"

typedef struct lunatik_runtime_s {
	lua_State *L;
	struct kref kref;
	union {
		struct mutex mutex;
		spinlock_t spin;
	};
	bool sleep;
} lunatik_runtime_t;

#define lunatik_locker(runtime, mutex_op, spin_op)	\
do {							\
	if ((runtime)->sleep)				\
		mutex_op(&(runtime)->mutex);		\
	else						\
		spin_op(&(runtime)->spin);		\
} while(0)

#define lunatik_lock(runtime)	lunatik_locker(runtime, mutex_lock, spin_lock)
#define lunatik_unlock(runtime)	lunatik_locker(runtime, mutex_unlock, spin_unlock)
#define lunatik_toruntime(L)	(*(lunatik_runtime_t **)lua_getextraspace(L))

int lunatik_runtime(lunatik_runtime_t **pruntime, const char *script, bool sleep);
int lunatik_stop(lunatik_runtime_t *runtime);

static inline void lunatik_release(struct kref *kref)
{
	lunatik_runtime_t *runtime = container_of(kref, lunatik_runtime_t, kref);
	lunatik_locker(runtime, mutex_destroy, (void));
	kfree(runtime);
}

#define lunatik_put(runtime)	kref_put(&(runtime)->kref, lunatik_release)
#define lunatik_get(runtime)	kref_get(&(runtime)->kref)

#define lunatik_getsleep(L)	(lunatik_toruntime(L)->sleep)

#define lunatik_run(runtime, handler, ret, ...)		\
do {							\
	lua_State *L;					\
	lunatik_lock(runtime);				\
	L = runtime->L;					\
	if (unlikely(!L))				\
		ret = -ENXIO;				\
	else {						\
		int n;					\
		n = lua_gettop(L);			\
		ret = handler(L, ## __VA_ARGS__);	\
		lua_settop(L, n);			\
	}						\
	lunatik_unlock(runtime);			\
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
} lunatik_class_t;

static inline void lunatik_newclass(lua_State *L, const lunatik_class_t *class)
{
	luaL_newmetatable(L, class->name); /* mt = {} */
	luaL_setfuncs(L, class->methods, 0);
	lua_pushvalue(L, -1);  /* push lib */
	lua_setfield(L, -2, "__index");  /* mt.__index = lib */
	lua_pop(L, 1);  /* pop mt */
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

#define LUNATIK_NEWLIB(libname, funcs, class, namespaces, sleep)				\
int luaopen_##libname(lua_State *L)								\
{												\
	const lunatik_class_t *cls = class; /* avoid -Waddress */				\
	const lunatik_namespace_t *nss = namespaces; /* avoid -Waddress */			\
	if (sleep && !lunatik_getsleep(L))							\
		luaL_error(L, "cannot require '" #libname "' on non-sleepable runtimes");	\
	luaL_newlib(L, funcs);									\
	if (cls)										\
		lunatik_newclass(L, class);							\
	if (nss)										\
		lunatik_newnamespaces(L, namespaces);						\
	return 1;										\
}												\
EXPORT_SYMBOL(luaopen_##libname)

#endif

