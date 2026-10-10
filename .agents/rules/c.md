---
paths:
  - "**/*.c"
  - "**/*.h"
---

# Object model

`lunatik_newobject(L, class, size, opt)` allocates and pushes a userdata;
`lunatik_createobject(class, size, ...)` allocates without a Lua state.

* `LUNATIK_OPT_EXTERNAL` in the class's `opt` means `object->private` is a pointer Lunatik does not
  own and will not free. The `release` callback still runs.
* Cleanup belongs in an explicit `detach`/`stop`, not hidden in `release`. `release` should be a noop
  unless there is no alternative.
* Do not name a C internal allocator `luaXXX_new`. That name implies the object is constructible from
  Lua. Use `luaXXX_attach` when it is not.
* Large allocations use `kvmalloc`, and therefore must be freed with `kvfree`, never `kfree`.
* Objects a C module pre allocates but exposes to Lua use `lunatik_createobject` plus
  `lunatik_pushobject`, which clones under a reference of its own and refuses a
  `LUNATIK_OPT_SINGLE` object.

A registration a percpu script makes once for all its runtimes, a hook or a kernel thread, lives
in the private of an object from `lunatik_percpudata`, of a class the binding declares for it, whose
`release` the percpu object runs before closing the runtimes. A binding that keeps a global list
or a use count of its own to find what the other runtimes registered is doing the object's job.

That registration arms before the set exists. `lunatik_percpu` creates the runtimes one at a time and
writes each per-CPU slot last, after that runtime's script body has run, so a hook or a kprobe armed
from the first body fires while the other slots are still NULL — and the body is where it must be armed,
since `lunatik_percpudata` refuses to create shared data once the runtime is ready. Whatever dispatches
through a percpu object therefore has to survive a runtime that is not published yet: `lunatik_run`
answers `-ENXIO`, as it already does for a runtime whose script is still loading.

The registry pattern for a reusable per hook object (`lunatik_getregistry`, reset, pass to Lua, clear
afterwards) is used by `lib/luanetfilter.c` for its `skb`. Follow it rather than inventing a variant.

A fact about a runtime has two homes, and which one is decided by who sets it. The core's live in
`lunatik_runtime_t` (`lunatik.h`), which embeds the runtime's object as its first member, so the
object's free frees it, and which every task that holds a reference reaches through
`lunatik_runtimeof`: the CPU, the percpu set and `ready` are there, and what only a runtime holds
costs no other object anything. One only a binding sets and reads lives in the registry under the
binding's own static key, as `luakfunc_env_key` and `fsnotify`'s callback flag do; the registry is
one per state and every coroutine shares it. Lua's extra space holds the runtime's pointer alone,
which `lunatik_toruntime` reads: `lua_newthread` copies it into every coroutine when it is made and
`lua_close` frees it with the state, so a fact kept there is right only while fixed and only while
the state lives. A core field the core neither sets nor reads is a contract the core cannot keep: a flag kept in the
extra space reads clear in a coroutine made before it was set and stays set in one made inside, and
`tools/checks/extraspace.sh` names a change that sizes the extra space again. The home of a field is
part of the design that was agreed, not a detail below it. A registry slot a callback writes is seeded where a protected call runs, the constructor: the
dispatch path runs outside one, and a first insertion that rehashes and fails to allocate aborts
the state, where a boolean stored on an existing node cannot.

# C style

* C99: initialize at declaration.
* `else` on its own line, never `} else {`.
* Single statement `if` without braces, and a loop whose body is one statement, an `if` included, the
  same.
* Block comments `/* */`, never `//`.
* Symbols in a library are prefixed `LUA<LIBNAME>_` or `lua<libname>_`.
* The `l` prefix on a Lua binding (`lunatik_lruntime`) exists to disambiguate from a C function of
  the same name. Without that collision, the plain name is the right one.
* A name matches what the tree already calls the same thing; grep for it before choosing. A Lua stack
  index is `ix`, a callback `cb`. Importing `arg` or `callback_ref` where the base settled on a
  shorter word is a deviation.
* A helper's name is the verb the tree already uses for that step, `match`, `find`, `register`,
  `free`, `share`, `own`, `attach` and `detach` being the ones in place. The noun joins the verb
  when that verb has more than one kind to act on — `luarcu_newentry` beside `luarcu_newtable`,
  `luacrypto_aead_newrequest` beside `luacrypto_aead_new` — or when the mirror it pairs with
  carries one, as `luadarken_freerequest` does beside `luadarken_setrequest`; it does not when it
  only repeats what the type already says, which is what `luanetfilter_findhook` did in a file
  whose only list holds hooks.
