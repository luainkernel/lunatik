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
* through it reaches the runtime of the CPU it fired on.
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
	size_t osize = percpu->ndata * sizeof(lunatik_object_t *);
	lunatik_object_t *data;

	percpu->data = lunatik_checknull(L, lunatik_realloc(L, percpu->data, osize, osize + sizeof(lunatik_object_t *)));
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

static lunatik_shared_t *lunatik_findshared(struct hlist_head *head, const lunatik_sharing_t *sharing,
	const lunatik_shared_t *spec)
{
	lunatik_shared_t *shared;

	hlist_for_each_entry(shared, head, node) {
		if (sharing->match(shared, spec))
			return shared;
	}
	return NULL;
}

static lunatik_shared_t *lunatik_newshared(lua_State *L, lunatik_object_t *runtime,
	const lunatik_sharing_t *sharing, const lunatik_shared_t *spec)
{
	lunatik_shared_t *shared = lunatik_checkalloc(L, sharing->size);

	memcpy(shared, spec, sharing->size);
	shared->runtime = runtime;
	sharing->arm(L, shared);
	return shared;
}

lunatik_shared_t *lunatik_own(lua_State *L, lunatik_object_t *runtime, const lunatik_sharing_t *sharing,
	const lunatik_shared_t *spec)
{
	lunatik_shared_t *shared = lunatik_newshared(L, runtime, sharing, spec);

	lunatik_getobject(runtime); /* a percpu object is held by its data; a plain runtime is held here */
	return shared;
}
EXPORT_SYMBOL(lunatik_own);

lunatik_shared_t *lunatik_share(lua_State *L, lunatik_object_t *percpu, const lunatik_sharing_t *sharing,
	const lunatik_shared_t *spec)
{
	struct hlist_head *head = lunatik_percpudata(L, sharing->class, sizeof(struct hlist_head))->private;
	lunatik_shared_t *shared = lunatik_findshared(head, sharing, spec);

	if (shared == NULL) {
		shared = lunatik_newshared(L, percpu, sharing, spec);
		hlist_add_head(&shared->node, head);
	}
	else if (lunatik_getregistry(L, shared) != LUA_TNIL)
		luaL_error(L, "%s", sharing->registered);
	else
		lua_pop(L, 1);
	return shared;
}
EXPORT_SYMBOL(lunatik_share);

static void lunatik_stopdata(lunatik_object_t *object)
{
	lunatik_percpu_t *percpu = lunatik_topercpu(object);
	unsigned int i;

	for (i = 0; i < percpu->ndata; i++) {
		lunatik_closeprivate(percpu->data[i]); /* the class's release runs here, before the runtimes close */
		lunatik_putobject(percpu->data[i]);
		lunatik_putobject(object);
	}
	percpu->ndata = 0;
	lunatik_free(percpu->data);
	percpu->data = NULL;
}

#define lunatik_foreachruntime(percpu, cpu, runtime)	\
	for_each_possible_cpu(cpu)			\
		if ((runtime = *per_cpu_ptr((percpu)->runtimes, cpu)) != NULL)

static void lunatik_closeruntimes(lunatik_percpu_t *percpu)
{
	lunatik_object_t *runtime;
	int cpu;

	lunatik_foreachruntime(percpu, cpu, runtime)
		lunatik_closeprivate(runtime);
}

static void lunatik_releasepercpu(void *private)
{
	lunatik_percpu_t *percpu = (lunatik_percpu_t *)private;
	lunatik_object_t *runtime;
	int cpu;

	if (percpu->runtimes == NULL)
		return;

	lunatik_foreachruntime(percpu, cpu, runtime)
		lunatik_putobject(runtime); /* may run in softirq: a put, never a stop */
	free_percpu(percpu->runtimes);
}

static int lunatik_resumeruntime(lua_State *L, lunatik_object_t *runtime, int nargs, char *error)
{
	int nresults = -ENXIO;

	lunatik_lock(runtime); /* a runtime dispatches as soon as its script registers a hook */
	if (likely(lunatik_isready(runtime))) {
		lua_State *Lto = lunatik_getstate(runtime);

		nresults = lunatik_resume(Lto, L, 2, nargs);
		if (nresults < 0) /* the caller raises: a longjmp here would skip the unlock */
			strscpy(error, lua_tostring(Lto, -1) ?: "error object is not a string", LUAL_BUFFERSIZE);
		lua_pop(Lto, nresults < 0 ? 1 : nresults); /* the message, or the yield a broadcast drops */
	}
	lunatik_unlock(runtime);
	return nresults;
}

/***
* Resumes every runtime, as `runtime:resume` does, delivering the same objects to each. Nothing
* comes back: a broadcast has no single set of values to return, so what a runtime yields is
* dropped.
* @function resume
* @param ... objects delivered to each runtime as the return values of its `coroutine.yield()`
* @raise "null pointer dereference" if the object has been stopped; otherwise the error of the
*   first runtime that refuses a value it cannot carry or raises on resumption, naming its CPU,
*   with the runtimes after it not resumed. A runtime that refuses a value stays where it yielded;
*   one that raises is dead, so every later resume delivers to the CPUs before it again and fails
*   on it again
*/
static int lunatik_resumepercpu(lua_State *L)
{
	lunatik_object_t *object = lunatik_checkobjectclass(L, 1, &lunatik_percpu_class);
	lunatik_percpu_t *percpu = lunatik_topercpu(object);
	int nargs = lua_gettop(L) - 1;
	char error[LUAL_BUFFERSIZE];
	lunatik_object_t *runtime;
	int cpu;

	lunatik_foreachruntime(percpu, cpu, runtime) {
		int status = lunatik_resumeruntime(L, runtime, nargs, error);

		luaL_argcheck(L, status != -ENXIO, 1, LUNATIK_ERR_NULLPTR);
		if (status < 0)
			luaL_error(L, "cpu %d: %s", cpu, error);
	}
	return 0;
}

/***
* Closes the objects the runtimes share, then every runtime, releasing their Lua states.
* @function stop
*/
static int lunatik_stoppercpu(lua_State *L)
{
	lunatik_object_t *object = lunatik_checkobjectclass(L, 1, &lunatik_percpu_class);

	lunatik_stopdata(object);
	lunatik_closeruntimes(lunatik_topercpu(object));
	return 0;
}

static const luaL_Reg lunatik_percpu_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_stoppercpu},
	{"stop", lunatik_stoppercpu},
	{"resume", lunatik_resumepercpu},
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
* The runtimes are dispatched by CPU: see `lunatik.cpu` and `runner.run`.
* @function percpu
* @tparam string script script name (e.g., `"mymod"` loads `/lib/modules/lua/mymod.lua`)
* @tparam[opt="process"] string context execution context, as in `lunatik.runtime`
* @treturn percpu
* @raise if allocation fails or the script errors on load, after releasing the runtimes
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
			lunatik_closeprivate(object); /* release the runtimes now, not on collection */
			lua_error(L);
		}
	}
	return 1;
}

