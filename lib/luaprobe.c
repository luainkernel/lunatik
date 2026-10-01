/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Places kprobes on kernel functions and runs Lua handlers when they are hit.
*
* A probe goes on a kernel symbol, or on an address as `syscall.address`,
* `syscall.table` and `linux.lookup` return one. Its `pre` handler runs before the
* probed instruction and its `post` handler after it. What a handler returns is
* ignored, so a probe observes the function and cannot skip it, and the error of a
* handler that raises goes to the kernel log. `dump()` prints the registers of the
* probed CPU to the kernel log.
*
* A probe fires wherever the probed code runs, inside an interrupt handler too, with
* preemption or interrupts off, so the script runs in a hardirq runtime,
* `lunatik run -c hardirq <script>`, whose lock turns interrupts off, and its handlers
* must not sleep.
*
* See `examples/systrack` and `examples/dropreason`.
* @usage
*   -- run with `lunatik run -c hardirq <script>`
*   local probe = require("probe")
*
*   local reported = false
*
*   local function pre(symbol, dump)
*     if not reported then
*       reported = true
*       print(symbol)
*       dump()
*     end
*   end
*
*   probe.new("do_sys_openat2", {pre = pre})
* @module probe
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/kprobes.h>
#include <linux/list.h>
#include <linux/ptrace.h>
#include <linux/string.h>

#include <lunatik.h>

/***
* Represents a registered kprobe.
* @type probe
*/
typedef struct luaprobe_s {
	struct hlist_node node;
	struct kref kref;
	struct kprobe kp;
	kprobe_opcode_t *requested;	/* register_kprobe rewrites kp.addr: on x86 with IBT, past the ENDBR */
	lunatik_object_t *runtime;
} luaprobe_t;

static void (*luaprobe_showregs)(struct pt_regs *);

static int luaprobe_dump(lua_State *L)
{
	struct pt_regs *regs = lua_touserdata(L, lua_upvalueindex(1));
	if (regs == NULL)
		luaL_error(L, LUNATIK_ERR_CLOSED);

	luaprobe_showregs(regs);
	return 0;
}

#ifdef CONFIG_HAVE_FUNCTION_ARG_ACCESS_API
static int luaprobe_argument(lua_State *L)
{
	struct pt_regs *regs = lua_touserdata(L, lua_upvalueindex(1));
	unsigned int n = (unsigned int)lunatik_checkinteger(L, 1, 0, UINT_MAX);

	if (regs == NULL)
		luaL_error(L, LUNATIK_ERR_CLOSED);

	lua_pushinteger(L, (lua_Integer)regs_get_kernel_argument(regs, n));
	return 1;
}
#endif

static const lua_CFunction luaprobe_closures[] = {
	luaprobe_dump,
#ifdef CONFIG_HAVE_FUNCTION_ARG_ACCESS_API
	luaprobe_argument,
#endif
};

static inline void luaprobe_pushregs(lua_State *L, lua_CFunction closure, struct pt_regs *regs)
{
	lua_pushlightuserdata(L, regs);
	lua_pushcclosure(L, closure, 1);
}

static inline void luaprobe_dropregs(lua_State *L, int ix)
{
	lua_pushnil(L);
	lua_setupvalue(L, ix, 1);
}

typedef struct luaprobe_ctx_s {
	luaprobe_t *probe;
	const char *handler;
	struct pt_regs *regs;
} luaprobe_ctx_t;

static int luaprobe_dohandler(lua_State *L)
{
	luaprobe_ctx_t *ctx = lua_touserdata(L, 1);
	luaprobe_t *probe = ctx->probe;
	struct kprobe *kp = &probe->kp;
	const char *symbol = kp->symbol_name;

	if (lunatik_getregistry(L, probe) != LUA_TTABLE)
		luaL_error(L, "couldn't find probe table");
	int base = lua_gettop(L);
	int nclosures = ARRAY_SIZE(luaprobe_closures);
	int i;

	if (lua_getfield(L, base, ctx->handler) != LUA_TFUNCTION) /* base + 1 */
		return 0;

	for (i = 0; i < nclosures; i++)
		luaprobe_pushregs(L, luaprobe_closures[i], ctx->regs); /* base + 2 + i */

	lua_pushvalue(L, base + 1);

	if (symbol != NULL)
		lua_pushstring(L, symbol);
	else
		lua_pushlightuserdata(L, probe->requested);

	for (i = 0; i < nclosures; i++)
		lua_pushvalue(L, base + 2 + i);

	int status = lua_pcall(L, 1 + nclosures, 0, 0); /* handler(symbol | addr, dump[, argument]) */

	for (i = 0; i < nclosures; i++)
		luaprobe_dropregs(L, base + 2 + i); /* regs are only live while the probed function is trapped */
	if (status != LUA_OK)
		lua_error(L);
	return 0;
}

