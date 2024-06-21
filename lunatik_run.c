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

#include <linux/module.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include "lunatik.h"
#include "lib/luarcu.h"

static lunatik_object_t *runtime;

static int __init lunatik_run_init(void)
{
	if ((lunatik_runtimes = luarcu_newtable(LUARCU_DEFAULT_SIZE, false)) == NULL)
		return -ENOMEM;
	return lunatik_runtime(&runtime, "driver", true);
}

static void __exit lunatik_run_exit(void)
{
	lunatik_putobject(lunatik_runtimes);
	lunatik_stop(runtime);
}

module_init(lunatik_run_init);
module_exit(lunatik_run_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ring-0.io>");

