/*
* SPDX-FileCopyrightText: (c) 2023-2024 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
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

