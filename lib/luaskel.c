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

typedef struct luaskel_s {
	int unused;
} luaskel_t;

static int luaskel_nop(lua_State *L)
{
	lunatik_object_t *object = lunatik_toobject(L, 1);
	luaskel_t *skel = (luaskel_t *)object->private;
	(void)skel; /* do nothing */
	return 0;
}

static void luaskel_release(void *private)
{
	luaskel_t *skel = (luaskel_t *)private;
	(void)skel; /* do nothing */
}

static int luaskel_new(lua_State *L);

static const luaL_Reg luaskel_lib[] = {
	{"new", luaskel_new},
	{"nop", luaskel_nop},
	{NULL, NULL}
};

static const luaL_Reg luaskel_mt[] = {
	{"nop", luaskel_nop},
	{NULL, NULL}
};

static const lunatik_class_t luaskel_class = {
	.name = "skel",
	.methods = luaskel_mt,
	.release = luaskel_release,
	.sleep = false,
};

static int luaskel_new(lua_State *L)
{
	lunatik_object_t *object = lunatik_newobject(L, &luaskel_class, sizeof(luaskel_t));
	luaskel_t *skel = (luskel_t *)object->private;
	(void)private; /* do nothing */
	return 1; /* object */
}

LUNATIK_NEWLIB(skel, luaskel_lib, &luaskel_class, NULL);

static int __init luaskel_init(void)
{
	return 0;
}

static void __exit luaskel_exit(void)
{
}

module_init(luaskel_init);
module_exit(luaskel_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ring-0.io>");

