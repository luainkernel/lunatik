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
static lunatik_object_t *lunatik_finddata(lunatik_percpu_t *percpu, const lunatik_class_t *class)
{
	unsigned int i;

	for (i = 0; i < percpu->ndata; i++) {
		if (percpu->data[i]->class == class)
			return percpu->data[i];
	}
	return NULL;
}

static lunatik_object_t *lunatik_newdata(lua_State *L, lunatik_object_t *object, const lunatik_class_t *class, size_t size)
{
	lunatik_percpu_t *percpu = lunatik_topercpu(object);
	lunatik_object_t *data;

	percpu->data = lunatik_checknull(L, lunatik_realloc(L, percpu->data, (percpu->ndata + 1) * sizeof(lunatik_object_t *)));
	if ((data = lunatik_createobject(class, size, LUNATIK_OPT_NONE)) == NULL)
		lunatik_enomem(L);
	lunatik_getobject(object); /* stop releases it; collection never sees data outstanding */
	percpu->data[percpu->ndata++] = data;
	return data;
}

lunatik_object_t *lunatik_percpudata(lua_State *L, const lunatik_class_t *class, size_t size)
{
	lunatik_object_t *object = lunatik_getpercpu(L);

	if (object == NULL)
		return NULL;

	if (lunatik_isready(lunatik_toruntime(L)))
		luaL_error(L, "not allowed after module load");

	lunatik_object_t *data = lunatik_finddata(lunatik_topercpu(object), class);
	return data != NULL ? data : lunatik_newdata(L, object, class, size);
}
EXPORT_SYMBOL(lunatik_percpudata);

static void lunatik_stopdata(lunatik_object_t *object)
{
	lunatik_percpu_t *percpu = lunatik_topercpu(object);
	unsigned int i;

	for (i = 0; i < percpu->ndata; i++) {
		lunatik_closeprivate(percpu->data[i]); /* the class's release runs here, before the instances close */
		lunatik_putobject(percpu->data[i]);
		lunatik_putobject(object);
	}
	percpu->ndata = 0;
	lunatik_free(percpu->data);
	percpu->data = NULL;
}

#define lunatik_foreachinstance(percpu, cpu, runtime)	\
	for_each_possible_cpu(cpu)			\
		if ((runtime = *per_cpu_ptr((percpu)->runtimes, cpu)) != NULL)

static void lunatik_closeinstances(lunatik_percpu_t *percpu)
{
	lunatik_object_t *runtime;
	int cpu;

	lunatik_foreachinstance(percpu, cpu, runtime)
		lunatik_closeprivate(runtime);
}

static void lunatik_releasepercpu(void *private)
{
	lunatik_percpu_t *percpu = (lunatik_percpu_t *)private;
	lunatik_object_t *runtime;
	int cpu;

	if (percpu->runtimes == NULL)
		return;

	lunatik_foreachinstance(percpu, cpu, runtime)
		lunatik_putobject(runtime); /* may run in softirq: a put, never a stop */
	free_percpu(percpu->runtimes);
}

static inline lunatik_object_t *lunatik_checkpercpuobject(lua_State *L, int ix)
{
	lunatik_object_t *object = lunatik_checkobject(L, ix);
	lunatik_argcheckclass(L, ix, object, &lunatik_percpu_class);
	return object;
}

/***
* Closes the objects the instances share, then every instance, releasing their Lua states.
* @function stop
*/
static int lunatik_stoppercpu(lua_State *L)
{
	lunatik_object_t *object = lunatik_checkpercpuobject(L, 1);

	lunatik_stopdata(object);
	lunatik_closeinstances(lunatik_topercpu(object));
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
	.opt = LUNATIK_OPT_PERCPU,
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

	lunatik_object_t *object = lunatik_newobject(L, &lunatik_percpu_class, sizeof(lunatik_percpu_t), opt);
	lunatik_percpu_t *percpu = lunatik_topercpu(object);

	if ((percpu->runtimes = alloc_percpu(lunatik_object_t *)) == NULL)
		lunatik_enomem(L);

	for_each_possible_cpu(cpu) {
		if (lunatik_newruntime(per_cpu_ptr(percpu->runtimes, cpu), L, script, opt, object, cpu) != 0) {
			lunatik_stopdata(object);
			lunatik_closeprivate(object); /* release the instances now, not on collection */
			lua_error(L);
		}
	}
	return 1;
}

