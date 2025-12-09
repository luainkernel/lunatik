/*
* SPDX-FileCopyrightText: (c) 2023-2025 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Direct memory access and manipulation.
* This library allows creating `data` objects that represent blocks of memory.
* These objects can then be used to read and write various integer types
* (signed/unsigned, 8/16/32/64-bit) and raw byte strings at specific offsets.
*
* @module data
*/

/***
* Represents a raw block of memory.
* This is a userdata object returned by `data.new()` or created internally
* by other Lunatik modules (e.g., for network packet buffers).
* @type data
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

/***
 * Bounds-checked pointer calculation. Returns pointer on success, raises Lua error on failure.
 * @param L Lua state
 * @param ix Argument index for error reporting
 * @param data luadata object
 * @param offset Byte offset
 * @param length Access length
 * @return Valid pointer within bounds
 */
static inline void *luadata_checkbounds(lua_State *L, int ix, luadata_t *data, lua_Integer offset, lua_Integer length)
{
	int bounds = offset >= 0 && length > 0 && offset + length <= data->size;
	luaL_argcheck(L, bounds, ix, "out of bounds");
	return (void *)(data->ptr + offset);
}

#define luadata_checkwritable(L, data)	luaL_argcheck((L), !((data)->opt & LUADATA_OPT_READONLY), 1, "read only")

/***
* Extracts a signed 8-bit integer from the data object.
* @function getint8
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @treturn integer The signed 8-bit integer value at the specified offset.
* @raise Error if offset is out of bounds.
*/
/***
* Inserts a signed 8-bit integer into the data object.
* @function setint8
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @tparam integer value The signed 8-bit integer value to write.
* @raise Error if offset is out of bounds or the data object is read-only.
*/
#define LUADATA_NEWINT_GETTER(T) 	\
static int luadata_get##T(lua_State *L) \
{					\
	luadata_t *data = luadata_check(L, 1);					\
	lua_Integer offset = luaL_checkinteger(L, 2);				\
	T##_t value = *(T##_t *)luadata_checkbounds(L, 2, data, offset, sizeof(T##_t));		\
	lua_pushinteger(L, (lua_Integer)value);	\
	return 1;			\
}

