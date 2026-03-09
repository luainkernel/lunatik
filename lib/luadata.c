/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Direct memory access and manipulation.
* @module data
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/bitops.h>
#include <net/checksum.h>

#include <lunatik.h>

#include "luadata.h"


typedef struct luadata_s {
	void *ptr;
	size_t size;
	uint8_t opt;
} luadata_t;

#define LUADATA_NUMBER_SZ	(sizeof(lua_Integer))

static int luadata_lnew(lua_State *L);

LUNATIK_PRIVATECHECKER(luadata_check, luadata_t *);

static inline void *luadata_checkbounds(lua_State *L, int ix, luadata_t *data, lua_Integer offset, lua_Integer length)
{
	int bounds = offset >= 0 && length > 0 && offset + length <= data->size;
	luaL_argcheck(L, bounds, ix, "out of bounds");
	return (data->ptr + offset);
}

#define luadata_checkwritable(L, data)	luaL_argcheck((L), !((data)->opt & LUADATA_OPT_READONLY), 1, "read only")

#define LUADATA_NEWINT_GETTER(T)							\
static int luadata_get##T(lua_State *L) 						\
{											\
	luadata_t *data = luadata_check(L, 1);						\
	lua_Integer offset = luaL_checkinteger(L, 2);					\
	T##_t value = *(T##_t *)luadata_checkbounds(L, 2, data, offset, sizeof(T##_t));	\
	lua_pushinteger(L, (lua_Integer)value);						\
	return 1;									\
}

#define LUADATA_NEWINT_SETTER(T)						\
static int luadata_set##T(lua_State *L)						\
{										\
	luadata_t *data = luadata_check(L, 1);					\
	lua_Integer offset = luaL_checkinteger(L, 2);				\
	T##_t *ptr = luadata_checkbounds(L, 2, data, offset, sizeof(T##_t));	\
	luadata_checkwritable(L, data);						\
	*ptr = (T##_t)luaL_checkinteger(L, 3);					\
	return 0;								\
}

#define LUADATA_NEWINT(T)		\
	LUADATA_NEWINT_GETTER(T); 	\
	LUADATA_NEWINT_SETTER(T);

LUADATA_NEWINT(int8);
LUADATA_NEWINT(uint8);
LUADATA_NEWINT(int16);
LUADATA_NEWINT(uint16);
LUADATA_NEWINT(int32);
LUADATA_NEWINT(uint32);
LUADATA_NEWINT(int64);

/***
* @function getstring
* @tparam integer offset
* @tparam[opt] integer length number of bytes; default: from offset to end
* @treturn string
* @raise if out of bounds
*/
static int luadata_getstring(lua_State *L)
{
	luadata_t *data = luadata_check(L, 1);
	lua_Integer offset = luaL_checkinteger(L, 2);
	lua_Integer length = luaL_optinteger(L, 3, data->size - offset);
	char *str = (char *)luadata_checkbounds(L, 2, data, offset, length);

	lua_pushlstring(L, str, length);
	return 1;
}

/***
* @function setstring
* @tparam integer offset
* @tparam string s
* @raise if out of bounds or read-only
*/
static int luadata_setstring(lua_State *L)
{
	size_t length;
	luadata_t *data = luadata_check(L, 1);
	lua_Integer offset = luaL_checkinteger(L, 2);
	const char *str = luaL_checklstring(L, 3, &length);
	void *ptr = luadata_checkbounds(L, 2, data, offset, length);

	luadata_checkwritable(L, data);
	memcpy(ptr, str, length);
	return 0;
}

/***
* @function checksum
* @tparam[opt] integer offset
* @tparam[opt] integer length
* @treturn integer
* @raise if out of bounds
*/
static int luadata_checksum(lua_State *L)
{
	luadata_t *data = luadata_check(L, 1);
	lua_Integer offset = luaL_optinteger(L, 2, 0);
	lua_Integer length = luaL_optinteger(L, 3, data->size - offset);
	void *value = (void*)luadata_checkbounds(L, 2, data, offset, length);

	__wsum sum = csum_partial(value, length, 0);
	lua_pushinteger(L, csum_fold(sum));
	return 1;
}

/***
* @function resize
* @tparam integer new_size
* @raise if read-only or not owned
*/
static int luadata_resize(lua_State *L)
{
	luadata_t *data = luadata_check(L, 1);
	size_t new_size = (size_t)luaL_checkinteger(L, 2);

	luadata_checkwritable(L, data);

	if (data->opt & LUADATA_OPT_FREE)
		data->ptr = lunatik_checknull(L, lunatik_realloc(L, data->ptr, new_size));
	else
		luaL_error(L, "cannot resize external memory");

	data->size = new_size;
	return 0;
}

/***
* @function __len
* @treturn integer data size in bytes
*/
static int luadata_length(lua_State *L)
{
	luadata_t *data = luadata_check(L, 1);
	lua_pushinteger(L, (lua_Integer)data->size);
	return 1;
}

/***
* @function __tostring
* @treturn string
*/
static int luadata_tostring(lua_State *L)
{
	luadata_t *data = luadata_check(L, 1);
	lua_pushlstring(L, (char *)data->ptr, data->size);
	return 1;
}

static void luadata_release(void *private)
{
	luadata_t *data = (luadata_t *)private;
	if (data->opt & LUADATA_OPT_FREE)
		lunatik_free(data->ptr);
}

/***
* @function new
* @tparam integer size
* @treturn data
* @raise if allocation fails
*/
static const luaL_Reg luadata_lib[] = {
	{"new", luadata_lnew},
	{NULL, NULL}
};

static const luaL_Reg luadata_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"__len", luadata_length},
	{"__tostring", luadata_tostring},
