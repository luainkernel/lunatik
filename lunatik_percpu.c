/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Set of runtimes, one per CPU id, running the same script.
* @module lunatik
*/

#include <linux/percpu.h>

#include <lunatik.h>

LUNATIK_OPENER(lunatik);

/***
* Set of runtimes, one per CPU id, running the same script. A callback dispatched
* through it reaches the instance of the CPU it fired on.
* @type percpu
*/
static void lunatik_releasepercpu(void *private)
{
	lunatik_object_t * __percpu *runtimes = lunatik_percpuruntimes(private);
	int cpu;

	for_each_possible_cpu(cpu) {
		lunatik_object_t *runtime = *per_cpu_ptr(runtimes, cpu);
		if (runtime != NULL) /* last reference: a stop would lock, and this can run in softirq */
			lunatik_putobject(runtime);
	}
	free_percpu(runtimes);
}

static inline lunatik_object_t * __percpu *lunatik_checkruntimes(lua_State *L, int ix)
{
	lunatik_object_t *object = lunatik_checkobject(L, ix);
	lunatik_argcheckclass(L, ix, object, &lunatik_percpu_class);
	return lunatik_percpuruntimes(object->private);
}

/***
* Closes every instance, releasing their Lua states.
* @function stop
*/
static int lunatik_stoppercpu(lua_State *L)
{
	lunatik_object_t * __percpu *runtimes = lunatik_checkruntimes(L, 1);
	int cpu;

	for_each_possible_cpu(cpu) {
		lunatik_object_t *runtime = *per_cpu_ptr(runtimes, cpu);
		if (runtime != NULL)
			lunatik_closeprivate(runtime);
	}
	return 0;
}

static const luaL_Reg lunatik_percpu_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_stoppercpu},
	{"stop", lunatik_stoppercpu},
	{NULL, NULL}
};

const lunatik_class_t lunatik_percpu_class = {
	.name = "percpu",
	.methods = lunatik_percpu_mt,
	.release = lunatik_releasepercpu,
	.opener = luaopen_lunatik,
	.opt = LUNATIK_OPT_PERCPU | LUNATIK_OPT_EXTERNAL,
};

/***
* Creates one runtime per CPU id, each loading the given script in the calling context.
* The instances are dispatched by CPU: see `lunatik.cpu` and `runner.run`.
* @function percpu
* @tparam string script script name (e.g., `"mymod"` loads `/lib/modules/lua/mymod.lua`)
* @tparam[opt="process"] string context execution context, as in `lunatik.runtime`
* @treturn percpu
* @raise if allocation fails or the script errors on load, after releasing the instances
*   already created
* @within lunatik
*/
int lunatik_percpu(lua_State *L)
{
	const char *script = luaL_checkstring(L, 1);
	lunatik_opt_t opt = lunatik_checkcontext(L, 2);
	int cpu;

	lunatik_object_t *object = lunatik_newobject(L, &lunatik_percpu_class, 0, opt);
	lunatik_object_t * __percpu *runtimes = alloc_percpu(lunatik_object_t *);

	if (runtimes == NULL)
		lunatik_enomem(L);
	object->private = runtimes;

	for_each_possible_cpu(cpu) {
		if (lunatik_newruntime(per_cpu_ptr(runtimes, cpu), L, script, opt, cpu) != 0) {
			object->private = NULL;
			lunatik_releasepercpu(runtimes); /* release the instances now, not on collection */
			lua_error(L);
		}
	}
	return 1;
}

