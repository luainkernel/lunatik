/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Manages Lunatik runtimes — isolated Lua states running in the kernel.
* In a softirq or hardirq runtime the module holds only `cpu` and `_ENV`: `runtime` and `percpu`
* exist in a process runtime alone, and the `io` library is not opened there and `require` refuses it.
* @module lunatik
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/module.h>
#include <linux/mm.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include "lunatik.h"
#include "lunatik_core.h"
#include "lunatik_sym.h"

/***
* Shared `rcu.table` through which scripts exchange objects. Its keys `runtimes` and `threads`
* are reserved for `lunatik.runner`, which records there the scripts it runs and spawns. It is
* present in a runtime created while the `lunatik_run` module is loaded.
* @field _ENV
* @within lunatik
*/

#ifdef LUNATIK_RUNTIME
lunatik_object_t *lunatik_env;
EXPORT_SYMBOL(lunatik_env);
struct task_struct *lunatik_rtnl;	/* one task holds RTNL at a time */
EXPORT_SYMBOL(lunatik_rtnl);
EXPORT_SYMBOL(luaS_hash);	/* required by luarcu */

static inline void lunatik_setversion(lua_State *L)
{
	lua_pushstring(L, LUNATIK_VERSION);
	lua_setglobal(L, "_LUNATIK_VERSION");
}

#define lunatik_cankrealloc(p, n, f)	\
	(((f) == GFP_ATOMIC || (n) <= PAGE_SIZE) && (!is_vmalloc_addr(p) || (p) == NULL))

/***
* Isolated Lua state running within the Linux kernel.
* @type runtime
*/
static void *lunatik_alloc(void *ud, void *optr, size_t osize, size_t nsize)
{
	if (nsize == 0) {
		kvfree(optr);
		return NULL;
	}

	lunatik_object_t *runtime = (lunatik_object_t *)ud;
	gfp_t gfp = lunatik_gfp(runtime);
	gfp_t nowarn = gfp | __GFP_NOWARN; /* Lua raises on a NULL */

	if (lunatik_cankrealloc(optr, nsize, gfp))
		return krealloc(optr, nsize, nowarn);

	void *nptr = gfp == GFP_KERNEL ? kvmalloc(nsize, nowarn) : kmalloc(nsize, nowarn);
	if (nptr == NULL) /* if shrinking, it's safe to return optr */
		return nsize <= osize ? optr : nptr;
	else if (optr != NULL) {
		memcpy(nptr, optr, min(osize, nsize));
		kvfree(optr);
	}
	return nptr;
}

static inline void lunatik_runerror(lua_State *L, const char *errmsg)
{
	if (L)
		lua_pushstring(L, errmsg);
	else
		pr_err("%s\n", errmsg);
}

static void lunatik_releaseruntime(void *private)
{
	lua_State *L = (lua_State *)private;

	lunatik_cstack(lunatik_toruntime(L)) = current_stack_pointer;
	lua_close(L);
}

int lunatik_stop(lunatik_object_t *runtime)
{
	lunatik_closeprivate(runtime);
	return lunatik_putobject(runtime);
}
EXPORT_SYMBOL(lunatik_stop);

static int lunatik_lruntime(lua_State *L);

LUNATIK_PRIVATECHECKER(lunatik_check, lua_State *, &lunatik_runtime_class);

static int lunatik_lcopyobjects(lua_State *L)
{
	lua_State *Lfrom = (lua_State *)lua_touserdata(L, 1);
	int ixfrom = lua_tointeger(L, 2);
	int nobjects = lua_tointeger(L, 3);
	int i;

	luaL_checkstack(L, nobjects, "too many objects");
	for (i = 0; i < nobjects; i++) {
		lunatik_object_t **pobject = lunatik_testobject(Lfrom, ixfrom + i);

		luaL_argcheck(L, pobject != NULL, i + 1, "invalid object");
		lunatik_pushobject(L, *pobject);
	}
	return nobjects;
}