* Kernel headers first, then a blank line, then `#include <lunatik.h>`. Do not remove that blank line.
* `<lua.h>` and `<lauxlib.h>` are already pulled in by `lunatik.h`.
* Every file ends with a trailing blank line. `tools/checks/pre-commit` rejects a commit that does
  not.
* Lunatik has no floats. Do not check `lua_isinteger`.
* Multi line macros use the `do { ... } while (0)` form.
* Do not duplicate a struct defined by another module; use its exported API. The same for
  behaviour: look for the helper the tree already has before writing one. `lunatik_pusherrname`
  already turns an errno into `EINVAL`, and `autogen`'s emitter already writes the config a Makefile
  was about to write a second time.
* Prefer a named `static inline` helper over an open coded repetition, and do not inline an existing
  named helper into its callers while refactoring; they exist for readability and symmetry. A
  sequence two bindings spell is that helper too, in the core when its calls are the core's, and
  `tools/checks/core-helper.sh` names the sequence a change adds that another file already spells.
* A function does one thing; whether to do it is its caller's decision. An early return added at the
  top of a function that creates something, guarded by a lookup with its own stack juggling, moves
  that decision into the wrong place: the lookup becomes a `has`/`is` predicate beside the ones the
  header already has, and the caller that loops over the work tests it, as `lunatik_newclasses` tests
  `lunatik_hasclass`.
* When a two line pattern repeats in every method, collapse it into one helper or macro.
* A pointer-keyed registry slot is read with `lua_rawgetp` and written with `lua_rawsetp`, never
  with `lua_pushlightuserdata` followed by `lua_rawget` or `lua_rawset`. The pair spells one
  operation as two, and on the write it leaves the key on the stack under whatever runs between them.
* A helper meant to be shared is held to a higher design bar than a one-off, because everything
  built on it inherits its shape: a pair mirrors, so whatever one half acquires or registers its
  partner releases or unregisters, and an argument on one appears on the other; a family of helpers
  or macros names the same argument the same way, carries the same prefix, and types a value for
  what it is, not for how it is stored.
* A secondary check that must always follow a `LUNATIK_PRIVATECHECKER` (a field that must be set,
  the class identity of the object) goes in the macro's vararg body, in the mold of `luaskb_check`;
  `L` and `ix` are in scope there. A hand written checker only when the macro's shape does not fit.
* A method that reads `private` as its own type checks the class first. `lunatik_checkobject`
  accepts any Lunatik object, so a foreign object's private read through this class's pointer is a
  kernel crash reachable from Lua: `getmetatable(a).method(b)` is one line of script. The check is
  `lunatik_argcheckclass` in the checker's body, or in a hand written checker when the cast needs
  `__force`.
* A per-CPU access names the guarantee it has: `this_cpu_ptr` where preemption is off, `per_cpu_ptr`
  with an explicit id, and `raw_cpu_ptr` never to silence the check a preemptible caller would trip.
  A cast into an annotated address space or type, `__percpu` or `__bitwise`, carries `__force`, as
  the `opt` constants do.
* `/*** @section name */` separates logical sections in a merged C file and groups them in the docs.
* Two short mutually exclusive calls read better as a ternary than a four line if/else; void arms are
  fine. This does not transpose to Lua (see `.agents/rules/lua.md`).
* Function pointers get a named typedef: `lua<libname>_<role>_t`.
* A check on the runtime or the execution context raises with `luaL_error` and is named for what it
  examines, as `lunatik_checkruntime` and `lunatik_checkclass` are; the polarity belongs in the
  message, not in the identifier. Its message is a `LUNATIK_ERR_*` constant, and a condition the
  family has no check for gets its `lunatik_check*` helper beside the others in `lunatik.h`, which
  `guards.sh` counts, so a change that drops it is named; `tools/checks/idioms.sh` names a refusal
  spelled as a literal. `luaL_argcheck` is for a value that arrived at an index and is wrong: using it
  for a context error blames argument #1 for something no argument could have fixed.
* A sentinel value gets a name as soon as it appears in more than one place: `cpu != LUNATIK_CPU_NONE`
  says what `cpu >= 0` only implies, and ties the definition, the default and every test of it.
