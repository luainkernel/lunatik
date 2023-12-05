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
#include <linux/kthread.h>
#include <linux/completion.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <lunatik.h>

typedef struct luathread_s {
	struct completion stopped;
	struct task_struct *task;
	lunatik_runtime_t *runtime;
} luathread_t;

#define LUATHREAD_MT	"thread"
#define LUATHREAD_FUNC	"__thread_task"

static inline luathread_t *luathread_checkudata(lua_State *L, int arg)
{
	luathread_t *thread = (luathread_t *)luaL_checkudata(L, arg, LUATHREAD_MT);
	luaL_argcheck(L, thread->task != NULL, arg, "invalid thread");
	return thread;
}

static int luathread_call(lua_State *L)
{
	lua_getglobal(L, LUATHREAD_FUNC);
	if (lua_pcall(L, 0, 1, 0) != LUA_OK) {
		pr_err("%s: %s\n", lua_tostring(L, -1), LUATHREAD_FUNC);
		return -1;
	}
	return (int)lua_tointeger(L, -1);
}

static int luathread_func(void *data)
{
	luathread_t *thread = (luathread_t *)data;
	int ret;

	lunatik_run(thread->runtime, luathread_call, ret);
	while (!kthread_should_stop())
		wait_for_completion_interruptible(&thread->stopped);
	return ret;
}

static int luathread_settask(lua_State *L)
{
	luaL_checktype(L, 1, LUA_TFUNCTION);
	lua_setglobal(L, LUATHREAD_FUNC);
	return 0;
}

static int luathread_shouldstop(lua_State *L)
{
	lua_pushboolean(L, (int)kthread_should_stop());
	return 1;
}

static int luathread_run(lua_State *L)
{
	lunatik_runtime_t *runtime = lunatik_checkruntime(L, 1);
	const char *name = luaL_checkstring(L, 2);
	luathread_t *thread = (luathread_t *)lua_newuserdatauv(L, sizeof(luathread_t), 0);

	lunatik_get(runtime);
	thread->runtime = runtime;

	luaL_setmetatable(L, LUATHREAD_MT);

	init_completion(&thread->stopped);
	thread->task = kthread_run(luathread_func, thread, name);
	if (IS_ERR(thread->task))
		luaL_error(L, "failed to create a new thread");

	return 1; /* userdata */
}

static int luathread_stop(lua_State *L)
{
	luathread_t *thread = luathread_checkudata(L, 1);

	complete(&thread->stopped);
	lua_pushinteger(L, kthread_stop(thread->task));
	thread->task = NULL;
	lunatik_put(thread->runtime);
	thread->runtime = NULL;
	return 1;
}

static const luaL_Reg luathread_lib[] = {
	{"run", luathread_run},
	{"stop", luathread_stop},
	{"settask", luathread_settask},
	{"shouldstop", luathread_shouldstop},
	{NULL, NULL}
};

static const luaL_Reg luathread_mt[] = {
	{"__gc", luathread_stop},
	{"__close", luathread_stop},
	{"stop", luathread_stop},
	{NULL, NULL}
};

static const lunatik_class_t luathread_class = {
	.name = LUATHREAD_MT,
	.methods = luathread_mt,
	.sleep = true,
};

LUNATIK_NEWLIB(thread, luathread_lib, &luathread_class, NULL);

static int __init luathread_init(void)
{
	return 0;
}

static void __exit luathread_exit(void)
{
}

module_init(luathread_init);
module_exit(luathread_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ring-0.io>");

