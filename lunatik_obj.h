/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef lunatik_obj_h
#define lunatik_obj_h

static inline void lunatik_checkclass(lua_State *L, const lunatik_class_t *class)
{
	if (lunatik_cannotsleep(L, class->sleep))
		luaL_error(L, "cannot use '%s' class on non-sleepable runtime", class->name);
}

static inline void lunatik_setclass(lua_State *L, const lunatik_class_t *class, bool shared)
{
	lua_pushfstring(L, shared ? "_%s" : "%s", class->name);
	if (lua_rawget(L, LUA_REGISTRYINDEX) == LUA_TNIL)
		luaL_error(L, "metatable not found (%s)", lua_tostring(L, -1));
	lua_setmetatable(L, -2);
	lua_pushlightuserdata(L, (void *)class);
	lua_setiuservalue(L, -2, 1); /* pop class */
}

static inline void lunatik_setobject(lunatik_object_t *object, const lunatik_class_t *class, bool sleep, bool shared)
{
	kref_init(&object->kref);
	object->private = NULL;
	object->class = class;
	object->sleep = sleep;
	object->shared = shared;
	object->gfp = sleep ? GFP_KERNEL : GFP_ATOMIC;
	lunatik_newlock(object);
}

lunatik_object_t *lunatik_newobject(lua_State *L, const lunatik_class_t *class, size_t size, bool shared);
lunatik_object_t *lunatik_createobject(const lunatik_class_t *class, size_t size, bool sleep, bool shared);
void lunatik_cloneobject(lua_State *L, lunatik_object_t *object);
void lunatik_releaseobject(struct kref *kref);
int lunatik_closeobject(lua_State *L);
int lunatik_deleteobject(lua_State *L);
void lunatik_monitorobject(lua_State *L, const lunatik_class_t *class);

#define LUNATIK_ERR_NULLPTR	"null-pointer dereference"
#define LUNATIK_ERR_SHARED 	"cannot create shared object from non-shared class '%s'"

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
	lua_pushfstring(L, monitored ? "_%s" : "%s", class->name);
	luaL_newmetatable(L, lua_tostring(L, -1)); /* mt = {} */
	luaL_setfuncs(L, class->methods, 0);
	if (monitored)
		lunatik_monitorobject(L, class);
	if (!lunatik_hasindex(L, -1)) {
		lua_pushvalue(L, -1);  /* push mt */
		lua_setfield(L, -2, "__index");  /* mt.__index = mt */
	}
	lua_pop(L, 2);  /* pop mt, class name */
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

#define LUNATIK_NEWLIB(libname, funcs, class, namespaces)			\
int luaopen_##libname(lua_State *L);						\
int luaopen_##libname(lua_State *L)						\
{										\
	const lunatik_class_t *cls = class; /* avoid -Waddress */		\
	const lunatik_namespace_t *nss = namespaces; /* avoid -Waddress */	\
	luaL_newlib(L, funcs);							\
	if (cls) {								\
		lunatik_checkclass(L, cls);					\
		if (cls->shared)							\
			lunatik_newclass(L, cls, true);			\
		lunatik_newclass(L, cls, false);			\
	}									\
	if (nss)								\
		lunatik_newnamespaces(L, nss);					\
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

#endif

