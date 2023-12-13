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
	lunatik_object_t *runtime;
	int result;
	size_t nargs;
	lunatik_object_t *argv[];
} luathread_t;

static int luathread_run(lua_State *L);

static int luathread_call(lua_State *L, luathread_t *thread)
{
	int nresult, i, nargs = thread->nargs;
	lunatik_object_t **argv = thread->argv;

	for (i = 0; i < nargs; i++)
		lunatik_cloneobject(L, argv[i]);

	if (lua_resume(L, NULL, nargs, &nresult) != LUA_OK) {
		pr_err("%s\n", lua_tostring(L, -1));
		return -1;
	}
	return (int)lua_tointeger(L, -1);
}

static int luathread_func(void *data)
{
	luathread_t *thread = (luathread_t *)data;
	int ret;

	lunatik_run(thread->runtime, luathread_call, ret, thread);
	while (!kthread_should_stop())
		wait_for_completion_interruptible(&thread->stopped);
	return ret;
}

static int luathread_shouldstop(lua_State *L)
{
	lua_pushboolean(L, (int)kthread_should_stop());
	return 1;
}

static void luathread_release(void *private)
{
	luathread_t *thread = (luathread_t *)private;

	if (thread->task != NULL) { /* has stopped? */
		complete(&thread->stopped);
		thread->result = kthread_stop(thread->task);
		thread->task = NULL;
		lunatik_putobject(thread->runtime);
		thread->runtime = NULL;
	}
}

static int luathread_stop(lua_State *L)
{
	lunatik_object_t *object = lunatik_toobject(L, 1);
	luathread_t *thread = (luathread_t *)object->private;

	luathread_release(thread);
	lua_pushinteger(L, thread->result);
	return 1;
}

static const luaL_Reg luathread_lib[] = {
	{"run", luathread_run},
	{"stop", luathread_stop},
	{"shouldstop", luathread_shouldstop},
	{NULL, NULL}
};

static const luaL_Reg luathread_mt[] = {
	{"__index", lunatik_monitorobject},
	{"__gc", lunatik_deleteobject},
	{"stop", luathread_stop},
	{NULL, NULL}
};

static const lunatik_class_t luathread_class = {
	.name = "thread",
	.methods = luathread_mt,
	.release = luathread_release,
	.sleep = true,
};

#define luathread_size(n)	(sizeof(luathread_t) + sizeof(lunatik_object_t *) * (n))

static int luathread_run(lua_State *L)
{
	lunatik_object_t *runtime = lunatik_checkobject(L, 1);
	const char *name = luaL_checkstring(L, 2);
	int i, nargs = lua_gettop(L) - 2;
	lunatik_object_t *object = lunatik_newobject(L, &luathread_class, luathread_size(nargs));
	luathread_t *thread = object->private;
	lunatik_object_t **argv = thread->argv;

	for (i = 0; i < nargs; i++) {
		lunatik_object_t *arg = lunatik_checkobject(L, 3 + i);
		lunatik_getobject(arg);
		argv[i] = arg;
	}
	thread->nargs = nargs;

	lunatik_getobject(runtime);
	thread->runtime = runtime;

	init_completion(&thread->stopped);
	thread->task = kthread_run(luathread_func, thread, name);
	if (IS_ERR(thread->task))
		luaL_error(L, "failed to create a new thread");

	return 1; /* object */
}

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

