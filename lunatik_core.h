/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef lunatik_core_h
#define lunatik_core_h

int lunatik_newruntime(lunatik_object_t **pruntime, lua_State *Lfrom, const char *script, lunatik_opt_t opt,
	lunatik_object_t *percpu, int cpu);
int lunatik_resume(lua_State *Lto, lua_State *Lfrom, int ixfrom, int nargs);
int lunatik_closekillable(lunatik_object_t *object);

extern const lunatik_class_t lunatik_percpu_class;
int lunatik_percpu(lua_State *L);

#ifdef MODULE
void lunatik_resolve(void);
#else
#define lunatik_resolve()
#endif

static inline lunatik_opt_t lunatik_inheritopt(const lunatik_class_t *class, lunatik_opt_t opt)
{
	lunatik_opt_t inherited = opt | class->opt;
	return lunatik_issingle(opt) ? inherited & ~LUNATIK_OPT_MONITOR : inherited;
}

static inline void lunatik_pushmetatable(lua_State *L, const lunatik_class_t *class, bool monitor)
{
	if (lua_rawgetp(L, LUA_REGISTRYINDEX, lunatik_monitormt(class, monitor)) == LUA_TNIL)
		luaL_error(L, "'%s': %s", class->name, LUNATIK_ERR_METATABLE);
}

static inline void lunatik_checkmetatable(lua_State *L, const lunatik_class_t *class, bool monitor)
{
	lunatik_pushmetatable(L, class, monitor);
	lua_pop(L, 1); /* metatable */
}

static inline void lunatik_setclass(lua_State *L, const lunatik_class_t *class, bool monitor)
{
	lunatik_pushmetatable(L, class, monitor);
	lua_setmetatable(L, -2);
	lua_pushlightuserdata(L, (void *)class);
	lua_setiuservalue(L, -2, 1); /* pop class */
}

static inline void lunatik_setobject(lunatik_object_t *object, const lunatik_class_t *class, lunatik_opt_t opt)
{
	__module_get(class->owner); /* the code creating the object holds its module already */
	kref_init(&object->kref);
	object->private = NULL;
	object->class = class;
	object->opt = lunatik_inheritopt(class, opt);
	object->gfp = lunatik_isirq(object->opt) ? GFP_ATOMIC : GFP_KERNEL;
	lunatik_newlock(object);
	object->owner = NULL;
}

#define lunatik_newpobject(L, n)	(lunatik_object_t **)lua_newuserdatauv((L), sizeof(lunatik_object_t *), (n))

static inline void *lunatik_unholdobject(void *ud, void *ptr, size_t osize, size_t nsize)
{
	lunatik_putobject((lunatik_object_t *)ud);
	return NULL;
}

static inline void *lunatik_unholdmodule(void *ud, void *ptr, size_t osize, size_t nsize)
{
	module_put((struct module *)ud);
	return NULL;
}

#define lunatik_hold(L, unhold, ud)								\
do {												\
	lua_pushexternalstring((L), "", 0, (unhold), (ud)); /* freed at the end of lua_close */	\
	luaL_ref((L), LUA_REGISTRYINDEX);							\
} while (0)

#define lunatik_holdobject(L, object)	lunatik_hold((L), lunatik_unholdobject, (object))
#define lunatik_holdmodule(L, module)	lunatik_hold((L), lunatik_unholdmodule, (module))

#endif

