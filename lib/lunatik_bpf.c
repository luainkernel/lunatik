/* SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
 * SPDX-License-Identifier: MIT OR GPL-2.0-only
 */

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/kernel.h>

#include "lunatik.h"
#include "lunatik_bpf.h"

static int lunatik_bpf_handler(lua_State *L, struct lunatik_bpf_call *call)
{
	if (lunatik_getregistry(L, call->registry_key) != LUA_TFUNCTION) {
		pr_err("couldn't find callback\n");
		return -1;
	}

	lunatik_pushobject(L, call->obj);

	if (lua_pcall(L, 1, 0, 0) != LUA_OK) {
		pr_err("%s\n", lua_tostring(L, -1));
		lua_pop(L, 1);
		return -1;
	}

	return 0;
}

int lunatik_bpf_run(lunatik_object_t *runtime, lua_CFunction registry_key, lunatik_object_t *obj, void *ctx)
{
	struct lunatik_bpf_call call = {
		.registry_key = registry_key,
		.obj          = obj,
		.ctx          = ctx,
	};
	int ret = -1;

	lunatik_run(runtime, lunatik_bpf_handler, ret, &call);
	return ret;
}
EXPORT_SYMBOL_GPL(lunatik_bpf_run);