static inline void luaprobe_run(luaprobe_t *probe, const char *handler, struct pt_regs *regs)
{
	luaprobe_ctx_t ctx = {.probe = probe, .handler = handler, .regs = regs};
	int ret;

	lunatik_run(probe->runtime, lunatik_catch, ret, luaprobe_dohandler, &ctx, handler);
	(void)ret;
}

static int __kprobes luaprobe_pre_handler(struct kprobe *kp, struct pt_regs *regs)
{
	luaprobe_run(container_of(kp, luaprobe_t, kp), "pre", regs);
	return 0;
}

static void __kprobes luaprobe_post_handler(struct kprobe *kp, struct pt_regs *regs, unsigned long flags)
{
	/* flags always seems to be zero; see: https://docs.kernel.org/trace/kprobes.html#api-reference */
	luaprobe_run(container_of(kp, luaprobe_t, kp), "post", regs);
}

static void luaprobe_delete(luaprobe_t *probe)
{
	struct kprobe *kp = &probe->kp;
	const char *symbol_name = kp->symbol_name;

	if (kp->pre_handler != NULL) {
		/* disarm picks the ftrace_ops from post_handler; clear handlers only after unregister */
		unregister_kprobe(kp);
		kp->pre_handler = NULL;
		kp->post_handler = NULL;
	}

	if (symbol_name != NULL) {
		kfree(symbol_name);
		kp->symbol_name = NULL;
	}
}

static bool luaprobe_match(const luaprobe_t *probe, const luaprobe_t *spec)
{
	const char *symbol = probe->kp.symbol_name;

	if (spec->kp.symbol_name == NULL)
		return probe->requested == spec->requested;
	return symbol != NULL && strcmp(symbol, spec->kp.symbol_name) == 0;
}

static luaprobe_t *luaprobe_find(struct hlist_head *kprobes, const luaprobe_t *spec)
{
	luaprobe_t *probe;

	hlist_for_each_entry(probe, kprobes, node)
		if (luaprobe_match(probe, spec))
			return probe;
	return NULL;
}

static luaprobe_t *luaprobe_register(lua_State *L, lunatik_object_t *runtime, const luaprobe_t *spec)
{
	luaprobe_t *probe = lunatik_checkalloc(L, sizeof(luaprobe_t));
	struct kprobe *kp = &probe->kp;
	int ret;

	*probe = *spec;
	probe->runtime = runtime;
	kref_init(&probe->kref);

	if (kp->symbol_name != NULL) {
		kp->symbol_name = kstrdup(kp->symbol_name, lunatik_gfp(lunatik_toruntime(L)));
		if (kp->symbol_name == NULL) {
			lunatik_free(probe);
			lunatik_enomem(L);
		}
	}

	if ((ret = register_kprobe(kp)) != 0) {
		kfree(kp->symbol_name);
		lunatik_free(probe);
		lunatik_throw(L, ret);
	}
	return probe;
}

static void luaprobe_free(struct kref *kref)
{
	luaprobe_t *probe = container_of(kref, luaprobe_t, kref);

	luaprobe_delete(probe);
	lunatik_free(probe);
}

#define luaprobe_put(probe)	kref_put(&(probe)->kref, luaprobe_free)

#define luaprobe_isshared(probe)	lunatik_ispercpu((probe)->runtime->opt)

static void luaprobe_disarm(luaprobe_t *probe)
{
	luaprobe_delete(probe); /* the set unregisters before its runtimes close, however many handles remain */
	luaprobe_put(probe);
}

LUNATIK_PERCPUDATA(luaprobe_kprobes, "probe.kprobes", luaprobe_t, luaprobe_disarm);