int lunatik_copyobjects(lua_State *Lto, lua_State *Lfrom, int ixfrom, int nobjects)
{
	lua_pushcfunction(Lto, lunatik_lcopyobjects);
	lua_pushlightuserdata(Lto, Lfrom);
	lua_pushinteger(Lto, ixfrom);
	lua_pushinteger(Lto, nobjects);

	return lua_pcall(Lto, 3, nobjects, 0);
}
EXPORT_SYMBOL(lunatik_copyobjects);

int lunatik_resume(lua_State *Lto, lua_State *Lfrom, int ixfrom, int nargs)
{
	lunatik_object_t *runtime = lunatik_toruntime(Lto);
	int nresults;

	lunatik_cstack(runtime) = lunatik_cstack(lunatik_toruntime(Lfrom));
	int status = lunatik_copyobjects(Lto, Lfrom, ixfrom, nargs);

	if (status == LUA_OK)
		status = lua_resume(Lto, Lfrom, nargs, &nresults);
	lunatik_cstack(runtime) = 0;
	return status > LUA_YIELD ? -ECANCELED : nresults;
}

/***
* Resumes a runtime as the function `coroutine.wrap` returns resumes a coroutine: an error is
* raised, not returned.
* The runtime's script returns a function: the first resume calls it with the objects as its
* arguments, and each later one delivers them as the return values of the `coroutine.yield()` it
* is suspended in. Only Lunatik objects cross between the runtimes, in either direction.
* @function resume
* @param ... objects passed to the function, or returned by its `coroutine.yield()`
* @treturn vararg objects passed to the next `coroutine.yield()`, or returned by the function
* @raise "closed object" if the runtime has been stopped; "invalid object" or
*   "cannot share SINGLE object" if a value cannot cross, numbering the
*   arguments on the way in and the yielded values on the way back, or the error raised on
*   resumption; "not allowed from the runtime itself" from under the runtime's own lock, the
*   contexts `stop` names, where the resumption would wait on it; "EINTR" if the stop of the
*   calling kernel thread, or a fatal signal to any other task, ends its wait for the runtime's
*   lock
* @usage
*   -- echo.lua, a runtime that hands back what it receives
*   local function echo(object)
*   	while true do
*   		object = coroutine.yield(object)
*   	end
*   end
*   return echo
*
*   -- the script that drives it
*   local lunatik = require("lunatik")
*   local data    = require("data")
*   local runtime <close> = lunatik.runtime("echo")
*   local back = runtime:resume(data.new(4)) -- calls echo, which yields the object back
*/
static int lunatik_lresume(lua_State *L)
{
	lua_State *Lto = lunatik_check(L, 1);
	int nargs = lua_gettop(L) - 1;
	int nresults = lunatik_resume(Lto, L, 2, nargs);

	if (nresults < 0) {
		lua_pushfstring(L, "%s\n", lunatik_errmsg(Lto));
		lua_pop(Lto, 1); /* error message */
		lua_error(L);
	}

	int status = lunatik_copyobjects(L, Lto, -nresults, nresults);
	lua_pop(Lto, nresults);
	if (status != LUA_OK)
		lua_error(L);
	return nresults;
}

/***
* Returns the CPU id a percpu runtime serves.
* Ranges from `0` to `cpu.maxid()`; see `runner.run`.
* @function cpu
* @treturn integer CPU id, or `nil` on a plain runtime
* @within lunatik
*/
static int lunatik_cpu(lua_State *L)
{
	lunatik_pushoptinteger(L, lunatik_hascpu(L), lunatik_getcpu(L));
	return 1;
}

static const luaL_Reg lunatik_lib[] = {
	{"runtime", lunatik_lruntime},
	{"percpu", lunatik_percpu},
	{"cpu", lunatik_cpu},
	{NULL, NULL}
};

static const luaL_Reg lunatik_stub_lib[] = {
	{"cpu", lunatik_cpu},
	{NULL, NULL}
};

