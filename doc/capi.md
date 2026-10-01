# Lunatik C API

```C
#include <lunatik.h>
```

## Types

### lunatik\_class\_t
```C
typedef void (*lunatik_release_t)(void *);

typedef struct lunatik_class_s {
	const char        *name;
	const luaL_Reg    *methods;
	lunatik_release_t  release;
	lunatik_opt_t      opt;
	struct module     *owner;
} lunatik_class_t;
```
Describes a Lunatik object class.

- `name`: the class's type name, quoted by type errors and `__name`.
- `methods`: `NULL`-terminated array of Lua methods registered in the metatable. It carries
  `{"__gc", lunatik_deleteobject}`, which drops the reference the userdata holds: without it, the
  object and its private are never released. `{"__close", lunatik_closeobject}` and
  `{"close", lunatik_closeobject}` release the private before the collector does, through
  [`lunatik_closeprivate`](#lunatik_closeprivate).
- `release`: called once with the private, at the first of
  [`lunatik_closeprivate`](#lunatik_closeprivate), which an object's `close` or `stop` and
  `lunatik_stop` run, and the drop of the last reference; Lunatik then frees the private, unless
  the class is `LUNATIK_OPT_EXTERNAL`. It runs on the task that closed the object or dropped that
  reference. May be `NULL`.
- `opt`: bitmask of `LUNATIK_OPT_*` flags controlling class behaviour. Flags are inherited by
  every instance via `object->opt = opt | class->opt` (see `lunatik_newobject`). Flags differ
  in whether they act as **constraints** or **capabilities**:
  - `LUNATIK_OPT_SOFTIRQ` *(constraint)*: all instances use `GFP_ATOMIC` and a spinlock:
    `spin_lock_bh`, or `spin_lock_irqsave` when interrupts are already off; absence means mutex and
    `GFP_KERNEL`. Use for classes whose handlers fire in softirq context (netfilter, XDP). Because
    this flag is always inherited, a SOFTIRQ class can never produce a non-SOFTIRQ instance.
  - `LUNATIK_OPT_HARDIRQ` *(constraint)*: like `SOFTIRQ`, but always `spin_lock_irqsave`, whatever
    the interrupt state. Required for classes whose handlers can fire inside an interrupt handler or
    with interrupts off (e.g. kprobes): an interrupt on the CPU that holds a lock taken with
    interrupts on would spin on it forever.
  - `LUNATIK_OPT_MONITOR` *(capability)*: the class supports a monitored metatable that wraps Lua
    method calls with the object lock, enabling safe concurrent access from multiple runtimes.
    Inherited by default but cancelled when an instance is created with `LUNATIK_OPT_SINGLE`. A
    metamethod other than `__tostring`, which reads the object as a method does, a method named
    `close`, and a method bound to `lunatik_lstop`, the runtime's `stop`, are left unwrapped: a
    close takes the lock itself, through `lunatik_closeprivate`, and would wait on the one the
    wrapper holds. The wrapper waits for the lock with
    `lunatik_lockkillable`: the stop of a kernel thread, or a fatal signal to any other task, ends
    the wait and the call raises `EINTR`. While the method runs, the calling runtime allocates with
    the object's `gfp`.
  - `LUNATIK_OPT_SINGLE` *(constraint)*: all instances are private and non-shareable by default.
    Like `SOFTIRQ`, this is always inherited and cannot be overridden per instance.
  - `LUNATIK_OPT_EXTERNAL` *(constraint)*: `object->private` holds an external pointer — Lunatik
    will not free it on release.
  - `LUNATIK_OPT_IRQ`: the bit both `SOFTIRQ` and `HARDIRQ` carry, which `lunatik_isirq(opt)`
    tests; it is not set alone.
  - `LUNATIK_OPT_PERCPU`: marks the `percpu` class, whose private holds one runtime per CPU;
    internal to the core.
  - `LUNATIK_OPT_NONE`: `0`, no flag.
- `owner`: the module the class's methods and `release` live in, `THIS_MODULE`, as a
  `struct file_operations` names its own; a class that leaves it `NULL`, as `THIS_MODULE` is in a
  built-in build, holds nothing. Every object of the class holds a reference to it from
  its creation to its release, so the module stays loaded while an object is left, in an
  `rcu.table` such as `_ENV` or in a runtime that never required its library. A state that
  [`lunatik_cloneobject`](#lunatik_cloneobject) creates the class's metatables in holds another
  until it closes.

### lunatik\_object\_t
```C
typedef struct lunatik_object_s {
	struct kref kref;
	const lunatik_class_t *class;
	void *private;
	union {
		struct mutex mutex;
		spinlock_t spin;
	};
	struct task_struct *owner;
	lunatik_opt_t opt;
	gfp_t gfp;
	unsigned long flags;
	struct rcu_head rcu;
} lunatik_object_t;
```
A Lunatik object. A binding reads `private`, the data of its class, `NULL` once the object is
closed; `object->class`, the class it was created with; `opt`, as
[`lunatik_newobject`](#lunatik_newobject) computes it; and `gfp`, through
[`lunatik_gfp`](#lunatik_gfp). The other fields are the core's: `kref` belongs to
[`lunatik_getobject`](#lunatik_getobject) and [`lunatik_putobject`](#lunatik_putobject), the lock
union, `owner` and `flags` to [`lunatik_lock`](#lunatik_lock), and the `rcu_head` to the release.

### lunatik\_opt\_t
```C
typedef u8 __bitwise lunatik_opt_t;
```
The type of the `LUNATIK_OPT_*` flags, of a class's `opt` and of an object's. It is `__bitwise`, so
sparse (`make C=1`) warns on a plain integer mixed into it: flags combine with `|`, and a cast
into the type carries `__force`, as the `LUNATIK_OPT_*` definitions do.

---

## Runtime

### lunatik\_runtime
```C
int lunatik_runtime(lunatik_object_t **pruntime, const char *script, lunatik_opt_t opt);
```
_lunatik\_runtime()_ creates a new `runtime` environment then loads and runs the script
`/lib/modules/lua/<script>.lua` as the entry point for this environment.
It _must_ only be called from _process context_.
The `runtime` environment is a Lunatik object that holds
a [Lua state](https://www.lua.org/manual/5.5/manual.html#lua_State).
Lunatik objects are special
Lua [userdata](https://www.lua.org/manual/5.5/manual.html#2.1)
which also hold
a [lock type](https://docs.kernel.org/locking/locktypes.html) and
a [reference counter](https://docs.kernel.org/core-api/kref.html).
`opt` selects the context the `runtime` environment runs in.
With `LUNATIK_OPT_NONE`, _lunatik\_runtime()_ will use a
[mutex](https://docs.kernel.org/locking/mutex-design.html)
for locking the `runtime` environment and the
[GFP\_KERNEL](https://www.kernel.org/doc/html/latest/core-api/memory-allocation.html)
flag for allocating new memory later on
[lunatik\_run()](#lunatik_run) calls.
With `LUNATIK_OPT_SOFTIRQ` or `LUNATIK_OPT_HARDIRQ`, it will use a
[spinlock](https://docs.kernel.org/locking/locktypes.html#raw-spinlock-t-and-spinlock-t),
taken with bottom halves off, or with interrupts off for `LUNATIK_OPT_HARDIRQ` and wherever
interrupts are already off, and
[GFP\_ATOMIC](https://www.kernel.org/doc/html/latest/core-api/memory-allocation.html)
once the script has loaded.
_lunatik\_runtime()_ opens the Lua standard libraries
[present on Lunatik](guide/04-lua.md).
A softirq or hardirq runtime opens every one of them but `io`, and its `lunatik` library carries
only `lunatik.cpu`.
If successful, _lunatik\_runtime()_ sets the address pointed by `pruntime` and
[Lua's extra space](https://www.lua.org/manual/5.5/manual.html#lua_getextraspace)
with a pointer for the new created `runtime` environment,
sets the _reference counter_ to `1` and then returns `0`.
The script's first return value stays on the state's stack, at index `1`, below what a handler
pushes.
Otherwise, it returns `-ENOMEM`, if insufficient memory is available;
or `-ENOEXEC`, if it fails to load or run the `script`, and logs the error with `pr_err`.

#### Example: lunatik\_runtime
```Lua
-- /lib/modules/lua/mydevice.lua
function myread(len, off)
	return "42"
end
```

```C
static lunatik_object_t *runtime;

static int __init mydevice_init(void)
{
	return lunatik_runtime(&runtime, "mydevice", LUNATIK_OPT_NONE);
}
```

### lunatik\_stop
```C
int lunatik_stop(lunatik_object_t *runtime);
```
_lunatik\_stop()_
[closes](https://www.lua.org/manual/5.5/manual.html#lua_close)
the
[Lua state](https://www.lua.org/manual/5.5/manual.html#lua_State)
created for this `runtime` environment and decrements the
[reference counter](https://docs.kernel.org/core-api/kref.html).
Once the reference counter is decremented to zero, the
[lock type](https://docs.kernel.org/locking/locktypes.html)
and the memory allocated for the `runtime` environment are released.
If the `runtime` environment has been released, it returns `1`;
otherwise, it returns `0`.
A hook the script registers with the kernel holds a reference of its own,
so it is _lunatik\_stop()_, and not a [lunatik\_putobject()](#lunatik_putobject)
of the caller's reference, that closes a `runtime` a hook still holds.
Call it from process context and never from the runtime's own code: from a handler dispatched on
it, the close waits on the lock that task holds, which [`lunatik_isowner`](#lunatik_isowner)
tells, and from its script body it closes the state that is running. Nor call it under RTNL when
the script may have registered a netdevice notifier, whose release unregisters it and takes RTNL.
A holder in atomic context drops its reference with [lunatik\_putobject()](#lunatik_putobject)
instead.

### lunatik\_copyobjects
```C
int lunatik_copyobjects(lua_State *Lto, lua_State *Lfrom, int ixfrom, int nobjects);
```
Clones onto `Lto`, in order, the `nobjects` Lunatik objects `Lfrom` holds from `ixfrom`, which may
be negative to count from `Lfrom`'s top. It carries objects and nothing else: a value that is not a
Lunatik object fails it with `invalid object`; an object marked `SINGLE` with
`'<class>': cannot share SINGLE object`; a process-context object copied into a softirq or
hardirq runtime with `'<class>': process-context class in interrupt-context runtime`; and more
objects than `Lto`'s stack takes with `too many objects`. On failure it returns the status of the
[protected call](https://www.lua.org/manual/5.5/manual.html#lua_pcall) and leaves the message on
`Lto`, which the caller pops; on success it returns `LUA_OK`.

### lunatik\_run
```C
void lunatik_run(lunatik_object_t *runtime, <inttype> (*handler)(...), <inttype> &ret, ...);
```
_lunatik\_run()_ locks the `runtime` environment and calls the `handler`
passing the associated Lua state as the first argument followed by the variadic arguments.
`ret` is set with `-ENXIO`, and the handler does not run, when the Lua state has been closed, when
the script body is still running, as it is when a hook armed from the body fires, and, for a
`percpu` object, when the runtime of this CPU is not published yet; if the calling task already
holds the runtime's lock, a dispatch from the runtime's own code, with `-EDEADLK`, and the handler
does not run either; otherwise, `ret` is set with the result of `handler(L, ...)` call.
Then, it restores the Lua stack and unlocks the `runtime` environment.
A process runtime is locked with a mutex, so _lunatik\_run()_ on it is called from a context that
may sleep.
A `percpu` object, which the caller keeps referenced across the call, is resolved first, through
`lunatik_pin`, to the runtime of the CPU the caller runs on, and the caller stays on that CPU
until `lunatik_unpin` after the call returns: with preemption off for a softirq or hardirq set,
with migration off for a process one.
It is defined as a macro.

#### Example: lunatik\_run
```C
typedef struct myread_s {
	char __user *buf;
	size_t len;
	loff_t *off;
	ssize_t ret;
} myread_t;

static int l_read(lua_State *L)
{
	myread_t *ctx = lua_touserdata(L, 1);
	size_t llen;
	const char *lbuf;
	loff_t off;

	lua_getglobal(L, "myread");
	lua_pushinteger(L, ctx->len);
	lua_pushinteger(L, *ctx->off);
	lua_call(L, 2, 2); /* calls myread(len, off) */

	lbuf = lua_tolstring(L, -2, &llen);
	llen = min(ctx->len, llen);
	off = (loff_t)luaL_optinteger(L, -1, *ctx->off + llen);
	if (copy_to_user(ctx->buf, lbuf, llen) != 0) {
		ctx->ret = -EFAULT;
		return 0;
	}

	*ctx->off = off;
	ctx->ret = (ssize_t)llen;
	return 0;
}

static ssize_t mydevice_read(struct file *f, char __user *buf, size_t len, loff_t *off)
{
	ssize_t ret;
	lunatik_object_t *runtime = (lunatik_object_t *)f->private_data;
	myread_t ctx = {.buf = buf, .len = len, .off = off};

	lunatik_run(runtime, lunatik_catch, ret, l_read, &ctx, "read");
	return ret == 0 ? ctx.ret : ret;
}
```
Everything that can raise, the callback, pushing its arguments, reading what it returned and any
allocation, runs inside `l_read`, under the protected call [`lunatik_catch`](#lunatik_catch) makes: a
raise with no handler is a `BUG()`.

### lunatik\_handle
```C
void lunatik_handle(lunatik_object_t *runtime, <inttype> (*handler)(...), <inttype> &ret, ...);
```
Runs `handler(L, ...)` on `runtime`'s state and restores the stack. Unlike `lunatik_run`, it
takes no lock, does not resolve a `percpu` object, and does not check that the state is open or
ready: the caller already runs inside the runtime, holding its lock or in its script body, and
passes a plain runtime whose state it knows is open. Defined as a macro.

### lunatik\_cpcall
```C
int lunatik_cpcall(lua_State *L, lua_CFunction f, void *ud);
```
Calls the C function `f` in protected mode with `ud` as its only argument, a light userdata, as
Lua 5.1's `lua_cpcall` did, and returns the status of the
[protected call](https://www.lua.org/manual/5.5/manual.html#lua_pcall), leaving the error on the
stack when it fails; what `f` returns is dropped. A handler of `lunatik_run` whose work can raise passes its
arguments and its result in a context `ud` points to and does that work in `f`, as the example of
`lunatik_run` does through [`lunatik_catch`](#lunatik_catch).

### lunatik\_catch
```C
int lunatik_catch(lua_State *L, lua_CFunction f, void *ud, const char *name);
```
Calls `f` with `ud` through [`lunatik_cpcall`](#lunatik_cpcall) and returns `0`; when `f` raises, it logs
the error read through [`lunatik_errmsg`](#lunatik_errmsg) followed by `name`, rate limited and under the
`pr_fmt` of the file that calls it, and returns `-ECANCELED`. It is the handler a binding gives
`lunatik_run` or `lunatik_handle` for a callback: `f` pushes the callback's arguments, calls it and reads
what it returns, taking its input from `ud` and leaving its result there, and `name` says which callback
failed, as `read` does in the example of `lunatik_run`.

### lunatik\_opterrno
```C
int lunatik_opterrno(lua_State *L, int ix);
```
Returns the errno a callback answered with at `ix`: `0` for nil or none, and the value itself for an
integer from `-MAX_ERRNO` to `0`; any other value raises `invalid errno`, which
[`lunatik_catch`](#lunatik_catch) turns into `-ECANCELED`. A binding whose callback fails an operation
the kernel asked for by returning a negative errno reads that return through it, in the `f` it gives
`lunatik_catch`, and hands the result to the kernel.

### lunatik\_toruntime
```C
lunatik_object_t *lunatik_toruntime(lua_State *L);
```
Returns the `runtime` environment referenced by `L`'s
[extra space](https://www.lua.org/manual/5.5/manual.html#lua_getextraspace).
Defined as a macro.

### lunatik\_getstate
```C
lua_State *lunatik_getstate(lunatik_object_t *runtime);
```
Returns the Lua state of `runtime`, `NULL` once the runtime is closed. Defined as a macro.

### lunatik\_class
```C
extern const lunatik_class_t lunatik_class;
```
The class of a runtime, `lunatik.runtime` in type errors. A binding that takes a runtime as an argument
checks it with `lunatik_checkobjectclass(L, ix, &lunatik_class)`.

### lunatik\_env
```C
extern lunatik_object_t *lunatik_env;
```
The `rcu.table` every runtime shares as `lunatik._ENV`, through which scripts exchange objects.
`lunatik_run.ko`, the module that runs the `/dev/lunatik` driver, creates it when it loads and
clears it when it unloads; it is `NULL` while that module is not loaded, and a runtime created then
has no `lunatik._ENV`.

### lunatik\_isready
```C
bool lunatik_isready(lunatik_object_t *runtime);
```
Returns `true` once `runtime` is armed, its script body returned, and until it is closed.
`thread.run` uses it to refuse creating a thread from the script body of the runtime that calls
it, with `not allowed before the runtime is armed`.

### lunatik\_isclosing
```C
bool lunatik_isclosing(lunatik_object_t *runtime);
```
Returns `true` while `runtime` closes and its state runs the script's finalizers: a stop and a
script that fails to load clear its private before `lua_close`, and the drop of its last reference
closes it at a zero count, which a runtime has at no other time. Lua arms no `__gc` on what those
finalizers create. Defined as a macro.

### lunatik\_isowner
```C
bool lunatik_isowner(lunatik_object_t *object);
```
Returns `true` if the calling task holds `object`'s lock. `lunatik_lock` records the owner
and `lunatik_unlock` clears it, so every holder is seen, whichever route it took into the
lock. The read takes no lock: only the holder writes the field, so the only value that can
make the test true is the reader's own. `lunatik_run` reads it before it locks and answers
`-EDEADLK` to a dispatch on the task that holds the lock, and
[`lunatik_checkowner`](#lunatik_checkowner) refuses an entry point that would take the lock
its own task holds; a binding that dispatches without `lunatik_run` reads it itself.

The answer is exact for a process-context object, whose mutex is task-owned; a SOFTIRQ or
HARDIRQ class takes a spinlock, owned by a CPU and not by a task, and records whichever task
the softirq or hardirq interrupted. It answers about the object it is given: a percpu set's own
lock, which no dispatch takes, so `lunatik_run` reads it on the per-CPU instance `lunatik_pin`
returns and `percpu:stop()` asks each runtime of the set in turn. And it sees the calling task
only — Lua that blocks under the lock on a second task which then reaches the same lock is a
cycle no owner check can name. The entries a script reaches, the monitor, `stop`, `resume` and
`thread.run`, take a runtime's lock with `lunatik_lockkillable`, so the stop of a kernel thread
in that cycle, or a fatal signal to another task in it, ends its wait; a dispatch through
`lunatik_run` is not one of them and waits for the lock regardless.

### lunatik\_isrtnl
```C
bool lunatik_isrtnl(void);
void lunatik_setrtnl(struct task_struct *task);
```
`lunatik_isrtnl` returns `true` if the calling task is dispatching a callback under RTNL. A binding
whose kernel callback runs with RTNL held, as `notifier.netdevice`'s does, sets the task with
`lunatik_setrtnl(current)` before it runs Lua there and clears it with `lunatik_setrtnl(NULL)` after.
RTNL is held by one task at a time, so one pointer serves every runtime and every coroutine, and
the read takes no lock: only the task that wrote the pointer can find itself there. Use it before a
kernel call that takes RTNL, such as `register_netdevice_notifier`, which would wait on the lock its
own task holds: refuse the call with `lunatik_checkrtnl`. A `release` cannot refuse, so the entry
point that runs one on the calling task, a `stop()` or a `close()` and its `__close`, refuses
instead under RTNL. It sees the calling task only: Lua on a second task that waits for
RTNL while this one waits for that task is a cycle it cannot name. Defined as macros.

### lunatik\_iskthread
```C
bool lunatik_iskthread(void);
```
Returns `true` if the calling task is a kernel thread, one `thread.run` or the kernel started, and
not a task that entered from userspace, a `device` file operation's or the CLI's. What ends a wait
differs by the answer: a kernel thread is stopped, which sets the flag an interruptible wait reads
and no fatal signal, so `lunatik_lockkillable` waits interruptibly there and killably elsewhere,
and `thread.shouldstop` asks `kthread_should_stop` only there. Defined as a macro.

### lunatik\_checkruntime
```C
lunatik_object_t *lunatik_checkruntime(lua_State *L, const char *name, lunatik_opt_t opt);
```
Returns the runtime associated with `L` and raises `runtime context mismatch: <name> needs
<context>` if its context does not match `opt`, where `name` names what needs the context, the
class a constructor creates, and `<context>` is `process`, `softirq` or `hardirq`, as `opt` says.
Context is determined by the SOFTIRQ/HARDIRQ bits: a SOFTIRQ class must run in a `softirq` runtime,
a HARDIRQ class in a `hardirq` runtime, and a process-context class in a process runtime. A
binding's constructor calls it, directly or through `lunatik_setruntime`, to enforce that a class
is only instantiated in a compatible runtime. It runs [`lunatik_checkclosing`](#lunatik_checkclosing)
too, so a finalizer that runs as the runtime closes registers nothing the runtime would dispatch.

### lunatik\_setruntime
```C
lunatik_object_t *lunatik_setruntime(lua_State *L, libname, priv);
```
Stores `lunatik_checkruntime(L, lua<libname>_class.name, lua<libname>_class.opt)` in
`priv->runtime` and returns it: the class is read by its name, `lua<libname>_class`, so
`lunatik_setruntime(L, device, luadev)` checks against `luadevice_class`. Defined as a macro.

### lunatik\_checkcontext
```C
lunatik_opt_t lunatik_checkcontext(lua_State *L, int ix);
```
Reads the context name at `ix`, `"process"`, the default, `"softirq"` or `"hardirq"`, and returns
`LUNATIK_OPT_NONE`, `LUNATIK_OPT_SOFTIRQ` or `LUNATIK_OPT_HARDIRQ`. Raises
`invalid option '<name>'` for any other string, as `luaL_checkoption` does.

### lunatik\_checkclass
```C
void lunatik_checkclass(lua_State *L, const lunatik_class_t *class);
```
Raises `'<name>': process-context class in interrupt-context runtime` when `L`'s runtime is a
softirq or hardirq one and `class->opt` carries neither `LUNATIK_OPT_SOFTIRQ` nor
`LUNATIK_OPT_HARDIRQ`: an object whose lock is a mutex cannot live there.

### lunatik\_cannotsleep
```C
bool lunatik_cannotsleep(lua_State *L, bool s);
```
Returns `true` when `s` holds and `L`'s runtime is a softirq or hardirq one. An entry point that
would sleep when `s` holds tests it and refuses rather than deadlocking the machine:
[`lunatik_checkarmed`](#lunatik_checkarmed) passes `lunatik_isready` as `s`. Defined as a macro.

### lunatik\_checkarmed
```C
void lunatik_checkarmed(lua_State *L);
```
Raises a Lua error, `"not allowed once the runtime is armed"`, when `L` belongs to an
interrupt-context runtime whose script body returned. An IRQ runtime is process context only while
its script body runs, so a call that may sleep is allowed there and must be refused afterwards,
when the runtime lock is a spinlock: from a hook or a handler, and from the `resume` of such a
runtime. Use it in an entry point that reaches a sleeping kernel call, where `lunatik_checkruntime`
answers the different question of whether the class matches the runtime at all.

### lunatik\_checkclosing
```C
void lunatik_checkclosing(lua_State *L);
```
Raises a Lua error, `"not allowed while the runtime closes"`, when
[`lunatik_isclosing`](#lunatik_isclosing) holds for `L`'s runtime: from a finalizer its close
runs, in whatever coroutine. A registration made there would hold a runtime that never dispatches
again: use it in an entry point that registers one without
[`lunatik_checkruntime`](#lunatik_checkruntime), which runs it.

### lunatik\_checkrtnl
```C
void lunatik_checkrtnl(lua_State *L);
```
Raises a Lua error, `"not allowed under RTNL"`, when [`lunatik_isrtnl`](#lunatik_isrtnl) holds: from
a callback dispatched under RTNL, in whatever runtime or coroutine the calling task runs. Use it in
an entry point that reaches a kernel call taking RTNL.

### lunatik\_checkowner
```C
void lunatik_checkowner(lua_State *L, lunatik_object_t *runtime);
```
Raises a Lua error, `"not allowed from the runtime itself"`, when [`lunatik_isowner`](#lunatik_isowner)
holds for `runtime`: the calling task is inside it, a callback, a file operation, a thread body or a
resumed body, and an entry point that takes its lock would wait on itself. `runtime:stop()` and
`percpu:stop()` use it, since the close locks the runtime it closes; so do a monitored method,
which locks the object it runs on and is `runtime:resume()`'s route into the lock, `percpu:resume()`,
which locks each runtime it resumes, and `thread.run`, which passes the body's arguments under the
runtime's lock.

### lunatik\_percpudata
```C
lunatik_object_t *lunatik_percpudata(lua_State *L, const lunatik_class_t *class, size_t size);
```
Returns the object of `class` a `percpu` object holds for its runtimes: the first runtime to ask
creates it, as `lunatik_createobject(class, size, LUNATIK_OPT_NONE)` does, with its private zeroed;
the following ones get the same object, so every runtime sees one. The `percpu` object owns it:
`percpu:stop()` closes it (`lunatik_closeprivate`, which runs the class's `release` in process
context) before closing the runtimes, then drops it, and an object with such data outstanding is
released by `stop`, never by collection. A registration a script makes once for all its runtimes,
a netfilter hook, say, lives in the private of such an object, with the class's `release`
unregistering it. Only the script body may ask, while the runtime loads; it raises a Lua error
afterwards. Returns `NULL` on a plain runtime, which has no runtimes to share with;
[`lunatik_getpercpu`](#lunatik_getpercpu) tells the two apart.

### LUNATIK\_PERCPUDATA (macro)
```C
#define LUNATIK_PERCPUDATA(prefix, cname, T, free)
```
Defines `static const lunatik_class_t prefix_class`, named `cname`, for the data a `percpu` object
holds for the registrations its runtimes share, as [`lunatik_percpudata`](#lunatik_percpudata)
creates it: a private that is a `struct hlist_head` of `T` entries linked through their
`struct hlist_node node`, whose `release`, `prefix_release`, unlinks every entry and passes it to
`free`. For example,
`LUNATIK_PERCPUDATA(luaprobe_kprobes, "probe.kprobes", luaprobe_t, luaprobe_disarm)`
defines `luaprobe_kprobes_class`.

### lunatik\_getpercpu
```C
lunatik_object_t *lunatik_getpercpu(lua_State *L);
```
Returns the `percpu` object owning the runtime of `L`, or `NULL` on a plain runtime. Defined as a
macro.

### lunatik\_getcpu
```C
#define LUNATIK_CPU_NONE	(-1)
int lunatik_getcpu(lua_State *L);
bool lunatik_hascpu(lua_State *L);
```
`lunatik_getcpu` returns the CPU id the runtime of `L` serves in its `percpu` set, and
`LUNATIK_CPU_NONE` on a plain runtime; `lunatik_hascpu` tells the two apart. Defined as macros.

### lunatik\_checkpercpu
```C
void lunatik_checkpercpu(lua_State *L);
```
Raises `not allowed in a percpu runtime` when `L`'s runtime belongs to a `percpu` set. A
constructor whose registration cannot be shared by the set calls it.

---

## Object Lifecycle

### lunatik\_newobject
```C
lunatik_object_t *lunatik_newobject(lua_State *L, const lunatik_class_t *class, size_t size, lunatik_opt_t opt);
```
_lunatik\_newobject()_ allocates a new Lunatik object and pushes a userdata
containing a pointer to the object onto the Lua stack.

`object->opt` is computed as `opt | class->opt`: all class flags are inherited by the instance.
`opt` may add flags on top (e.g. `LUNATIK_OPT_SOFTIRQ` or `LUNATIK_OPT_HARDIRQ` for a non-sleepable runtime instance).

- `LUNATIK_OPT_MONITOR` wraps method calls with the object lock only for a class whose `opt`
  carries it, where it is already inherited: the monitored metatable is registered only for such
  a class, so for any other class `lunatik_newobject` and `lunatik_cloneobject` raise
  `'<name>': metatable not found`.
- Pass `LUNATIK_OPT_SINGLE` for a private, non-shareable instance. The object cannot be cloned or
  passed to another runtime via `_ENV` or `resume`. `SINGLE` cancels `MONITOR` inheritance: a
  `SINGLE` instance of a `MONITOR` class does **not** get monitor wrappers, since non-shared
  objects do not need them.
- Pass `LUNATIK_OPT_NONE` (`0`) to inherit only the class flags.

It allocates `size` bytes for the object's private data, unless `LUNATIK_OPT_EXTERNAL` is set in
`class->opt`, in which case `object->private` is expected to be set by the caller. The private is
zeroed and comes from the runtime's allocator, `GFP_ATOMIC` in a softirq or hardirq runtime once
it is armed; it is freed with `kvfree` after `release`.

The userdata's `__gc` drops the reference the object is created with. In a state that is closing,
where Lua arms no `__gc` (see [`lunatik_isclosing`](#lunatik_isclosing)), the state holds that
reference instead and drops it once `lua_close` has run every finalizer.

Raises `'<name>': process-context class in interrupt-context runtime`; `'<name>': metatable not
found` when the class's metatables are not in this state's registry, which
[`lunatik_require`](#lunatik_require) creates beforehand; and `not enough memory`.

### lunatik\_createobject
```C
lunatik_object_t *lunatik_createobject(const lunatik_class_t *class, size_t size, lunatik_opt_t opt);
```
_lunatik\_createobject()_ creates a Lunatik object independently of any Lua
state. This is intended for objects created in C that will be shared
with Lua runtimes later via `lunatik_cloneobject`.

Like `lunatik_newobject`, `object->opt` is computed as `opt | class->opt`.
It allocates with `GFP_ATOMIC` when `opt | class->opt` carries `LUNATIK_OPT_SOFTIRQ` or
`LUNATIK_OPT_HARDIRQ`, and with `GFP_KERNEL` otherwise, so a process-context object is created
only where the caller may sleep. The private is `size` zeroed bytes; the call is not for a
`LUNATIK_OPT_EXTERNAL` class, whose private it would allocate and never free.
Returns a pointer to the `lunatik_object_t` on success, or `NULL` if memory allocation fails.

### lunatik\_require
```C
void lunatik_require(lua_State *L, const lunatik_class_t *class);
```
Creates the class's metatables in the registry of `L` from its `methods`, the monitored one too
for a `LUNATIK_OPT_MONITOR` class, unless `L` has them already. It opens no library and adds no
`package.loaded` entry. A function that creates an object of its class in a state whose script
may not have required the library calls it before [`lunatik_newobject`](#lunatik_newobject), as
`luadata_new` does. Raises `not enough memory`.

### lunatik\_cloneobject
```C
void lunatik_cloneobject(lua_State *L, lunatik_object_t *object);
```
_lunatik\_cloneobject()_ pushes `object` onto the Lua stack as a userdata with the correct
metatable, and takes no reference: the userdata's `__gc` drops one, which the caller hands over
or takes, as [`lunatik_pushobject`](#lunatik_pushobject) does; in a closing state the state drops
it instead, as [`lunatik_newobject`](#lunatik_newobject) describes. It calls
[`lunatik_require`](#lunatik_require) first, so the object reaches a state whose script never
required its library; where that creates the metatables, `L` holds the class's `owner` until it
closes, as `require` holds the module of a library it opens.
Raises `'<name>': cannot share SINGLE object` for a `LUNATIK_OPT_SINGLE` object,
`'<name>': process-context class in interrupt-context runtime`, `'<name>': metatable not found`
for a `LUNATIK_OPT_MONITOR` object of a class that does not carry the flag, and `not enough
memory`; so it runs under a protected call.

### lunatik\_pushobject
```C
void lunatik_pushobject(lua_State *L, lunatik_object_t *object);
```
Clones `object` onto `L`, as [`lunatik_cloneobject`](#lunatik_cloneobject) does, and then takes
the reference the new userdata's `__gc` drops, so the caller keeps its own. It raises what
`lunatik_cloneobject` raises, before the reference is taken.

Use together with `lunatik_createobject` for C-owned objects that must be passed to Lua:
```C
static int l_share(lua_State *L)
{
	lunatik_object_t *obj = (lunatik_object_t *)lua_touserdata(L, 1);

	lunatik_pushobject(L, obj);
	lua_setglobal(L, "foo");
	return 0;
}

static int p_share(lua_State *L, lunatik_object_t *obj)
{
	return lunatik_cpcall(L, l_share, obj);
}

obj = lunatik_createobject(&luafoo_class, sizeof(foo_t), LUNATIK_OPT_NONE);
lunatik_run(runtime, p_share, ret, obj);
```
The push runs in `l_share`, under the protected call, and stores the object before `l_share`
returns, since `lunatik_cpcall` drops what it returns.

### lunatik\_getobject
```C
void lunatik_getobject(lunatik_object_t *object);
```
Increments the [reference counter](https://docs.kernel.org/core-api/kref.html) of `object`.

### lunatik\_getobject\_rcu
```C
bool lunatik_getobject_rcu(lunatik_object_t *object);
```
Takes a reference on an object found under `rcu_read_lock()` without one held, as an
`rcu.table` entry hands its readers, and returns `true`; returns `false`, taking none, when the
count is zero: the object is being released, and the reader treats it as absent. The object's
memory outlives the grace period after its release, which is what lets the count be read there.
`lunatik_getobject` is for a holder of a reference.

### lunatik\_putobject
```C
int lunatik_putobject(lunatik_object_t *object);
```
Decrements the [reference counter](https://docs.kernel.org/core-api/kref.html) of `object`.
If the object has been released, returns `1`; otherwise returns `0`. The release runs at once, on
the calling task; the object's memory is freed after an RCU grace period.

### lunatik\_closeobject
```C
int lunatik_closeobject(lua_State *L);
int lunatik_deleteobject(lua_State *L);
```
Methods for a class's `methods` table. `lunatik_closeobject`, for `close` and `__close`, closes
the object at index `1` through [`lunatik_closeprivate`](#lunatik_closeprivate); its userdata
stays, holding its reference. `lunatik_deleteobject`, for `__gc`, drops the reference the
userdata holds and releases the object when it was the last. Both raise `invalid object` when
index `1` holds no Lunatik object, and `lunatik_closeobject` raises `object of another class` when
the object's own `__close` is not `lunatik_closeobject`.

---

## Object Access

### lunatik\_checkobject
```C
lunatik_object_t *lunatik_checkobject(lua_State *L, int i);
```
Returns the Lunatik object at stack position `i`. Raises a Lua error if the value is not a
Lunatik object. Defined as a macro.

### lunatik\_toobject
```C
lunatik_object_t *lunatik_toobject(lua_State *L, int i);
```
Returns the pointer stored in the userdata at stack position `i`, without any check. The value
must be a Lunatik object's userdata: a value that is no userdata dereferences `NULL`, and any
other userdata returns whatever its first word holds. Use `lunatik_checkobject`, or
[`lunatik_getregistryobject`](#lunatik_getregistryobject) for a value read from the registry.
Defined as a macro.

### lunatik\_checkshareable
```C
lunatik_object_t *lunatik_checkshareable(lua_State *L, int ix);
```
Returns the Lunatik object at `ix`, as `lunatik_checkobject` does, and raises
`cannot share SINGLE object` when it is `LUNATIK_OPT_SINGLE`: for a value about to be handed to
another runtime.

### LUNATIK\_PRIVATECHECKER
```C
#define LUNATIK_PRIVATECHECKER(checker, T, cls, ...)
#define LUNATIK_PRIVATECHECKERS(checker, T, tname, ...)
```
Generates a `static inline` function `T checker(lua_State *L, int ix)` that returns
`object->private` cast to `T`, after proving three things about the value at `ix`, each with a
Lua error: it is a Lunatik object (`lunatik_checkobject`), it is of the class `cls`, whose
`name` the type error quotes, and its private is set, which rules out a closed object. The
second form is for a family of classes sharing one checker: `...` lists the classes it accepts,
and `tname` is the name the type error quotes. The first form's optional `...` are further
validation statements, run with `L`, `ix`, `object` and `private` in scope, before `return
private`.

### lunatik\_argcheckclass
```C
void lunatik_argcheckclass(lua_State *L, int ix, lunatik_object_t *object, const lunatik_class_t *cls);
```
Raises a type error naming `cls->name` unless `object`, the Lunatik object at `ix`, is of that
class. Defined as a macro.

### lunatik\_checkobjectclass
```C
lunatik_object_t *lunatik_checkobjectclass(lua_State *L, int ix, const lunatik_class_t *cls);
```
Returns the Lunatik object at `ix` after proving it is one and is of the class `cls`, raising a
Lua error otherwise: the checkers above, for a method that needs the object itself, not only its
private.

---

## Locking

### lunatik\_lock
```C
void lunatik_lock(lunatik_object_t *object);
void lunatik_unlock(lunatik_object_t *object);
```
Take and release `object`'s lock: a mutex for a process-context object; for a SOFTIRQ or HARDIRQ
one, a spinlock, taken with `spin_lock_irqsave` for HARDIRQ or where interrupts are already off,
and with `spin_lock_bh` otherwise. `lunatik_lock` records the calling task as the owner and
`lunatik_unlock` clears it, which is what [`lunatik_isowner`](#lunatik_isowner) reads. A raise
between the two skips the unlock, so what runs under the lock and can raise runs in a protected
call, as the example of `lunatik_run` does through `lunatik_cpcall`. A process-context object is
locked only where the caller may sleep.

### lunatik\_lockkillable
```C
int lunatik_lockkillable(lunatik_object_t *object);
```
Like `lunatik_lock`, but the wait for a process-context object's mutex ends early, returning
`-EINTR` without the lock: on a kernel thread, on its stop, since the wait is interruptible there;
on any other task, on a fatal signal. A SOFTIRQ or HARDIRQ object is locked as `lunatik_lock`
does, and it returns `0`. The entries a script reaches take a runtime's lock through it, and
`lunatik_try` raises the `EINTR`.

### lunatik\_closeprivate
```C
void lunatik_closeprivate(lunatik_object_t *object);
```
Takes `object`'s lock, detaches its private (`object->private = NULL`) and unlocks; then, outside
the lock, runs the class's `release` on the private and frees it, unless the class is
`LUNATIK_OPT_EXTERNAL`. It is how a `close` or a `stop` ends an object before its last reference
goes: the userdata stays, and a checker from
[`LUNATIK_PRIVATECHECKER`](#lunatik_privatechecker) refuses it. A second call finds no private
and does nothing. It takes the lock, so it is not called under it: a method the monitor wraps
holds it, which is why a `close` is left unwrapped.

---

## Registry and Attach/Detach

The registry pattern keeps pre-allocated objects alive across `lunatik_run` calls without
exposing them to the GC:

```C
/* registration, once, at hook setup */
lunatik_attach(L, obj, field, luafoo_new, opt);

/* use, on each callback */
lunatik_object_t *o = lunatik_getregistryobject(L, obj->field);
if (o != NULL)
	luafoo_reset(o, ...);
lua_pop(L, 1);

/* teardown, on unregister */
lunatik_detach(runtime, obj, field);
```

### lunatik\_register
```C
void lunatik_register(lua_State *L, int ix, const void *key);
```
Stores the value at stack index `ix` in `LUA_REGISTRYINDEX` at `key` and leaves the stack as it
found it. `key` is an address the caller owns for the life of the entry: an object's `private`, or
a `static const char` the binding declares for a slot of its own.

### lunatik\_unregister
```C
void lunatik_unregister(lua_State *L, const void *key);
```
Removes the value stored in `LUA_REGISTRYINDEX` at `key`.

### lunatik\_registerobject
```C
void lunatik_registerobject(lua_State *L, int ix, lunatik_object_t *object);
```
Stores the value at `ix`, typically the options table holding the callback, under the key
`object->private`, where a handler reads it with `lunatik_getregistry(L, private)`, and the
userdata on top of the stack, which must be `object`'s, under the key `object`, keeping it from
collection until `lunatik_unregisterobject`. Call it with the object's userdata on top, as right
after `lunatik_newobject`.

### lunatik\_unregisterobject
```C
void lunatik_unregisterobject(lua_State *L, lunatik_object_t *object);
```
Clears the registry entries keyed by `object->private` and by `object`, so the userdata may be
collected.

### lunatik\_getregistry
```C
int lunatik_getregistry(lua_State *L, const void *key);
```
Pushes the value stored in `LUA_REGISTRYINDEX` at `key` onto the Lua stack and returns
its type. Defined as a macro wrapping `lua_rawgetp`.

### lunatik\_getregistryobject
```C
lunatik_object_t *lunatik_getregistryobject(lua_State *L, const void *key);
```
Pushes the value stored in `LUA_REGISTRYINDEX` at `key` and returns it as a Lunatik object, or
`NULL` when there is none or it is no Lunatik object: a hook that reaches for the object it
registered (an `skb`, a handle) reads it through this rather than through `lunatik_toobject`,
which does not check.

### lunatik\_setflag
```C
void lunatik_setflag(lua_State *L, const void *key, bool on);
```
Stores `on` in `LUA_REGISTRYINDEX` at `key`, where a binding keeps a fact its own dispatcher sets
and its own code reads, such as a callback of this state being on the stack. The key is the
binding's own `static const char`, so one binding's callback does not answer for another's, and the
registry is one per state, so every coroutine of it reads the same slot. A dispatcher that sets the
flag outside a protected call seeds the key in its constructor, with `lunatik_seedflag`.

### lunatik\_getflag
```C
bool lunatik_getflag(lua_State *L, const void *key);
```
Returns the flag stored at `key`, `false` where nothing is stored, and leaves the stack as it found
it.

### lunatik\_seedflag
```C
void lunatik_seedflag(lua_State *L, const void *key);
```
Writes the flag back to itself, so the registry node exists without what it says changing and the
writes made at that key afterwards cannot insert. It is the write that can insert, rehash, fail to
allocate and abort the state, so a constructor calls it, where a protected call is on the stack. It
preserves the value because a constructor reached from inside the callback must leave the flag set.

### lunatik\_attach
```C
void lunatik_attach(lua_State *L, obj, field, new_fn, ...);
```
Creates a new object by calling `new_fn(L, ...)`, stores it in `LUA_REGISTRYINDEX` keyed by
the returned pointer, sets `obj->field` to the result, and pops the userdata from the stack.
Defined as a macro.

### lunatik\_detach
```C
void lunatik_detach(lunatik_object_t *runtime, obj, field);
```
Unregisters `obj->field` from the registry and sets `obj->field = NULL`. Safe to call when
the Lua state may already be closed (e.g., from `release` after `lunatik_stop`). Defined as a macro.

---

## Error Handling

### lunatik\_throw
```C
void lunatik_throw(lua_State *L, int ret);
```
Pushes the name of the errno `ret` through [`lunatik_pusherrname`](#lunatik_pusherrname) and
raises it with `lua_error`: `lunatik_throw(L, -ENOMEM)` raises `"ENOMEM"`. Used to convert
negative kernel error codes into Lua errors.

### lunatik\_pusherrname
```C
void lunatik_pusherrname(lua_State *L, int err);
```
Pushes the name of the errno `err`, of either sign, as a string, `"EINVAL"` for `-EINVAL`, say,
and `"unknown"` for a value with no name. The tree passes it negative, as the kernel returns it.

### lunatik\_try
```C
void lunatik_try(lua_State *L, op, ...);
```
Calls `op(...)`. If the return value is negative, calls `lunatik_throw`. Defined as a macro.

### lunatik\_tryret
```C
void lunatik_tryret(lua_State *L, ret, op, ...);
```
Like `lunatik_try`, but stores the return value in `ret` before checking. Defined as a macro.

### lunatik\_errmsg
```C
const char *lunatik_errmsg(lua_State *L);
```
Returns the error on top of the stack of `L` when it is a string, and `"error object is not a string"`
for any other value, never `NULL`. It does not convert a number: `lua_tostring` converts one in
place, which allocates, and an allocation that fails outside a protected call raises with no
handler, a `BUG()`. After a protected call or a resume fails, the error is read through it.

---

## Table Fields

These read fields from a Lua table at stack index `idx`.

### lunatik\_checkfield
```C
void lunatik_checkfield(lua_State *L, int idx, const char *field, int type);
```
Pushes the field named `field` of the table at `idx` and raises
`bad field '<field>' (<type> expected, got <type>)` when its Lua type differs from the one given.
The field stays on the stack for the caller to read and pop.

### lunatik\_optfield
```C
bool lunatik_optfield(lua_State *L, int idx, const char *field, int type);
```
Pushes the field named `field` of the table at `idx` and returns `true` when it holds the Lua type
given and `false` when it is nil or absent; any other type raises
`bad field '<field>' (<type> expected, got <type>)`. The field stays on the stack for the caller to
read and pop.

### lunatik\_optcfunction
```C
void lunatik_optcfunction(lua_State *L, int idx, const char *field, lua_CFunction default_func);
int lunatik_nop(lua_State *L);
```
Pushes the field named `field` of the table at `idx` when it is a function, and `default_func`
otherwise. `lunatik_nop` returns nothing, the default a binding passes for an optional callback.

### lunatik\_setinteger
```C
void lunatik_setinteger(lua_State *L, int idx, hook, field);
```
Reads a required integer field named `field` from the table at `idx` into `hook->field`.
Raises a Lua error if the field is missing or not a number.

### lunatik\_optinteger
```C
void lunatik_optinteger(lua_State *L, int idx, priv, field, opt);
```
Reads an optional integer field named `field` from the table at `idx` into `priv->field`,
through [`lunatik_optfield`](#lunatik_optfield). Falls back to `opt` when the field is nil or
absent, and raises `bad field '<field>' (number expected, got <type>)` when it holds anything
other than a number, a numeric string included. The value is not bounded: a field narrower than
`lua_Integer` keeps its low bits.

### lunatik\_setstring
```C
void lunatik_setstring(lua_State *L, int idx, hook, field, maxlen);
```
Reads a required string field named `field` from the table at `idx` into `hook->field`,
a buffer of `maxlen` bytes holding the string and its terminator. Raises a Lua error if
the field is missing, is not a string, or is too long.

---

## Values

### lunatik\_checkbounds
```C
void lunatik_checkbounds(lua_State *L, int idx, val, min, max);
lua_Integer lunatik_checkinteger(lua_State *L, int idx, lua_Integer min, lua_Integer max);
```
`lunatik_checkbounds` raises `out of bounds`, as an error of the argument at `idx`, unless
`min <= val <= max`; it is a macro, so `val` is any integer the caller computed from the argument.
`lunatik_checkinteger` reads the integer argument at `idx` with `luaL_checkinteger`, bounds it the
same way and returns it. A size, a length or a count that arrives from Lua is bounded with them
for what the binding can serve, and an integer that names a kernel identity, a pid, before the
cast to the kernel's type.

### lunatik\_pushstring
```C
const char *lunatik_pushstring(lua_State *L, char *s, size_t len);
```
Pushes the `len` bytes at `s` as a Lua string without copying them: `s` is a buffer of `len + 1`
bytes from [`lunatik_malloc`](#lunatik_malloc), whose last byte it sets to `'\0'`, and Lua owns
it from the call on, freeing it with the state's allocator, also when the push raises
`not enough memory`. Returns the string's contents.

### lunatik\_pushoptinteger
```C
void lunatik_pushoptinteger(lua_State *L, cond, val);
```
Pushes the integer `val` when `cond` holds, and `nil` otherwise; `val` is evaluated only when
`cond` holds, so it may read through what `cond` tests. Defined as a macro.

### lunatik\_value\_t
```C
typedef struct lunatik_value_s {
	int type;
	union {
		int boolean;
		lua_Integer integer;
		lunatik_object_t *object;
	};
} lunatik_value_t;

void lunatik_checkvalue(lua_State *L, int ix, lunatik_value_t *value);
void lunatik_pushvalue(lua_State *L, lunatik_value_t *value);
```
A Lua value that can cross runtimes: `nil`, a boolean, an integer, or a Lunatik object, as an
`rcu.table` stores it. `lunatik_checkvalue` reads the value at `ix` into `value`, taking no
reference on an object, and raises `unsupported type` for any other type and
`cannot share SINGLE object` for a `LUNATIK_OPT_SINGLE` object. `lunatik_pushvalue` pushes
`value`, handing the reference the caller holds on its object to the new userdata; when the push
raises, it drops that reference first.

---

## Module Definition

### LUNATIK\_OPENER
```C
#define LUNATIK_OPENER(libname)
```
Declares `int luaopen_<libname>(lua_State *L)`, the opener
[`LUNATIK_NEWLIB`](#lunatik_newlib) defines, for code that names it ahead of its definition; with
a body, it defines an opener written by hand, whose declaration is `LUNATIK_OPENER(foo);` ahead
of it.

### LUNATIK\_CLASSES
```C
#define LUNATIK_CLASSES(name, ...)
```
Declares a `static const lunatik_class_t *` array of class pointers with an
implicit trailing `NULL` sentinel. The array is named `lua<name>_classes` —
the same token used in `LUNATIK_NEWLIB(<name>, ..., lua<name>_classes, ...)`,
so both macros compose without the author naming the array explicitly.

- `name`: module name suffix; must match the `libname` of the companion
  `LUNATIK_NEWLIB` call.
- `...`: one or more `const lunatik_class_t *` pointers. The macro appends
  the terminator, so authors must **not** include a trailing `NULL`.

A module may list classes with different execution contexts (e.g. a HARDIRQ
class alongside a process-context class) in the same array; see the note
under [`LUNATIK_NEWLIB`](#lunatik_newlib) for how context enforcement is
handled at object creation.

#### When to use

Prefer `LUNATIK_CLASSES` for the common case of a fixed class list: it
removes boilerplate, enforces the `static const` qualifiers, and makes
forgetting the `NULL` sentinel impossible.

Write the array out by hand when any item is guarded by a preprocessor
directive — `#if`/`#endif` inside a macro argument list is undefined
behavior in C99 (§6.10.3/11), so the helper cannot express conditional
inclusion:

```C
static const lunatik_class_t *luafoo_classes[] = {
	&luafoo_class,
#if (LINUX_VERSION_CODE < KERNEL_VERSION(6, 15, 0))
	&luafoo_legacy_class,
#endif
	NULL
};
LUNATIK_NEWLIB(foo, luafoo_lib, luafoo_classes);
```

The naming convention (`lua<libname>_classes`) is a convention of the helper,
not a requirement of `LUNATIK_NEWLIB`: any NULL-terminated array works.

### LUNATIK\_NEWLIB
```C
#define LUNATIK_NEWLIB(libname, funcs, classes)
```
Defines and exports the `luaopen_<libname>` entry point using `EXPORT_SYMBOL_GPL`.

- `funcs`: `luaL_Reg[]` of Lua-callable functions (the module table).
- `classes`: NULL-terminated `const lunatik_class_t **` array declared with
  `LUNATIK_CLASSES`, or `NULL` if the module defines no object type.

When `classes != NULL`, `LUNATIK_NEWLIB` registers the metatable(s) for every
class in the array through [`lunatik_require`](#lunatik_require).

Metatable registration is context-agnostic: a module may expose classes of
different execution contexts (e.g. a HARDIRQ class alongside a process-context
class) and `luaopen_<libname>` succeeds in any runtime. Context enforcement
happens later, at object creation time — `lunatik_newobject` rejects a
process-context class in an IRQ runtime, and each constructor should call
[`lunatik_checkruntime`](#lunatik_checkruntime) to reject exact mismatches
(e.g. a SOFTIRQ class in a HARDIRQ runtime). This lets a single module serve
runtimes of different contexts: each runtime sees every class registered, but
can only instantiate the ones whose context matches its own.

#### Example — single class
```C
static const luaL_Reg luafoo_lib[] = {
	{"new", luafoo_new},
	{NULL, NULL},
};

LUNATIK_CLASSES(foo, &luafoo_class);
LUNATIK_NEWLIB(foo, luafoo_lib, luafoo_classes);
```

#### Example — multiple classes, different contexts
```C
static const lunatik_class_t luafoo_process_class = {
	.name = "foo", .methods = luafoo_mt, .release = luafoo_release,
	.opt = LUNATIK_OPT_SINGLE, .owner = THIS_MODULE,
};

static const lunatik_class_t luafoo_hardirq_class = {
	.name = "foo", .methods = luafoo_mt, .release = luafoo_release,
	.opt = LUNATIK_OPT_HARDIRQ | LUNATIK_OPT_SINGLE, .owner = THIS_MODULE,
};

LUNATIK_CLASSES(foo, &luafoo_process_class, &luafoo_hardirq_class);
LUNATIK_NEWLIB(foo, luafoo_lib, luafoo_classes);
```

`require("foo")` succeeds in any runtime — both metatables are registered.
Each class can only be instantiated from a runtime whose context matches
its `opt`; the constructor enforces this via
[`lunatik_checkruntime`](#lunatik_checkruntime).

### LUNATIK\_RELEASE
```C
#define LUNATIK_RELEASE	"<major>.<minor>"
#define LUNATIK_VERSION	"Lunatik " LUNATIK_RELEASE
```
`LUNATIK_RELEASE` is the release, spelled as a module version takes it, and `LUNATIK_VERSION` the
string a script reads as `_LUNATIK_VERSION` and `lunatik -V` prints. A module declares
`MODULE_VERSION(LUNATIK_RELEASE)` beside its license: modpost writes the `srcversion` that
`lunatik reload` compares only for a module that declares a version, unless the kernel sets
`CONFIG_MODULE_SRCVERSION_ALL`.

### Writing a binding
A kernel module exposing a Lua library `foo` whose objects count: the private structure, its
checker, a method table carrying `__gc` and `__close`, the class, a constructor, and the module's
entry points.
```C
#include <linux/module.h>

#include <lunatik.h>

typedef struct luafoo_s {
	lua_Integer count;
} luafoo_t;

static const lunatik_class_t luafoo_class;

LUNATIK_PRIVATECHECKER(luafoo_check, luafoo_t *, &luafoo_class);

static int luafoo_inc(lua_State *L)
{
	luafoo_t *foo = luafoo_check(L, 1);

	lua_pushinteger(L, ++foo->count);
	return 1;
}

static const luaL_Reg luafoo_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{"close", lunatik_closeobject},
	{"inc", luafoo_inc},
	{NULL, NULL}
};

static const lunatik_class_t luafoo_class = {
	.name = "foo",
	.methods = luafoo_mt,
	.opt = LUNATIK_OPT_MONITOR,
	.owner = THIS_MODULE,
};

static int luafoo_new(lua_State *L)
{
	lunatik_newobject(L, &luafoo_class, sizeof(luafoo_t), LUNATIK_OPT_NONE);
	return 1; /* object */
}

static const luaL_Reg luafoo_lib[] = {
	{"new", luafoo_new},
	{NULL, NULL}
};

LUNATIK_CLASSES(foo, &luafoo_class);
LUNATIK_NEWLIB(foo, luafoo_lib, luafoo_classes);

static int __init luafoo_init(void)
{
	return 0;
}

static void __exit luafoo_exit(void)
{
}

module_init(luafoo_init);
module_exit(luafoo_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_VERSION(LUNATIK_RELEASE);
```
A script then runs `local foo = require("foo")` and `foo.new():inc()`.

---

## Memory

### lunatik\_malloc
```C
void *lunatik_malloc(lua_State *L, size_t size);
```
Allocates `size` bytes using the Lua allocator. Returns `NULL` on failure. The allocator asks for
the runtime's `gfp`, [`lunatik_gfp`](#lunatik_gfp), without an allocation warning; with
`GFP_KERNEL`, a block larger than a page may come from `vmalloc`. Free it with `lunatik_free`,
never `kfree`.

### lunatik\_realloc
```C
void *lunatik_realloc(lua_State *L, void *ptr, size_t osize, size_t nsize);
```
Reallocates `ptr`, currently `osize` bytes long, to `nsize` bytes using the Lua
allocator. Returns `NULL` when `nsize` is zero, which frees `ptr`, and when the
allocation fails, leaving `ptr` allocated; the exception is a shrink whose
allocation fails, which returns `ptr` itself, still `osize` bytes long. When
`ptr` is `NULL`, `osize` is not read as a size: either `0` or a type tag is
accepted.

### lunatik\_free
```C
void lunatik_free(void *ptr);
```
Frees memory allocated by `lunatik_malloc` or `lunatik_realloc`. Equivalent to `kvfree`.

### lunatik\_checkalloc
```C
void *lunatik_checkalloc(lua_State *L, size_t size);
void *lunatik_checkzalloc(lua_State *L, size_t size);
void *lunatik_checknull(lua_State *L, void *ptr);
int lunatik_enomem(lua_State *L);
```
Raise `not enough memory` instead of returning `NULL`: `lunatik_checkalloc` is
`lunatik_malloc`, `lunatik_checkzalloc` the same zeroed, and `lunatik_checknull` returns `ptr`,
raising when it is `NULL`. `lunatik_enomem` raises the error itself.

### lunatik\_gfp
```C
gfp_t lunatik_gfp(lunatik_object_t *object);
```
Returns the `gfp_t` `object` allocates with: `GFP_ATOMIC` for a SOFTIRQ or HARDIRQ object and
`GFP_KERNEL` otherwise. A runtime's is its allocator's, `GFP_KERNEL` while its script body runs
and the object's while it calls a monitored method.
A binding that allocates outside the Lua allocator passes `lunatik_gfp(lunatik_toruntime(L))`.
Defined as a macro.

---

## eBPF bindings

```C
#include <lunatik_ebpf.h>
```
The helpers of a binding whose kfunc an eBPF program calls to run a Lua callback, as
[`lib/luaxdp.c`](../lib/luaxdp.c) does. Building one needs the running kernel's BTF,
`sudo make btf_install` before `make`; without it the module loads with its kfunc unregistered,
logging `missing module BTF, cannot register kfunc` (`kfuncs` on v6.8 and earlier), and an eBPF
program that calls the kfunc fails to load.

### LUNATIK\_EBPF\_RUN
```C
#define LUNATIK_EBPF_RUN(key, key_sz, handler, ret, ctxp)
lunatik_object_t *lunatik_ebpf_lookupruntime(char *key, size_t key_sz);
```
The kfunc's body: `lunatik_ebpf_lookupruntime` finds the runtime stored at `key` in
`lunatik._ENV.runtimes`, where `lunatik run` keeps the runtimes it starts by script name, and
`LUNATIK_EBPF_RUN` runs `handler(L, ctxp)` on it with [`lunatik_run`](#lunatik_run), sets `ret`
with its result, a negative one, `lunatik_run`'s `-ENXIO` and `-EDEADLK` included, as `-1`, then
drops the reference the lookup took. `key_sz` counts the terminator, which the lookup writes at
`key[key_sz - 1]`. A key with no runtime, and a process runtime, which it logs, run nothing and
leave `ret` as it was. The
binding keeps the `runtimes` table the first lookup to find one returns; until then, a lookup made
while `lunatik_run.ko` is not loaded runs nothing, which it logs.

### lunatik\_ebpf\_bind
```C
void lunatik_ebpf_bind(lua_State *L, int ix, int *cb);
void lunatik_ebpf_unbind(lua_State *L, int *cb);
void *lunatik_ebpf_findctx(lua_State *L);
void *lunatik_ebpf_getctx(lua_State *L);
int lunatik_ebpf_invoke(lua_State *L, int cb, int nresults);
int lunatik_ebpf_action(lua_State *L, int cb, lua_Integer min, lua_Integer max);
```
A runtime has one callback context, the userdata of an object of the binding's class, kept in
its registry. `lunatik_ebpf_bind`, called with that userdata on top of the stack, references the
callback at `ix` in `cb`, stores the userdata and pops it. `lunatik_ebpf_findctx` pushes the
userdata and returns its private, or pops and returns `NULL` when the runtime has none;
`lunatik_ebpf_getctx` also logs `no callback attached` then. `lunatik_ebpf_invoke` calls the
callback `cb` with the value on top of the stack, the userdata `findctx` pushed, in a protected
call, and returns `-1` after logging the error, `0` otherwise, with its `nresults` results on the
stack. `lunatik_ebpf_action` invokes it for one result and returns that result when it is an
integer from `min` to `max`, and `-1` when the callback raised or returned nil, or, logging
`invalid action`, anything else. `lunatik_ebpf_unbind` releases
`cb`, clears the stored userdata, and pops the one `findctx` pushed.

### lunatik\_ebpf\_attach
```C
void lunatik_ebpf_attach(lua_State *L, obj, field, new_fn, ...);
void lunatik_ebpf_detach(lua_State *L, obj, field);
```
Like [`lunatik_attach`](#lunatik_attach), and it also takes a reference on the new object, which
the context's `release` drops; `lunatik_ebpf_detach` removes the registry entry and leaves
`obj->field` for that release. Defined as macros.

### LUNATIK\_EBPF\_NEWLIB
```C
#define LUNATIK_EBPF_START()
#define LUNATIK_EBPF_END()
#define LUNATIK_EBPF_KFUNC_DEFINE_SET(subsys, kfunc)
#define LUNATIK_EBPF_NEWLIB(subsys, lib, class)
#define LUNATIK_EBPF_KFUNC_INIT(subsys, prog_type)
#define LUNATIK_EBPF_EXIT(subsys)
```
The module around the kfunc. `LUNATIK_EBPF_START()` and `LUNATIK_EBPF_END()` enclose the kfunc's
definition; `LUNATIK_EBPF_KFUNC_DEFINE_SET` puts `kfunc` in the BTF set `bpf_lua<subsys>_set`
and defines `bpf_lua<subsys>_kfunc_set`, the id set that wraps it; `LUNATIK_EBPF_NEWLIB` is
[`LUNATIK_CLASSES`](#lunatik_classes) and [`LUNATIK_NEWLIB`](#lunatik_newlib) for the one class;
`LUNATIK_EBPF_KFUNC_INIT` defines `lua<subsys>_init`, registering `bpf_lua<subsys>_kfunc_set`
for the program type `prog_type`, and
`LUNATIK_EBPF_EXIT` defines `lua<subsys>_exit`. The binding then names both in `module_init` and
`module_exit`.

---

## Symbols

### lunatik\_lookup
```C
void *lunatik_lookup(const char *symbol);
```
Returns the address of the kernel symbol named `symbol`, or `NULL` when kallsyms does not carry
it. Never sleeps, so it is callable from any context, a softirq or hardirq handler included:
`kallsyms_lookup_name`, which the kernel does not export, is resolved through a kprobe once,
while `lunatik.ko` loads. Each call searches the kernel's symbol table, so a handler resolves a
name once and keeps the address rather than asking per event. Every lookup answers `NULL` when
that resolution fails, as it does without `CONFIG_KPROBES` or `CONFIG_KALLSYMS`.

