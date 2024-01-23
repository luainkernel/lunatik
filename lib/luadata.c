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

static int luadata_new(lua_State *L);

static inline luadata_t *luadata_checkdata(lua_State *L, lua_Integer *offset, lua_Integer length)
{
	lunatik_object_t *object = lunatik_toobject(L, 1);
	luadata_t *data = object->private;
	*offset = luaL_checkinteger(L, 2);
	luaL_argcheck(L, *offset >= 0 && length > 0 && *offset + length <= data->size, 2, "out of bounds");
	return data;
}

static int luadata_getnumber(lua_State *L)
{
	lua_Integer offset;
	luadata_t *data = luadata_checkdata(L, &offset, LUADATA_NUMBER_SZ);

	lua_pushinteger(L, *(lua_Integer *)(data->ptr + offset));
	return 1;
}

static int luadata_setnumber(lua_State *L)
{
	lua_Integer offset;
	luadata_t *data = luadata_checkdata(L, &offset, LUADATA_NUMBER_SZ);

	*(lua_Integer *)(data->ptr + offset) = luaL_checkinteger(L, 3);
	return 0;
}

static int luadata_getbyte(lua_State *L)
{
	lua_Integer offset;
	luadata_t *data = luadata_checkdata(L, &offset, 1);

	lua_pushinteger(L, (lua_Integer)*(data->ptr + offset));
	return 1;
}

static int luadata_setbyte(lua_State *L)
{
	lua_Integer offset;
	luadata_t *data = luadata_checkdata(L, &offset, 1);

	*(data->ptr + offset) = luaL_checkinteger(L, 3);
	return 0;
}

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
	{"new", luadata_new},
	{NULL, NULL}
};

static const luaL_Reg luadata_mt[] = {
	{"__index", lunatik_monitorobject},
	{"__gc", lunatik_deleteobject},
	{"getnumber", luadata_getnumber},
	{"setnumber", luadata_setnumber},
	{"getbyte", luadata_getbyte},
	{"setbyte", luadata_setbyte},
	{"getstring", luadata_getstring},
	{"setstring", luadata_setstring},
	{NULL, NULL}
};

static const lunatik_class_t luadata_class = {
	.name = "data",
	.methods = luadata_mt,
	.release = luadata_release,
};

static int luadata_new(lua_State *L)
{
	size_t size = (size_t)luaL_checkinteger(L, 1);
	lunatik_object_t *object = lunatik_newobject(L, &luadata_class, sizeof(luadata_t));
	luadata_t *data = object->private;

	data->ptr = lunatik_checkalloc(L, size);
	data->size = size;
	data->free = true;
	return 1; /* object */
}

LUNATIK_NEWLIB(data, luadata_lib, &luadata_class, NULL);

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