/***
* Stops the runtime and releases all associated kernel resources.
* @function stop
* @raise "not allowed from the runtime itself" from the runtime's own callback, a `device` file
*   operation, a `thread` body or a resumed body, where the close would wait on the lock that task
*   holds; "EINTR" if the stop of the calling kernel thread, or a fatal signal to any other task,
*   ends its wait for the runtime's lock
*/
static int lunatik_lstop(lua_State *L)
{
	lunatik_object_t *runtime = lunatik_checkobjectclass(L, 1, &lunatik_runtime_class);

	lunatik_checkowner(L, runtime);
	lunatik_try(L, lunatik_closekillable, runtime);
	return 0;
}

static const luaL_Reg lunatik_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_lstop},
	{"stop", lunatik_lstop},
	{"resume", lunatik_lresume},
	{NULL, NULL}
};

LUNATIK_OPENER(lunatik);
LUNATIK_OPENER(lunatik_stub);
const lunatik_class_t lunatik_runtime_class = {
	.name = "lunatik.runtime",
	.methods = lunatik_mt,
	.release = lunatik_releaseruntime,
	.opt = LUNATIK_OPT_MONITOR | LUNATIK_OPT_EXTERNAL,
	.owner = THIS_MODULE,
};
EXPORT_SYMBOL(lunatik_runtime_class);

static inline void lunatik_setready(lunatik_object_t *runtime)
{
	lunatik_lock(runtime); /* publish ready under the same lock readers take */
	WRITE_ONCE(lunatik_runtimeof(runtime)->ready, true);
	lunatik_unlock(runtime);
}

static int lunatik_callsleepable(lua_State *L)
{
	lunatik_checkarmed(L);
	lua_pushvalue(L, lua_upvalueindex(1));
	lua_insert(L, 1);
	lua_call(L, lua_gettop(L) - 1, LUA_MULTRET);
	return lua_gettop(L);
}

#define LUNATIK_SEARCHER_C	2
#define LUNATIK_SEARCHER_LUA	3

static int lunatik_searchbinding(lua_State *L)
{
	lua_pushvalue(L, lua_upvalueindex(1));
	lua_insert(L, 1);
	return lua_pcall(L, lua_gettop(L) - 1, 2, 0) == LUA_OK ? 2 : 1; /* the C searcher raises on a miss */
}

static void lunatik_ordersearchers(lua_State *L)
{
	lua_getglobal(L, LUA_LOADLIBNAME);
	lua_getfield(L, -1, "searchers");
	lua_rawgeti(L, -1, LUNATIK_SEARCHER_C); /* the fork's order is preload, Lua, C */
	lua_rawgeti(L, -2, LUNATIK_SEARCHER_LUA);
	lua_pushcclosure(L, lunatik_searchbinding, 1);
	lua_rawseti(L, -3, LUNATIK_SEARCHER_C);
	lua_rawseti(L, -2, LUNATIK_SEARCHER_LUA);
	lua_pop(L, 2); /* searchers and package */
}

static void lunatik_guardpackage(lua_State *L)
{
	/* the entries that open a file or load a binding, as the searchers below do */
	static const char *const fields[] = {"searchpath", "loadlib", NULL};
	const char *const *field;
	int ix;

	lua_getglobal(L, LUA_LOADLIBNAME);
	for (field = fields; *field != NULL; field++) {
		lua_getfield(L, -1, *field);
		lua_pushcclosure(L, lunatik_callsleepable, 1);
		lua_setfield(L, -2, *field);
	}

	lua_getfield(L, -1, "searchers");
	for (ix = LUNATIK_SEARCHER_C; ix <= LUNATIK_SEARCHER_LUA; ix++) {
		lua_rawgeti(L, -1, ix);
		lua_pushcclosure(L, lunatik_callsleepable, 1);
		lua_rawseti(L, -2, ix);
	}
	lua_pop(L, 2); /* searchers and package */
}

