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

typedef struct luafoo_s {
	unsigned long counter;
} luafoo_t;

LUNATIK_PRIVATECHECKER(luafoo_check, luafoo_t *);

static int luafoo_inc(lua_State *L)
{
	/* lunatik_object_t *object = lunatik_toobject(L, 1); */
	/* luafoo_t *foo = (luafoo_t *)object->private; */

	luafoo_t *foo = luafoo_check(L, 1);

	foo->counter++;
	lua_pushinteger(L, foo->counter);
	return 1;
}

static void luafoo_release(void *private)
{
	luafoo_t *foo = (luafoo_t *)private;
	(void)foo; /* do nothing */
}

static int luafoo_new(lua_State *L);

static const luaL_Reg luafoo_lib[] = {
	{"new", luafoo_new},
	{NULL, NULL}
};

static const luaL_Reg luafoo_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"inc", luafoo_inc},
	{NULL, NULL}
};

static const lunatik_class_t luafoo_class = {
	.name = "foo",
	.methods = luafoo_mt,
	.release = luafoo_release,
	.sleep = false,
};

static int luafoo_new(lua_State *L)
{
	lunatik_object_t *object = lunatik_newobject(L, &luafoo_class, sizeof(luafoo_t));
	luafoo_t *foo = (luafoo_t *)object->private;
	foo->counter = 0;
	return 1; /* object */
}

LUNATIK_NEWLIB(foo, luafoo_lib, &luafoo_class, NULL);

static int __init luafoo_init(void)
{
	return 0;
}

static void __exit luafoo_exit(void)
{
}

module_init(luafoo_init);
module_exit(luafoo_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ring-0.io>");