static void luaprobe_release(void *private)
{
	luaprobe_t *probe = (luaprobe_t *)private;
	lunatik_object_t *runtime = probe->runtime;
	bool owned = !luaprobe_isshared(probe); /* the percpu object outlives the runtimes it closes */

	luaprobe_put(probe);
	if (owned)
		lunatik_putobject(runtime);
}

#define LUAPROBE_ERR_SHARED	"the percpu object owns this probe"

static const lunatik_class_t luaprobe_class;

LUNATIK_PRIVATECHECKER(luaprobe_checkowned, luaprobe_t *, &luaprobe_class,
	luaL_argcheck(L, !luaprobe_isshared(private), ix, LUAPROBE_ERR_SHARED);
);

/***
* Unregisters and stops the probe.
* From a handler this raises: the way to stop delivering there is to return early on a flag
* the script owns, and the kprobe is unregistered when the runtime stops.
* @function stop
* @raise if the percpu object owns this probe, or `not allowed once the runtime is armed`
*   (its script body has returned): unregister_kprobe sleeps, and an
*   armed runtime runs with its lock held and interrupts off
*/
static int luaprobe_stop(lua_State *L)
{
	lunatik_checkarmed(L);
	luaprobe_delete(luaprobe_checkowned(L, 1));
	lunatik_unregisterobject(L, lunatik_toobject(L, 1));
	return 0;
}

static struct kprobe *luaprobe_checkkprobe(lua_State *L)
{
	lunatik_checkarmed(L);
	struct kprobe *kp = &luaprobe_checkowned(L, 1)->kp;

	luaL_argcheck(L, kp->pre_handler != NULL, 1, LUNATIK_ERR_CLOSED);
	return kp;
}

/***
* Enables the probe: a hit runs its handlers, as it does from `new` until a `disable`.
* @function enable
* @raise if the probe has been stopped, if the percpu object owns this probe,
*   `not allowed once the runtime is armed` (its script body has
*   returned): enable_kprobe sleeps, and an armed runtime runs with its
*   lock held and interrupts off; or the error enable_kprobe returns
*/
static int luaprobe_enable(lua_State *L)
{
	lunatik_try(L, enable_kprobe, luaprobe_checkkprobe(L));
	return 0;
}

/***
* Disables the probe: it stays registered, and a hit runs no handler until `enable`.
* @function disable
* @raise if the probe has been stopped, if the percpu object owns this probe,
*   `not allowed once the runtime is armed` (its script body has
*   returned): disable_kprobe sleeps, and an armed runtime runs with its
*   lock held and interrupts off; or the error disable_kprobe returns
*/
static int luaprobe_disable(lua_State *L)
{
	lunatik_try(L, disable_kprobe, luaprobe_checkkprobe(L));
	return 0;
}

static int luaprobe_new(lua_State *L);

/***
* Creates and registers a new kprobe.
* In a percpu script the runtimes share one kprobe per symbol or address: the first
* registration installs it, the others attach their handlers, and a call reaches the
* runtime of the CPU it ran on.
* Probing a target another probe already holds does not fail: both handlers run on a hit,
* so two symbols the kernel resolves to one address each count the other's calls. In a
* percpu script, repeating a target of the set is refused instead.
* @function new
* @tparam string|lightuserdata symbol kernel symbol name or address
* @tparam table handlers table with optional `pre` and `post` callback functions;
*   each receives the symbol (string) or the address as given (lightuserdata), a `dump`
*   closure and, where the architecture selects `CONFIG_HAVE_FUNCTION_ARG_ACCESS_API`, an
*   `argument` closure; both closures raise once the callback returns. `argument(n)` reads
*   the n-th argument of the probed function, counting from zero, through
*   `regs_get_kernel_argument()`, which guesses the register mapping: what it returns is not
*   the argument past the registers the architecture passes arguments in, nor after a
*   parameter 16 bytes or larger. The table is read once, to decide whether the kernel
*   installs a post handler, so a `post` added to it afterwards never fires; a `pre` added
*   afterwards does
* @treturn probe
* @raise `runtime context mismatch` unless the runtime is hardirq; `not allowed while the runtime
*   closes` from a finalizer that runs at its close; the kernel's errno if it refuses the
*   registration, `ENOENT` for a symbol it does not have; in a percpu script, if this runtime
*   already registered the same symbol or address, or if another runtime of the set registered
*   this target with a different post handler; or
*   `not allowed once the runtime is armed` (its script body has returned):
*   register_kprobe sleeps, and an armed runtime runs with its lock held and interrupts off
* @within probe
*/
static const luaL_Reg luaprobe_lib[] = {
	{"new", luaprobe_new},
	{NULL, NULL}
};