#define LUADATA_NEWINT_SETTER(T)		\
static int luadata_set##T(lua_State *L)		\
{						\
	luadata_t *data = luadata_check(L, 1);					\
	lua_Integer offset = luaL_checkinteger(L, 2);				\
	T##_t *ptr = luadata_checkbounds(L, 2, data, offset, sizeof(T##_t));		\
	luadata_checkwritable(L, data);		\
	*ptr = (T##_t)luaL_checkinteger(L, 3);	\
	return 0;				\
}

#define LUADATA_NEWINT(T)	\
	LUADATA_NEWINT_GETTER(T); 	\
	LUADATA_NEWINT_SETTER(T);

/***
* Extracts an unsigned 8-bit integer from the data object.
* @function getuint8
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @treturn integer The unsigned 8-bit integer value (0-255) at the specified offset.
* @raise Error if offset is out of bounds.
*/
/***
* Inserts an unsigned 8-bit integer into the data object.
* @function setuint8
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @tparam integer value The unsigned 8-bit integer value (0-255) to write.
* @raise Error if offset is out of bounds or the data object is read-only.
*/
LUADATA_NEWINT(int8);
LUADATA_NEWINT(uint8);
/***
* Extracts a signed 16-bit integer from the data object.
* Assumes host byte order. For specific byte orders, use `linux.be16toh` etc. on the result.
* @function getint16
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @treturn integer The signed 16-bit integer value at the specified offset.
* @raise Error if offset is out of bounds.
*/
/***
* Inserts a signed 16-bit integer into the data object.
* Assumes host byte order. For specific byte orders, use `linux.htobe16` etc. on the value before setting.
* @function setint16
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @tparam integer value The signed 16-bit integer value to write.
* @raise Error if offset is out of bounds or the data object is read-only.
*/
LUADATA_NEWINT(int16);
/***
* Extracts an unsigned 16-bit integer from the data object.
* Assumes host byte order.
* @function getuint16
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @treturn integer The unsigned 16-bit integer value at the specified offset.
* @raise Error if offset is out of bounds.
*/
/***
* Inserts an unsigned 16-bit integer into the data object.
* Assumes host byte order.
* @function setuint16
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @tparam integer value The unsigned 16-bit integer value to write.
* @raise Error if offset is out of bounds or the data object is read-only.
*/
LUADATA_NEWINT(uint16);
/***
* Extracts a signed 32-bit integer from the data object.
* Assumes host byte order.
* @function getint32
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @treturn integer The signed 32-bit integer value at the specified offset.
* @raise Error if offset is out of bounds.
*/
/***
* Inserts a signed 32-bit integer into the data object.
* Assumes host byte order.
* @function setint32
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @tparam integer value The signed 32-bit integer value to write.
* @raise Error if offset is out of bounds or the data object is read-only.
*/
LUADATA_NEWINT(int32);
/***
* Extracts an unsigned 32-bit integer from the data object.
* Assumes host byte order.
* @function getuint32
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @treturn integer The unsigned 32-bit integer value at the specified offset.
* @raise Error if offset is out of bounds.
*/
/***
* Inserts an unsigned 32-bit integer into the data object.
* Assumes host byte order.
* @function setuint32
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @tparam integer value The unsigned 32-bit integer value to write.
* @raise Error if offset is out of bounds or the data object is read-only.
*/
LUADATA_NEWINT(uint32);

#ifdef __LP64__
/***
* Extracts a signed 64-bit integer from the data object.
* Assumes host byte order.
* @function getint64
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @treturn integer The signed 64-bit integer value at the specified offset.
* @raise Error if offset is out of bounds.
*/
/***
* Inserts a signed 64-bit integer into the data object.
* Assumes host byte order.
* @function setint64
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @tparam integer value The signed 64-bit integer value to write.
* @raise Error if offset is out of bounds or the data object is read-only.
*/
LUADATA_NEWINT(int64);
#endif

/***
* Extracts a string from the data object.
* @function getstring
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @tparam[opt] integer length Number of bytes to read. If omitted, reads all bytes from `offset` to the end of the data block.
* @treturn string The string containing the bytes read from the data object.
* @raise Error if offset/length is out of bounds.
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
* Inserts a string into the data object.
* @function setstring
* @tparam integer offset Byte offset from the start of the data block (0-indexed) where writing will begin.
* @tparam string s The string to write into the data object.
* @raise Error if the write operation (offset + length of string) goes out of bounds, or if the data object is read-only.
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
* Returns the length of the data object in bytes.
* This is the Lua `__len` metamethod, allowing use of the `#` operator.
* @function __len
* @treturn integer The total size of the memory block in bytes.
*/
static int luadata_length(lua_State *L)
{
	luadata_t *data = luadata_check(L, 1);
	lua_pushinteger(L, (lua_Integer)data->size);
	return 1;
}

/***
* Returns the content of the data object as a Lua string.
* This is the Lua `__tostring` metamethod.
* @function __tostring
* @treturn string A string representation of the entire data block.
*/
static int luadata_tostring(lua_State *L)
{
	luadata_t *data = luadata_check(L, 1);
	lua_pushlstring(L, data->ptr, data->size);
	return 1;
}

static void luadata_release(void *private)
{
	luadata_t *data = (luadata_t *)private;
	if (data->opt & LUADATA_OPT_FREE)
		lunatik_free(data->ptr);
}

/***
* Creates a new data object, allocating a fresh block of memory.
* @function new
* @tparam integer size The number of bytes to allocate for the data block.
* @treturn data A new, writable data object.
* @raise Error if memory allocation fails.
* @within data
*/
static const luaL_Reg luadata_lib[] = {
	{"new", luadata_lnew},
	{NULL, NULL}
};

static const luaL_Reg luadata_mt[] = {
	{"__index", lunatik_monitorobject},
	{"__gc", lunatik_deleteobject},
	{"__len", luadata_length},
	{"__tostring", luadata_tostring},
/***
* Extracts an unsigned 8-bit integer (a byte) from the data object.
* Alias for `getuint8`.
* @function getbyte
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @treturn integer The byte value (0-255) at the specified offset.
* @raise Error if offset is out of bounds.
* @see getuint8
*/
	{"getbyte", luadata_getuint8},
/***
* Inserts an unsigned 8-bit integer (a byte) into the data object.
* Alias for `setuint8`.
* @function setbyte
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @tparam integer value The byte value (0-255) to write.
* @raise Error if offset is out of bounds or the data object is read-only.
* @see setuint8
*/
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
/***
* Extracts a Lua integer (platform-dependent: 64-bit on LP64, 32-bit otherwise) from the data object.
* Alias for `getint64` on LP64 systems, `getint32` otherwise. Assumes host byte order.
* @function getnumber
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @treturn integer The Lua integer value at the specified offset.
* @raise Error if offset is out of bounds.
*/
	{"getnumber", luadata_getint64},
/***
* Inserts a Lua integer (platform-dependent: 64-bit on LP64, 32-bit otherwise) into the data object.
* Alias for `setint64` on LP64 systems, `setint32` otherwise. Assumes host byte order.
* @function setnumber
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @tparam integer value The Lua integer value to write.
* @raise Error if offset is out of bounds or the data object is read-only.
*/
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
	.flags = false,
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

static inline lunatik_object_t *luadata_create(void *ptr, size_t size, bool sleep, uint8_t opt)
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

lunatik_object_t *luadata_new(lua_State *L)
{
	lunatik_object_t *data = lunatik_checknull(L, luadata_create(NULL, 0, false, LUADATA_OPT_NONE));
	lunatik_cloneobject(L, data);
	return data;
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

