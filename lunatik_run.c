/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include <linux/module.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include "lunatik.h"
#include "lib/luarcu.h"

static lunatik_object_t *runtime;

static void lunatik_run_putenv(void)
{
	lunatik_object_t *env = rcu_replace_pointer(lunatik_env, NULL, true);

	synchronize_rcu();
	lunatik_putobject(env);
}

static int __init lunatik_run_init(void)
{
	lunatik_object_t *env = luarcu_newtable(LUARCU_DEFAULT_SIZE, LUNATIK_OPT_NONE);
	int ret = 0;

	if (env == NULL)
		return -ENOMEM;
	rcu_assign_pointer(lunatik_env, env);

	if ((ret = lunatik_runtime(&runtime, "lunatik/driver", LUNATIK_OPT_NONE)) < 0) {
		pr_err("couldn't create driver runtime\n");
		lunatik_run_putenv();
	}

	return ret;
}

static void __exit lunatik_run_exit(void)
{
	lunatik_run_putenv();
	lunatik_stop(runtime);
}

module_init(lunatik_run_init);
module_exit(lunatik_run_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_VERSION(LUNATIK_RELEASE);
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ringzero.com.br>");
MODULE_DESCRIPTION("Lunatik driver runtime, which runs Lua scripts in the kernel");

