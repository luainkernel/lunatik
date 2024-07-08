/*
* SPDX-FileCopyrightText: (c) 2023-2024 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/kernel.h>
#include <linux/module.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <lunatik.h>

#include "luadata.h"

typedef struct luadata_s {
	char *ptr;
	size_t size;
	uint8_t opt;
} luadata_t;

#define LUADATA_NUMBER_SZ	(sizeof(lua_Integer))

static int luadata_lnew(lua_State *L);

LUNATIK_PRIVATECHECKER(luadata_check, luadata_t *);

static inline void luadata_checkbounds(lua_State *L, int ix, size_t size, lua_Integer offset, lua_Integer length)
{
	int bounds = offset >= 0 && length > 0 && offset + length <= size;
	luaL_argcheck(L, bounds, ix, "out of bounds");
}

static inline luadata_t *luadata_checkdata(lua_State *L, lua_Integer *offset, lua_Integer length)
{
	luadata_t* data = luadata_check(L, 1);
	*offset = luaL_checkinteger(L, 2);
	luadata_checkbounds(L, 2, data->size, *offset, length);
	return data;
}

#define luadata_checkint(L, offset, T)	luadata_checkdata((L), &(offset), sizeof(T##_t))

#define luadata_checkwritable(L, data)	luaL_argcheck((L), !((data)->opt & LUADATA_OPT_READONLY), 1, "read only")

#define LUADATA_NEWINT_GETTER(T) 	\
static int luadata_get##T(lua_State *L) \
{					\
	lua_Integer offset;		\
	luadata_t *data = luadata_checkint(L, offset, T);			\
	lua_pushinteger(L, (lua_Integer)*(T##_t *)(data->ptr + offset));	\
	return 1;			\
}

#define LUADATA_NEWINT_SETTER(T)		\
static int luadata_set##T(lua_State *L)		\
{						\
	lua_Integer offset;			\
	luadata_t *data = luadata_checkint(L, offset, T);			\
	luadata_checkwritable(L, data);		\
	*(T##_t *)(data->ptr + offset) = (T##_t)luaL_checkinteger(L, 3);	\
	return 0;				\
}

#define LUADATA_NEWINT(T)	\
	LUADATA_NEWINT_GETTER(T); 	\
	LUADATA_NEWINT_SETTER(T);

LUADATA_NEWINT(int8);
LUADATA_NEWINT(uint8);
LUADATA_NEWINT(int16);
LUADATA_NEWINT(uint16);
LUADATA_NEWINT(int32);
LUADATA_NEWINT(uint32);

#ifdef __LP64__
LUADATA_NEWINT(int64);
#endif

static int luadata_getstring(lua_State *L)
{
	luadata_t *data = luadata_check(L, 1);
	lua_Integer offset = luaL_checkinteger(L, 2);
	lua_Integer length = luaL_optinteger(L, 3, data->size - offset);
	luadata_checkbounds(L, 2, data->size, offset, length);

	lua_pushlstring(L, data->ptr + offset, length);
	return 1;
}

static int luadata_setstring(lua_State *L)
{
	lua_Integer offset;
	size_t length;
	const char *str = luaL_checklstring(L, 3, &length);
	luadata_t *data = luadata_checkdata(L, &offset, (lua_Integer)length);
	luadata_checkwritable(L, data);

	memcpy(data->ptr + offset, str, length);
	return 0;
}

static int luadata_length(lua_State *L)
{
	luadata_t *data = luadata_check(L, 1);
	lua_pushinteger(L, (lua_Integer)data->size);
	return 1;
}

static void luadata_release(void *private)
{
	luadata_t *data = (luadata_t *)private;
	if (data->opt & LUADATA_OPT_FREE)
		lunatik_free(data->ptr);
}

static const luaL_Reg luadata_lib[] = {
	{"new", luadata_lnew},
	{NULL, NULL}
};

static const luaL_Reg luadata_mt[] = {
	{"__index", lunatik_monitorobject},
	{"__gc", lunatik_deleteobject},
	{"__len", luadata_length},
	{"getbyte", luadata_getuint8},
	{"setbyte", luadata_setuint8},
	{"getint8", luadata_getint8},
	{"setint8", luadata_setint8},
	{"getuint8", luadata_getuint8},
	{"setuint8", luadata_setuint8},
	{"getint16", luadata_getint16},
	{"setint16", luadata_setint16},
	{"getuint16", luadata_getuint16},
	{"setuint16", luadata_setuint16},
	{"getint32", luadata_getint32},
	{"setint32", luadata_setint32},
	{"getuint32", luadata_getuint32},
	{"setuint32", luadata_setuint32},
#ifdef __LP64__
	{"getint64", luadata_getint64},
	{"setint64", luadata_setint64},
	{"getnumber", luadata_getint64},
	{"setnumber", luadata_setint64},
#else
	{"getnumber", luadata_getint32},
	{"setnumber", luadata_setint32},
#endif
	{"getstring", luadata_getstring},
	{"setstring", luadata_setstring},
	{NULL, NULL}
};

static const lunatik_class_t luadata_class = {
	.name = "data",
	.methods = luadata_mt,
	.release = luadata_release,
};

static int luadata_lnew(lua_State *L)
{
	size_t size = (size_t)luaL_checkinteger(L, 1);
	lunatik_object_t *object = lunatik_newobject(L, &luadata_class, sizeof(luadata_t));
	luadata_t *data = (luadata_t *)object->private;

	data->ptr = lunatik_checkalloc(L, size);
	data->size = size;
	data->opt = LUADATA_OPT_FREE;
	return 1; /* object */
}

LUNATIK_NEWLIB(data, luadata_lib, &luadata_class, NULL);

lunatik_object_t *luadata_new(void *ptr, size_t size, bool sleep, uint32_t opt)
{
	lunatik_object_t *object = lunatik_createobject(&luadata_class, sizeof(luadata_t), sleep);

	if (object != NULL) {
		luadata_t *data = (luadata_t *)object->private;
		data->ptr = ptr;
		data->size = size;
		data->opt = opt;
	}
	return object;
}
EXPORT_SYMBOL(luadata_new);

int luadata_reset(lunatik_object_t *object, void *ptr, size_t size, uint8_t opt)
{
	luadata_t *data;

	lunatik_lock(object);
	data = (luadata_t *)object->private;

	if (data->opt & LUADATA_OPT_FREE) {
		lunatik_unlock(object);
		return -1;
	}

	data->ptr = ptr;
	data->size = size;
	data->opt = opt & LUADATA_OPT_KEEP ? data->opt : opt;

	lunatik_unlock(object);
	return 0;
}
EXPORT_SYMBOL(luadata_reset);

static int __init luadata_init(void)
{
	return 0;
}

static void __exit luadata_exit(void)
{
}

module_init(luadata_init);
module_exit(luadata_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ring-0.io>");