static const luaL_Reg luaprobe_mt[] = {
	{"__gc",   lunatik_deleteobject},
	{"stop",   luaprobe_stop},
	{"enable", luaprobe_enable},
	{"disable", luaprobe_disable},
	{NULL, NULL}
};

static const lunatik_class_t luaprobe_class = {
	.name = "probe",
	.methods = luaprobe_mt,
	.release = luaprobe_release,
	.opt = LUNATIK_OPT_HARDIRQ | LUNATIK_OPT_SINGLE | LUNATIK_OPT_EXTERNAL,
	.owner = THIS_MODULE,
};

static void luaprobe_checkspec(lua_State *L, int ix, luaprobe_t *spec)
{
	if (lua_islightuserdata(L, ix))
		spec->requested = spec->kp.addr = lua_touserdata(L, ix);
	else
		spec->kp.symbol_name = luaL_checkstring(L, ix); /* anchored at ix until luaprobe_register copies it */
}

static luaprobe_t *luaprobe_share(lua_State *L, lunatik_object_t *percpu, const luaprobe_t *spec)
{
	struct hlist_head *kprobes = lunatik_percpudata(L, &luaprobe_kprobes_class, sizeof(struct hlist_head))->private;
	luaprobe_t *probe = luaprobe_find(kprobes, spec);

	if (probe == NULL) {
		probe = luaprobe_register(L, percpu, spec);
		hlist_add_head(&probe->node, kprobes);
	}
	else if (lunatik_getregistry(L, probe) != LUA_TNIL)
		luaL_error(L, "probe already registered");
	else if (spec->kp.post_handler != probe->kp.post_handler)
		luaL_error(L, "probe registered with a different post handler");
	else
		lua_pop(L, 1);

	kref_get(&probe->kref);
	return probe;
}

static luaprobe_t *luaprobe_own(lua_State *L, lunatik_object_t *runtime, const luaprobe_t *spec)
{
	luaprobe_t *probe = luaprobe_register(L, runtime, spec);

	lunatik_getobject(runtime); /* a percpu object is held by its data; a plain runtime is held here */
	return probe;
}

static int luaprobe_new(lua_State *L)
{
	lunatik_checkarmed(L);
	luaprobe_t spec = {.kp = {.pre_handler = luaprobe_pre_handler}};
	luaprobe_checkspec(L, 1, &spec);
	luaL_checktype(L, 2, LUA_TTABLE); /* handlers */
	/* the kernel charges for a post handler: no optimization, an ftrace IPMODIFY reservation */
	spec.kp.post_handler = lua_getfield(L, 2, "post") == LUA_TFUNCTION ? luaprobe_post_handler : NULL;
	lua_pop(L, 1);
	lunatik_object_t *runtime = lunatik_checkruntime(L, luaprobe_class.name, LUNATIK_OPT_HARDIRQ);
	lunatik_object_t *percpu = lunatik_getpercpu(L);

	lunatik_object_t *object = lunatik_newobject(L, &luaprobe_class, 0, LUNATIK_OPT_NONE);

	object->private = percpu != NULL ? luaprobe_share(L, percpu, &spec) : luaprobe_own(L, runtime, &spec);

	/* register_kprobe already ran: lunatik_run drops every hit until the runtime is ready */
	lunatik_registerobject(L, 2, object); /* keyed by the kprobe, which is what the handler looks up */
	return 1; /* object */
}

LUNATIK_CLASSES(probe, &luaprobe_class);
LUNATIK_NEWLIB(probe, luaprobe_lib, luaprobe_classes);

static int __init luaprobe_init(void)
{
	if ((luaprobe_showregs = (void (*)(struct pt_regs *))lunatik_lookup("show_regs")) == NULL)
		return -ENXIO;
	return 0;
}

static void __exit luaprobe_exit(void)
{
}

module_init(luaprobe_init);
module_exit(luaprobe_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_VERSION(LUNATIK_RELEASE);
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ringzero.com.br>");