/***
* @function getbyte
* @tparam integer offset
* @treturn integer
* @raise if out of bounds
*/
	{"getbyte", luadata_getuint8},
/***
* @function setbyte
* @tparam integer offset
* @tparam integer value
* @raise if out of bounds or read-only
*/
	{"setbyte", luadata_setuint8},
/***
* @function getint8
* @tparam integer offset
* @treturn integer
* @raise if out of bounds
*/
	{"getint8", luadata_getint8},
/***
* @function setint8
* @tparam integer offset
* @tparam integer value
* @raise if out of bounds or read-only
*/
	{"setint8", luadata_setint8},
/***
* @function getuint8
* @tparam integer offset
* @treturn integer
* @raise if out of bounds
*/
	{"getuint8", luadata_getuint8},
/***
* @function setuint8
* @tparam integer offset
* @tparam integer value
* @raise if out of bounds or read-only
*/
	{"setuint8", luadata_setuint8},
/***
* @function getint16
* @tparam integer offset
* @treturn integer
* @raise if out of bounds
*/
	{"getint16", luadata_getint16},
/***
* @function setint16
* @tparam integer offset
* @tparam integer value
* @raise if out of bounds or read-only
*/
	{"setint16", luadata_setint16},
/***
* @function getuint16
* @tparam integer offset
* @treturn integer
* @raise if out of bounds
*/
	{"getuint16", luadata_getuint16},
/***
* @function setuint16
* @tparam integer offset
* @tparam integer value
* @raise if out of bounds or read-only
*/
	{"setuint16", luadata_setuint16},
/***
* @function getint32
* @tparam integer offset
* @treturn integer
* @raise if out of bounds
*/
	{"getint32", luadata_getint32},
/***
* @function setint32
* @tparam integer offset
* @tparam integer value
* @raise if out of bounds or read-only
*/
	{"setint32", luadata_setint32},
/***
* @function getuint32
* @tparam integer offset
* @treturn integer
* @raise if out of bounds
*/
	{"getuint32", luadata_getuint32},
/***
* @function setuint32
* @tparam integer offset
* @tparam integer value
* @raise if out of bounds or read-only
*/
	{"setuint32", luadata_setuint32},
/***
* @function getint64
* @tparam integer offset
* @treturn integer
* @raise if out of bounds
*/
	{"getint64", luadata_getint64},
/***
* @function setint64
* @tparam integer offset
* @tparam integer value
* @raise if out of bounds or read-only
*/
	{"setint64", luadata_setint64},
/***
* @function getnumber
* @tparam integer offset
* @treturn integer
* @raise if out of bounds
*/
	{"getnumber", luadata_getint64},
/***
* @function setnumber
* @tparam integer offset
* @tparam integer value
* @raise if out of bounds or read-only
*/
	{"setnumber", luadata_setint64},
	{"getstring", luadata_getstring},
	{"setstring", luadata_setstring},
	{"resize", luadata_resize},
	{"checksum", luadata_checksum},
	{NULL, NULL}
};

static const lunatik_class_t luadata_class = {
	.name = "data",
	.methods = luadata_mt,
	.release = luadata_release,
	.sleep = false,
	.shared = true,
};

static inline void luadata_set(luadata_t *data, void *ptr, size_t size, uint8_t opt)
{
	data->ptr = ptr;
	data->size = size;
	data->opt = opt;
}

static int luadata_lnew(lua_State *L)
{
	size_t size = (size_t)luaL_checkinteger(L, 1);
	lunatik_object_t *object = lunatik_newobject(L, &luadata_class, sizeof(luadata_t), true);
	luadata_t *data = (luadata_t *)object->private;

	luadata_set(data, lunatik_checkalloc(L, size), size, LUADATA_OPT_FREE);
	return 1; /* object */
}

LUNATIK_NEWLIB(data, luadata_lib, &luadata_class, NULL);

lunatik_object_t *luadata_new(lua_State *L, bool shared)
{
	lunatik_require(L, "data");
	lunatik_object_t *object = lunatik_newobject(L, &luadata_class, sizeof(luadata_t), shared);
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

	opt = opt & LUADATA_OPT_KEEP ? data->opt : opt;
	luadata_set(data, ptr, size, opt);

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
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ringzero.com.br>");

