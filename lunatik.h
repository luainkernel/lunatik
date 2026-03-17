/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef lunatik_h
#define lunatik_h

#include <linux/version.h>

#include "lunatik_obj.h"

#define LUNATIK_VERSION	"Lunatik 4.1"

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

extern lunatik_object_t *lunatik_env;

int lunatik_runtime(lunatik_object_t **pruntime, const char *script, lunatik_opt_t opt);
int lunatik_stop(lunatik_object_t *runtime);

static inline int lunatik_nop(lua_State *L)
{
	return 0;
}

static inline bool lunatik_isready(lua_State *L)
{
	bool ready;
	lua_rawgetp(L, LUA_REGISTRYINDEX, L);
	ready = lua_toboolean(L, -1);
	lua_pop(L, 1);
	return ready;
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

static inline void lunatik_require(lua_State *L, const char *libname)
{
	lua_getglobal(L, "require");
	lua_pushstring(L, libname);
	lua_call(L, 1, 0);
}

#define lunatik_getregistry(L, key)	lua_rawgetp((L), LUA_REGISTRYINDEX, (key))

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

#define lunatik_setinteger(L, idx, hook, field)			\
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

#define LUNATIK_NEWLIB(libname, funcs, class, namespaces)			\
int luaopen_##libname(lua_State *L);						\
int luaopen_##libname(lua_State *L)						\
{										\
	const lunatik_class_t *cls = class; /* avoid -Waddress */		\
	const lunatik_namespace_t *nss = namespaces; /* avoid -Waddress */	\
	luaL_newlib(L, funcs);							\
	if (cls) {								\
		lunatik_checkclass(L, cls);					\
		if (lunatik_ismonitor(cls->opt))				\
			lunatik_newclass(L, cls, true);				\
		lunatik_newclass(L, cls, false);				\
	}									\
	if (nss)								\
		lunatik_newnamespaces(L, nss);					\
	return 1;								\
}										\
EXPORT_SYMBOL_GPL(luaopen_##libname)

static inline void lunatik_newnamespaces(lua_State *L, const lunatik_namespace_t *namespaces)
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

#include "lunatik_val.h"

#endif