* For every raise after acquiring a resource, know what is already held and who releases it; validate
  before acquiring whenever the check does not need the resource, and compute a value after the checks
  that do not read it, which `tools/checks/idioms.sh` names. The mirror holds too: a reference the
  `release` will drop is taken before the first call that can raise, and a registration made before the
  object is complete is undone on every error path out of the constructor.
* An assignment used as a value inside a condition is parenthesised: `<` binds tighter than `=`, so
  `n = f() < 0` stores the comparison and not the count.
* An integer that names a kernel identity, a pid, is bounded with `lunatik_checkinteger` before the
  cast the kernel's type takes, as `socket.new` bounds the pid it resolves a namespace by:
  `(pid_t)luaL_optinteger` read `2^32 + 1` as pid 1 in `linux.netns`, and `tools/checks/idioms.sh`
  names the cast.
* A method the monitor leaves unwrapped, a `close` or a `stop`, reads the object's private under the
  object lock, and what it decides on that read it does under the same hold: a read outside it can find what a
  sharer's close freed, and a read and a close under two holds let a sharer's join slip between them.
* A size, length or count that arrives from Lua is bounded with `lunatik_checkbounds`, for what the
  binding itself can serve: `roundup_pow_of_two` is undefined at zero, `__kfifo_alloc` truncates to an
  unsigned int, and the multiplication that sizes an object wraps before any allocator sees it. What
  the bound does not buy is silence from the kernel: a script reaches the Lua state's allocator with a
  size no binding named, `("x"):rep(1 << 40)` among them, so it is that allocator that asks for
  `__GFP_NOWARN`, since Lua turns the NULL into an error the script sees.
* The minimal representation: a raw pointer where a struct would wrap one field, a fresh allocation
  where a cache would need invalidating, a function where a macro is not clearer. A structure earns
  its place by what it buys, not by looking more complete. A macro that grows an arm or an operation
  to carry a new rule is the moment to write the functions instead, as the lock functions of
  `lunatik_lock.h` are, over one predicate, `lunatik_isirqsave`. A rule that takes one sentence to state takes one predicate to code.
* A field that stores what its reader can compute when it runs is a copy, not a field: the fsnotify
  event's frame kept the accessing task's pid for an accessor that only ever runs inside the callback,
  in that task, where `current` answers. The same holds for a wrapper written to fit a macro whose
  varargs already take the call, `lunatik_attach(L, obj, field, lunatik_newobject, &class, 0, opt)`.
* A field beside an embedded kernel object is asked first what the object already records:
  `hlist_del_init_rcu` leaves `pprev` NULL for `hlist_unhashed_lockless` to read, `list_del_init`
  leaves the node empty for `list_empty`, a `kref` carries its count and a timer answers
  `timer_pending`; `tools/checks/kernel-answer.sh` names such a field.
* A kernel version guard puts the current kernel's code in its `#if` arm and the older kernel's in
  `#else`, tested with `>=` on the version that introduced the API, or on the macro that arrived
  with it where a stable series backports the change: raising the floor then deletes `#else` arms
  and touches no line that stays. `lunatik_pusherrname` is the shape, `errname` in the `#if` arm
  and the `%pe` fallback below it; `#if (LINUX_VERSION_CODE < KERNEL_VERSION(6, 19, 0))` with the
  current call in `#else` is the inversion `idioms.sh` names.
* Every arm of a version guard or a header probe is safe on the kernels it selects: where a kernel
  lacks what the safe shape needs, that arm refuses with an errno the script sees rather than taking
  the unsafe path, and what each arm does is said in the binding's documentation, where the author
  of a script reads, and not only in the commit body: an `#ifdef` arm without `sk_net_refcnt_upgrade` would
  leave a closed TCP socket without a reference on its namespace, where an orphan's timer can run on a
  freed one.
* An errno crosses the C code negative, as the kernel returns it: `lunatik_throw(L, -EINVAL)`, or the
  raw return of the call that failed. The single normalisation is at the Lua boundary, where
  `lunatik_pusherrname` takes the absolute value.
* A `pr_err` on a path a callback reaches is `pr_err_ratelimited`, as `lib/luakfunc.h` uses throughout:
  a handler that logs per packet or per syscall is a printk storm the moment a script starts failing,
  and it competes with the log that would explain the failure.
* A log or error message is one terse line naming the condition, in the tree's voice — `couldn't find
  X`, lowercase, no trailing period — not a sentence spelling out the cause and its caveats. The
  reasoning behind a failure belongs in a code comment or the commit message, not the runtime log; a
  `pr_err` that reads as a paragraph is the smell.

