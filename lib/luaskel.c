/*
* SPDX-FileCopyrightText: (c) 2023-2025 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
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

LUNATIK_PRIVATECHECKER(luaskel_check, luaskel_t *);

static int luaskel_nop(lua_State *L)
{
	luaskel_t *skel = luaskel_check(L, 1)
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
	.flags = false,
};

static int luaskel_new(lua_State *L)
{
	lunatik_object_t *object = lunatik_newobject(L, &luaskel_class, sizeof(luaskel_t));
	luaskel_t *skel = (luaskel_t *)object->private;
	(void)skel; /* do nothing */
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

