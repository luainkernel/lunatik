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

LUNATIK_OBJECTCHECKER(luacompletion_check, struct completion *);

static int luacompletion_complete(lua_State *L)
{
	struct completion *completion = luacompletion_check(L, 1);

	complete(completion);
	return 0;
}

static int luacompletion_wait(lua_State *L)
{
	struct completion *completion = luacompletion_check(L, 1);
	lua_Integer timeout = luaL_optinteger(L, 2, MAX_SCHEDULE_TIMEOUT);
	unsigned long timeout_jiffies = msecs_to_jiffies((unsigned long)timeout);
	long ret;

	lunatik_checkruntime(L, true);
	ret = wait_for_completion_interruptible_timeout(completion, timeout_jiffies);
	if (ret > 0) {
		lua_pushboolean(L, true);
		return 1;		
	}

	lua_pushnil(L);
	switch (ret) {
	case 0:
		lua_pushliteral(L, "timeout");
		break;
	case -ERESTARTSYS:
		lua_pushliteral(L, "interrupt");
		break;
	default:
		lua_pushliteral(L, "unknown");
		break;
	}
	return 2;
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
	{NULL, NULL}
};

static const lunatik_class_t luacompletion_class = {
	.name = "completion",
	.methods = luacompletion_mt,
	.sleep = false,
};

static int luacompletion_new(lua_State *L)
{
	lunatik_object_t *object = lunatik_newobject(L, &luacompletion_class, sizeof(struct completion));
	struct completion *completion = (struct completion *)object->private;

	init_completion(completion);
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
MODULE_AUTHOR("Savio Sena <savio.sena@gmail.com>");