static int lunatik_refuseio(lua_State *L)
{
	return luaL_error(L, "'%s': %s", LUA_IOLIBNAME, LUNATIK_ERR_CONTEXT);
}

static void lunatik_guardio(lua_State *L)
{
	luaL_getsubtable(L, LUA_REGISTRYINDEX, LUA_PRELOAD_TABLE);
	lua_pushcfunction(L, lunatik_refuseio);
	lua_setfield(L, -2, LUA_IOLIBNAME);
	lua_pop(L, 1); /* preload table */
}

static int lunatik_runscript(lua_State *L)
{
	const char *script = lua_pushfstring(L, "%s%s.lua", LUA_ROOT, lua_touserdata(L, 1));
	int scriptix = lua_gettop(L);

	lunatik_setversion(L);

	if (!(lunatik_isirq(lunatik_toruntime(L)->opt))) {
		luaL_openlibs(L);
		lunatik_ordersearchers(L);
		luaL_requiref(L, "lunatik", luaopen_lunatik, 0);
	}
	else {
		luaL_openselectedlibs(L, ~LUA_IOLIBK, 0);
		lunatik_ordersearchers(L);
		lunatik_guardpackage(L);
		lunatik_guardio(L);
		luaL_requiref(L, "lunatik", luaopen_lunatik_stub, 0);
	}

	if (lunatik_env != NULL) {
		lunatik_pushobject(L, lunatik_env);
		lua_setfield(L, -2, "_ENV");
	}
	lua_pop(L, 1); /* lunatik library */

	if (lunatik_loadfile(L, script, NULL) != LUA_OK)
		lua_error(L);

	lua_call(L, 0, 1);
	lua_remove(L, scriptix);
	return 1; /* callback */
}

int lunatik_newruntime(lunatik_object_t **pruntime, lua_State *Lfrom, const char *script, lunatik_opt_t opt,
	lunatik_object_t *percpu, int cpu)
{
	lunatik_object_t *runtime;
	lua_State *L;

	if ((L = luaL_newstate()) == NULL) {
		lunatik_runerror(Lfrom, "failed to allocate Lua state");
		return -ENOMEM;
	}

	if ((runtime = kmalloc(sizeof(lunatik_runtime_t), GFP_KERNEL)) == NULL) {
		lunatik_runerror(Lfrom, "failed to allocate runtime");
		lua_close(L);
		return -ENOMEM;
	}

	lunatik_setobject(runtime, &lunatik_runtime_class, opt);
	lunatik_cstack(runtime) = Lfrom ? lunatik_cstack(lunatik_toruntime(Lfrom)) : current_stack_pointer;
	lunatik_toruntime(L) = runtime;
	lunatik_runtimeof(runtime)->ready = false;
	lunatik_runtimeof(runtime)->cpu = cpu;
	lunatik_runtimeof(runtime)->percpu = percpu;

	runtime->gfp = GFP_KERNEL; /* might use kvmalloc while running in process */
	lua_setallocf(L, lunatik_alloc, runtime);

	runtime->private = L;

	lua_pushcfunction(L, lunatik_runscript);
	lua_pushlightuserdata(L, (void *)script);
	if (lua_pcall(L, 1, 1, 0) != LUA_OK) {
		lunatik_runerror(Lfrom, lunatik_errmsg(L));
		runtime->private = NULL;
		lua_close(L); /* hooks hold extra krefs; putobject alone won't reach 0 */
		lunatik_putobject(runtime);
		return -ENOEXEC;
	}
	lunatik_cstack(runtime) = 0;

	if (lunatik_isirq(opt))
		runtime->gfp = GFP_ATOMIC;

	lunatik_setready(runtime); /* lunatik_run returns -ENXIO until here */

	/* pairs with smp_load_acquire() in lunatik_pin() */
	smp_store_release(pruntime, runtime);
	return 0;
}

