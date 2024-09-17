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
	int ret = 0;

	if ((lunatik_env = luarcu_newtable(LUARCU_DEFAULT_SIZE, false)) == NULL)
		return -ENOMEM;

	if ((ret = lunatik_runtime(&runtime, "driver", true)) < 0) {
		pr_err("couldn't create driver runtime\n");
		lunatik_putobject(lunatik_env);
	}

	return ret;
}

static void __exit lunatik_run_exit(void)
{
	lunatik_putobject(lunatik_env);
	lunatik_stop(runtime);
}

module_init(lunatik_run_init);
module_exit(lunatik_run_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ring-0.io>");

