/*
* SPDX-FileCopyrightText: (c) 2023-2024 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/completion.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <lunatik.h>

typedef struct luacompletion_s {
	struct completion event;
} luacompletion_t;

LUNATIK_PRIVATECHECKER(luacompletion_check, luacompletion_t *);

static int luacompletion_complete(lua_State *L)
{
	luacompletion_t *completion = luacompletion_check(L, 1);

	complete(&completion->event);
	return 0;
}

static int luacompletion_wait(lua_State *L)
{
	luacompletion_t *completion = luacompletion_check(L, 1);

	wait_for_completion(&completion->event);
	return 0;
}

static int luacompletion_wait_timeout(lua_State *L)
{
	luacompletion_t *completion = luacompletion_check(L, 1);
	unsigned long timeout = (unsigned long) luaL_checkinteger(L, 2);
	unsigned long ret;

	ret = wait_for_completion_timeout(&completion->event, msecs_to_jiffies(timeout));
	lua_pushboolean(L, ret > 0 ? true : false);
	return 1;
}


static void luacompletion_release(void *private)
{
	luacompletion_t *completion = (luacompletion_t *)private;
	(void)completion; /* do nothing */
}

static int luacompletion_new(lua_State *L);

static const luaL_Reg luacompletion_lib[] = {
	{"new", luacompletion_new},
	{NULL, NULL}
};

static const luaL_Reg luacompletion_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"complete", luacompletion_complete},
	{"wait", luacompletion_wait},
	{"wait_timeout", luacompletion_wait_timeout},
	{NULL, NULL}
};

static const lunatik_class_t luacompletion_class = {
	.name = "completion",
	.methods = luacompletion_mt,
	.release = luacompletion_release,
	.sleep = true,
};

static int luacompletion_new(lua_State *L)
{
	lunatik_object_t *object = lunatik_newobject(L, &luacompletion_class, sizeof(luacompletion_t));
	luacompletion_t *completion = (luacompletion_t *)object->private;

	init_completion(&completion->event);
	return 1;
}

LUNATIK_NEWLIB(completion, luacompletion_lib, &luacompletion_class, NULL);

static int __init luacompletion_init(void)
{
	return 0;
}

static void __exit luacompletion_exit(void)
{
}

module_init(luacompletion_init);
module_exit(luacompletion_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ring-0.io>");