int lunatik_runtime(lunatik_object_t **pruntime, const char *script, lunatik_opt_t opt)
{
	return lunatik_newruntime(pruntime, NULL, script, opt, NULL, LUNATIK_CPU_NONE);
}
EXPORT_SYMBOL(lunatik_runtime);

/***
* Creates a new Lunatik runtime executing the given script.
* The runtime closes on `stop()`, when a to-be-closed variable holding it goes out of scope, or
* when its last reference is dropped. A hook its script registers with the kernel holds a
* reference to the runtime, so dropping the handle does not close a runtime a hook still holds:
* it stays open, its hooks in place and the modules its script required loaded, until `stop()`,
* which cannot be called once its last handle is gone. A script stops the runtimes it creates. A
* sentinel stops a child with its creator: a table whose `__gc` stops the child, reachable from what
* the creator's runtime keeps until it closes, as the driver table `device.new` keeps in
* `examples/systrack/device.lua`, since what only a local of the script body references can be
* collected once the body returns. The close runs the script's finalizers, the sentinel's among
* them: an object one creates or reads is released by the end of the close, and a registration
* raises `not allowed while the runtime closes`. A last
* reference dropped with bottom halves or IRQs off, as a softirq or hardirq runtime's `rcu.table`
* write drops an entry's, closes it on a kernel worker after the drop, where its finalizers may
* sleep. Only a process runtime's `lunatik` module has it.
* @function runtime
* @tparam string script script name (e.g., `"mymod"` loads `/lib/modules/lua/mymod.lua`)
* @tparam[opt="process"] string context execution context: `"process"` (sleepable,
*   GFP\_KERNEL, mutex), `"softirq"` (atomic, GFP\_ATOMIC, spinlock), or `"hardirq"`
*   (atomic, GFP\_ATOMIC, spinlock with IRQs disabled).
*   Use `"softirq"` for hooks that fire in softirq context (netfilter, XDP).
*   Use `"hardirq"` for hooks that can fire inside an interrupt handler or with interrupts off
*   (kprobes), since only a lock that turns interrupts off cannot be taken again by an
*   interrupt on the CPU that holds it.
* @treturn runtime
* @raise if allocation fails or the script errors on load
* @within lunatik
*/
static int lunatik_lruntime(lua_State *L)
{
	const char *script = luaL_checkstring(L, 1);
	lunatik_opt_t opt = lunatik_optcontext(L, 2);

	lunatik_object_t **pruntime = lunatik_newpobject(L, 1);
	if (lunatik_newruntime(pruntime, L, script, opt, NULL, LUNATIK_CPU_NONE) != 0)
		lua_error(L);
	lunatik_setclass(L, &lunatik_runtime_class, true);
	if (lunatik_isclosing(lunatik_toruntime(L)))
		lunatik_holdobject(L, *pruntime);
	return 1;
}

static const lunatik_class_t *lunatik_classes[] = { &lunatik_runtime_class, &lunatik_percpu_class, NULL };

LUNATIK_NEWLIB(lunatik, lunatik_lib, lunatik_classes);
LUNATIK_NEWLIB(lunatik_stub, lunatik_stub_lib, NULL);
#endif /* LUNATIK_RUNTIME */

static struct workqueue_struct *lunatik_wq;

void lunatik_deferirq(struct irq_work *irq)
{
	queue_work(lunatik_wq, &container_of(irq, lunatik_defer_t, irq)->work);
}
EXPORT_SYMBOL(lunatik_deferirq);

static int __init lunatik_init(void)
{
	lunatik_resolve(); /* register_kprobe sleeps; lunatik_lookup must not */
	lunatik_wq = alloc_workqueue("lunatik", WQ_UNBOUND, 0);
	return lunatik_wq != NULL ? 0 : -ENOMEM;
}

static void __exit lunatik_exit(void)
{
	destroy_workqueue(lunatik_wq);
}

module_init(lunatik_init);
module_exit(lunatik_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_VERSION(LUNATIK_RELEASE);
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ringzero.com.br>");

