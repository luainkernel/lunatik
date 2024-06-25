/*
* Copyright (c) 2023-2024 ring-0 Ltda.
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

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/kernel.h>
#include <linux/module.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <lunatik.h>

typedef struct luadata_s {
	char *ptr;
	size_t size;
	bool free;
} luadata_t;

#define LUADATA_NUMBER_SZ	(sizeof(lua_Integer))

static int luadata_lnew(lua_State *L);

static inline luadata_t *luadata_checkdata(lua_State *L, lua_Integer *offset, lua_Integer length)
{
	lunatik_object_t *object = lunatik_toobject(L, 1);
	luadata_t *data = object->private;
	*offset = luaL_checkinteger(L, 2);
	luaL_argcheck(L, *offset >= 0 && length > 0 && *offset + length <= data->size, 2, "out of bounds");
	return data;
}

#define luadata_checkint(L, offset, T)	luadata_checkdata((L), &(offset), sizeof(T##_t))

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
LUADATA_NEWINT(uint64);
#endif

static int luadata_getstring(lua_State *L)
{
	lua_Integer offset;
	lua_Integer length = luaL_checkinteger(L, 3);
	luadata_t *data = luadata_checkdata(L, &offset, length);

	lua_pushlstring(L, data->ptr + offset, length);
	return 1;
}

static int luadata_setstring(lua_State *L)
{
	lua_Integer offset;
	size_t length;
	const char *str = luaL_checklstring(L, 3, &length); 
	luadata_t *data = luadata_checkdata(L, &offset, (lua_Integer)length);

	memcpy(data->ptr + offset, str, length);
	return 0;
}

static void luadata_release(void *private)
{
	luadata_t *data = (luadata_t *)private;
	if (data->free)
		lunatik_free(data->ptr);
}

static const luaL_Reg luadata_lib[] = {
	{"new", luadata_lnew},
	{NULL, NULL}
};

static const luaL_Reg luadata_mt[] = {
	{"__index", lunatik_monitorobject},
	{"__gc", lunatik_deleteobject},
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
	{"getuint64", luadata_getuint64},
	{"setuint64", luadata_setuint64},
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
	data->free = true;
	return 1; /* object */
}

LUNATIK_NEWLIB(data, luadata_lib, &luadata_class, NULL);

lunatik_object_t *luadata_new(void *ptr, size_t size, bool sleep)
{
	lunatik_object_t *object = lunatik_createobject(&luadata_class, sizeof(luadata_t), sleep);

	if (object != NULL) {
		luadata_t *data = (luadata_t *)object->private;
		data->ptr = ptr;
		data->size = size;
		data->free = false;
	}
	return object;
}
EXPORT_SYMBOL(luadata_new);

int luadata_reset(lunatik_object_t *object, void *ptr, size_t size)
{
	luadata_t *data;

	lunatik_lock(object);
	data = (luadata_t *)object->private;

	if (data->free) {
		lunatik_unlock(object);
		return -1;
	}

	data->ptr = ptr;
	data->size = size;
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

