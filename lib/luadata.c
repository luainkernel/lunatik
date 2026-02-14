/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
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
#include <linux/skbuff.h>

#include <lunatik.h>

#include "luadata.h"

#define LUADATA_TOSKB(d)  ((struct sk_buff *)(d)->ptr)
#define LUADATA_TOPTR(d)	\
	(((d)->opt & LUADATA_OPT_SKB ? (LUADATA_TOSKB(d)->data) : (d)->ptr) + (d)->offset)

typedef struct luadata_s {
	void *ptr;
	ptrdiff_t offset;
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
	return (LUADATA_TOPTR(data) + offset);
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
* Resizes an SKB (socket buffer) to the specified size.
* Expands the buffer using skb_put() if new_size > current size,
* or shrinks it using skb_trim() if new_size < current size.
* @param L Lua state for error reporting
* @param data luadata object wrapping the SKB
* @param new_size The desired size in bytes
* @raise Error if insufficient tailroom is available for expansion
*/
static void luadata_skb_resize(lua_State *L, luadata_t *data, size_t new_size)
{
	struct sk_buff *skb = LUADATA_TOSKB(data);
	if (new_size > data->size) {
		size_t needed = new_size - data->size;
		if (skb_tailroom(skb) < needed)
			luaL_error(L, "insufficient tailroom for resize");
		skb_put(skb, needed);
	}
	else if (new_size < data->size)
		skb_trim(skb, new_size);
}

/***
* Perform a raw checksum on a given buffer.
* @function checksum
* @tparam[opt] integer offset, from where to checksum
* @tparam[opt] integer length, total length checksum
* @raise Error if the write operation (offset + length of data).
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
* Resizes the memory block represented by the data object.
* If the object is a network packet (SKB), it uses skb_put() to expand 
* or skb_trim() to shrink the buffer. For raw buffers, it updates the size.
* @function resize
* @tparam integer new_size The desired size of the memory block in bytes.
* @raise Error if the data object is read-only or if resize fails.
*/
static int luadata_resize(lua_State *L)
{
	luadata_t *data = luadata_check(L, 1);
	size_t new_size = (size_t)luaL_checkinteger(L, 2);

	luadata_checkwritable(L, data);

	if (data->opt & LUADATA_OPT_SKB)
		luadata_skb_resize(L, data, new_size); 
	else if (data->opt & LUADATA_OPT_FREE)
		data->ptr = lunatik_checknull(L, lunatik_realloc(L, data->ptr, new_size));
	else
		luaL_error(L, "cannot resize external memory");

	data->size = new_size;
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
	lua_pushlstring(L, (char *)LUADATA_TOPTR(data), data->size);
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
/***
* Extracts a signed 8-bit integer from the data object.
* @function getint8
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @treturn integer The signed 8-bit integer value at the specified offset.
* @raise Error if offset is out of bounds.
*/
	{"getint8", luadata_getint8},
/***
* Inserts a signed 8-bit integer into the data object.
* @function setint8
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @tparam integer value The signed 8-bit integer value to write.
* @raise Error if offset is out of bounds or the data object is read-only.
*/
	{"setint8", luadata_setint8},
/***
* Extracts an unsigned 8-bit integer from the data object.
* @function getuint8
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @treturn integer The unsigned 8-bit integer value (0-255) at the specified offset.
* @raise Error if offset is out of bounds.
*/
	{"getuint8", luadata_getuint8},
/***
* Inserts an unsigned 8-bit integer into the data object.
* @function setuint8
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @tparam integer value The unsigned 8-bit integer value (0-255) to write.
* @raise Error if offset is out of bounds or the data object is read-only.
*/
	{"setuint8", luadata_setuint8},
/***
* Extracts a signed 16-bit integer from the data object.
* Assumes host byte order. For specific byte orders, use `linux.be16toh` etc. on the result.
* @function getint16
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @treturn integer The signed 16-bit integer value at the specified offset.
* @raise Error if offset is out of bounds.
*/
	{"getint16", luadata_getint16},
/***
* Inserts a signed 16-bit integer into the data object.
* Assumes host byte order. For specific byte orders, use `linux.htobe16` etc. on the value before setting.
* @function setint16
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @tparam integer value The signed 16-bit integer value to write.
* @raise Error if offset is out of bounds or the data object is read-only.
*/
	{"setint16", luadata_setint16},
/***
* Extracts an unsigned 16-bit integer from the data object.
* Assumes host byte order.
* @function getuint16
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @treturn integer The unsigned 16-bit integer value at the specified offset.
* @raise Error if offset is out of bounds.
*/
	{"getuint16", luadata_getuint16},
/***
* Inserts an unsigned 16-bit integer into the data object.
* Assumes host byte order.
* @function setuint16
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @tparam integer value The unsigned 16-bit integer value to write.
* @raise Error if offset is out of bounds or the data object is read-only.
*/
	{"setuint16", luadata_setuint16},
/***
* Extracts a signed 32-bit integer from the data object.
* Assumes host byte order.
* @function getint32
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @treturn integer The signed 32-bit integer value at the specified offset.
* @raise Error if offset is out of bounds.
*/
	{"getint32", luadata_getint32},
/***
* Inserts a signed 32-bit integer into the data object.
* Assumes host byte order.
* @function setint32
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @tparam integer value The signed 32-bit integer value to write.
* @raise Error if offset is out of bounds or the data object is read-only.
*/
	{"setint32", luadata_setint32},
/***
* Extracts an unsigned 32-bit integer from the data object.
* Assumes host byte order.
* @function getuint32
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @treturn integer The unsigned 32-bit integer value at the specified offset.
* @raise Error if offset is out of bounds.
*/
	{"getuint32", luadata_getuint32},
/***
* Inserts an unsigned 32-bit integer into the data object.
* Assumes host byte order.
* @function setuint32
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @tparam integer value The unsigned 32-bit integer value to write.
* @raise Error if offset is out of bounds or the data object is read-only.
*/
	{"setuint32", luadata_setuint32},
/***
* Extracts a signed 64-bit integer from the data object.
* Assumes host byte order.
* @function getint64
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @treturn integer The signed 64-bit integer value at the specified offset.
* @raise Error if offset is out of bounds.
*/
	{"getint64", luadata_getint64},
/***
* Inserts a signed 64-bit integer into the data object.
* Assumes host byte order.
* @function setint64
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @tparam integer value The signed 64-bit integer value to write.
* @raise Error if offset is out of bounds or the data object is read-only.
*/
	{"setint64", luadata_setint64},
/***
* Extracts a Lua integer from the data object.
* Alias for `getint64`. Assumes host byte order.
* @function getnumber
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @treturn integer The Lua integer value at the specified offset.
* @raise Error if offset is out of bounds.
*/
	{"getnumber", luadata_getint64},
/***
* Inserts a Lua integer into the data object.
* Alias for `setint64`. Assumes host byte order.
* @function setnumber
* @tparam integer offset Byte offset from the start of the data block (0-indexed).
* @tparam integer value The Lua integer value to write.
* @raise Error if offset is out of bounds or the data object is read-only.
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

static inline void luadata_set(luadata_t *data, void *ptr, ptrdiff_t offset, size_t size, uint8_t opt)
{
	data->ptr = ptr;
	data->offset = offset;
	data->size = size;
	data->opt = opt;
}

static int luadata_lnew(lua_State *L)
{
	size_t size = (size_t)luaL_checkinteger(L, 1);
	lunatik_object_t *object = lunatik_newobject(L, &luadata_class, sizeof(luadata_t));
	luadata_t *data = (luadata_t *)object->private;

	luadata_set(data, lunatik_checkalloc(L, size), 0, size, LUADATA_OPT_FREE);
	return 1; /* object */
}

LUNATIK_NEWLIB(data, luadata_lib, &luadata_class, NULL);

static inline lunatik_object_t *luadata_create(void *ptr, size_t size, bool sleep, uint8_t opt)
{
	lunatik_object_t *object = lunatik_createobject(&luadata_class, sizeof(luadata_t), sleep);

	if (object != NULL) {
		luadata_t *data = (luadata_t *)object->private;
		luadata_set(data, ptr, 0, size, opt);
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

int luadata_reset(lunatik_object_t *object, void *ptr, ptrdiff_t offset, size_t size, uint8_t opt)
{
	luadata_t *data;

	lunatik_lock(object);
	data = (luadata_t *)object->private;

	if (data->opt & LUADATA_OPT_FREE) {
		lunatik_unlock(object);
		return -1;
	}

	opt = opt & LUADATA_OPT_KEEP ? data->opt : opt;
	luadata_set(data, ptr, offset, size, opt);

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

