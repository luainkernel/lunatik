# Working on Lunatik

This file holds what speaks of Lunatik alone, under the section names of `harness/AGENTS.md`, which
binds here as this file does: the harness Lunatik shares with luaebpf, mounted at `harness/` with its
rules, skills and checks.

Two rules outrank everything else in this document:

1. **Verify, do not assume**, as `harness/AGENTS.md` states it. How the Lua the kernel runs behaves
   is read the same way, in the `_KERNEL`
   arms of `lua/` and in `lunatik_conf.h`, never in upstream Lua's defaults: #2556 was filed on how
   upstream Lua converts a float, a value the kernel's Lua cannot hold.
2. **Know your execution context.** Code that may sleep must not run from softirq or hardirq context.
   See "Execution contexts" below.

## Layout

| Path | What lives there |
|------|------------------|
| `lunatik_*.c`, `lunatik.h` | core runtime, object model, C API |
| `lua/` | the Lua fork (luainkernel/lua): upstream's git mirror plus the `_KERNEL` patch, which adapts Lua to the kernel and gives the VM no behaviour upstream's lacks, modifying only, `#ifndef _KERNEL` with upstream first; code the kernel side needs is added on the Lunatik side, `luac/` included, never to the fork |
| `luac/` | the luac fork (luainkernel/luac): the release tarball's `luac.c`, which the git mirror does not carry, plus the `_KERNEL` patch; a bump is an "update to Lua x.y.z" commit made from the tarball |
| `klibc/` | the klibc fork (luainkernel/klibc): upstream's tags mirrored, and per release a `klibc-x.y.z-kernel` branch, upstream's tag plus Lunatik's two setjmp patches (arm64 saves x18, x86_64 returns through the retpoline and rethunk thunks), which the fork's `lunatik` branch follows; the tree links only each architecture's `setjmp.S`, `archsetjmp.h` and `archconfig.h` and libgcc's 64-bit division helpers, so a bump is read against those files |
| `include/` | the C library headers the kernel's Lua includes, written over the kernel's headers and klibc's setjmp |
| `lib/lua*.c` | kernel modules, one `.ko` each, exposing a Lua module |
| `lib/*.lua`, `lib/*/*.lua` | kernel side Lua libraries, installed to `/lib/modules/lua/` |
| `common/` | Lua both sides run: installed under `/lib/modules/lua/`, where kernel scripts require it, as source whatever `BYTECODE` says, since the CLI's Lua refuses a chunk `lunatic` writes, and linked into the host's `LUA_PATH` under `lunatik/`, as `lunatik/config.lua` is, where the CLI requires it by that name, so that a program file's body, requiring it by the kernel's name, loads it from the kernel scripts through `lunatic` |
| `autogen/` | build time generation of `linux.*` constant tables from kernel headers |
| `driver.lua` | the script of the runtime `lunatik_run.ko` creates for the `/dev/lunatik` driver, installed as `lunatik/driver` |
| `bin/` | the host side: the CLI, `bin/lunatik`, which talks to the kernel through `/dev/lunatik`, and what it builds or loads, installed where the host finds it |
| `tests/` | KTAP integration tests, one directory per suite |
| `examples/` | example kernel scripts |
| `tools/` | Lunatik's own maintenance scripts, and its checks in `tools/checks/`, which `.agents/rules/lunatik-checks.md` describes |
| `harness/` | the harness (luainkernel/harness), a submodule; it runs on the host, in a session and in CI, and installs nowhere |
| `luaebpf/` | the Lua to eBPF compiler (luainkernel/luaebpf), mounted as a submodule and built and installed by this tree's Makefile: a package of the CLI's Lua installed under the host's `LUA_PATH` as `luaebpf/`, and `luaebpf.loader`, the C module over libbpf that loads, attaches and pins what it writes, installed under `LUA_CPATH`; its `lib/` holds the modules a program file's body requires to declare what the object carries, `bpf.xdp` among them, and one named as a kernel module is that module's compile-time twin; the site builds its guide pages, `luaebpf/doc/guide/`, and a change to it is a pull request of luaebpf, which reaches Lunatik as one that moves the mount |
| `.agents/` | Lunatik's own skills, its host cycle (lunatik-cycle), a new binding and a new test suite, its rules for a kind of file, and the `harness.conf` the mount's scripts read |
| `.claude/` | Claude Code's wiring of both trees, which runs Lunatik's own guards, `crash-guard.sh`, `example-guard.sh` and `consumers-guard.sh` |
| `.github/` | the CI workflows |
| `doc/` | all documentation: the guide pages (`doc/guide/`), the hand written C API reference (`doc/capi.md`), design notes (`doc/design/`), the site's style (`doc/style/`), and generated LDoc output (everything else, gitignored) |
| `doc/design/` | design notes for work in progress: gap analysis, proposed APIs, verified kernel references, test strategy |

All documentation lives under `doc/`. There is exactly one documentation directory: never create a
second top level one (`docs/`, `documentation/`, and the like). A guide page goes in `doc/guide/` and in
the `topics` of `config.ld`, design notes go in `doc/design/<topic>/`, the C API reference is
`doc/capi.md`, and LDoc fills the rest of `doc/`. The README is the site's home page: what it does not
say in a few lines links to a guide page.

Code lives and installs where it runs. What runs in the kernel, the bindings, their Lua libraries, the
examples and the test scripts, lives in `lib/`, `examples/` and `tests/`, with `driver.lua` and the tables
`autogen/` writes, and installs under `/lib/modules/lua/`, the tree the kernel's `require` reads; what runs
in the CLI, on the host, lives in `bin/` and installs where the host finds it, its Lua where the host's Lua
does, as `lunatik/config.lua` is linked into the host's `LUA_PATH`; what both run lives in `common/`, and
installs on both sides. A new top-level directory gets its row in the table above, which says which side
it is. The luaebpf compiler, which runs only in the CLI's Lua, reached review after review at the root of
the tree, installing into `/lib/modules/lua/`, and once moved to `bin/` it required `class` from `lib/`
through a copy `make install` put in its own root, from a package at `bin/luaebpf/luaebpf/`.
`tools/checks/layout.sh` names a top-level directory the table does not list, a file `make install` puts
in the kernel's script tree from outside the trees that run there, one it puts in the host's Lua path
from a tree that runs only in the kernel, and a directory named as the one that holds it.

A definition goes where the tree keeps its kind, and that place is read before the definition is
written: the declarations of its siblings point at it, as `include/stdint.h` declares the libgcc helpers
a module of the tree calls on a 32-bit kernel. That compiler's runtime lives in the core, which exports
each helper the kernel does not: klibc's in the objects `Kbuild` links into `lunatik.ko`, and the ones
the tree writes in `lunatik_libgcc.c`, never in a binding or in `lunatik_aux.c`. #2132 first took
klibc's `__umoddi3.c` into `lib/lualinux.c` and defined `__divmoddi4` in `lunatik_aux.c`, beside nothing
of their kind. `tools/checks/layout.sh` names a libgcc helper defined outside `lunatik_libgcc.c`, and a C
source of klibc included anywhere.

A module or an example that needs a second file gets a directory, not a prefixed sibling:
`examples/systrack/probe.lua` beside `device.lua`, never `systrack_device.lua` beside `systrack.lua`. The
directory is named for what it holds, never as the directory that holds it: a reader takes `x/x/` for a
copy made by mistake.

## Build, install, test

    sudo apt install linux-headers-$(uname -r)     # after a kernel upgrade
    make                                           # build every module
    sudo make install                              # scripts, modules, examples, tests
    sudo lunatik reload                            # reload the modules
    sudo lunatik test                              # run every suite
    sudo lunatik test <suite>                      # run one suite

Use `sudo make install`, not the partial `*_install` targets. Use `sudo lunatik reload`, never
`rmmod`: the CLI knows the dependency order and unloads cleanly. What the shared host does to a cycle,
a module that will not unload, a wedged device, a stale install, is the lunatik-cycle skill's.

### Running a script

    lunatik run [--context=softirq|hardirq] <script>   # one shot
    lunatik spawn <script>                             # in a kernel thread, always sleepable
    lunatik stop <script>
    lunatik list

Scripts are resolved under `/lib/modules/lua/`. The CLI loads the kernel modules a script needs by
itself, through `require()`. Never tell a user to `modprobe lua*` by hand.

`lunatik run`, `spawn`, `stop` and `list` exit 1 when the kernel refuses them, with `lunatik:` and
its message on stderr and nothing on stdout, and a wrong invocation exits 2 with the usage on stderr.

## Execution contexts

A runtime is created in one of three contexts, and this decides what its code may do:

| Context | How | Allocation | Lock | May sleep |
|---------|-----|-----------|------|-----------|
| process | default, and always for `spawn` | `GFP_KERNEL` | mutex | yes |
| softirq | `lunatik run --context=softirq <script>` | `GFP_ATOMIC` | `spin_lock_bh`; `spin_lock_irqsave` with IRQs already off | no |
| hardirq | `lunatik run --context=hardirq <script>` | `GFP_ATOMIC` | `spin_lock_irqsave`, always | no |

Netfilter and XDP hooks need a softirq runtime, kprobes a hardirq one: a kprobe fires wherever the
probed code runs, an interrupt handler included, and there it would spin forever on a runtime lock
its own CPU holds unless that lock turns interrupts off.
A softirq object reached with IRQs already off, as an `rcu.table` written from a kprobe handler is,
locks with `spin_lock_irqsave`: a bottom-half unlock there runs the pending softirqs inline, inside
the probe.

The script body itself runs once at runtime creation, in process context, before the runtime is armed.
So registering hooks at the top level of a `softirq` script is legal and may sleep. Everything that
runs later, from a hook, may not.

Use `lunatik_cannotsleep(L, ...)` to reject a sleeping entry point called from an IRQ context runtime
rather than letting it deadlock the machine.

Which runtime of a percpu script a callback reaches is the CPU it fires on, and nothing else ties a
flow to one of them: the packets of one connection reach several. State that must see a whole flow
belongs in what the runtimes share, the runtime holds what is per-CPU. Which CPU each path lands on
is traced in `doc/guide/03-percpu.md`.

### Kernel threads

A script for `lunatik spawn` must return the thread body, poll for a stop request, and yield.
Violating any of these hangs the machine:

    local thread = require("thread")
    local linux  = require("linux")

    return function()
        while not thread.shouldstop() do
            -- non blocking work only
            linux.schedule(100)
        end
    end

The thread body runs holding the runtime lock, and `stop()` waits for it to return. A stop ends a wait
that reads signals: `kthread_stop()` sets `TIF_NOTIFY_SIGNAL` on the task before it wakes it, so a
`sock:receive()` with no timeout returns `ERESTARTSYS`, a `linux.schedule()` returns early, and a wait
for another runtime's lock, in `resume`, `stop`, `thread.run` and every monitored method, raises
`EINTR`. One thing it does not end, and it makes the thread unstoppable: a wait that goes back to
sleep without reading a signal, the lock a `device` file operation or a kernel call takes among them.
The runtime that calls `thread.run()` keeps the thread and stops it as it ends, so a worker another
body starts and drops ends with that body's runtime, as `examples/echod`'s workers do; an end made
on the thread's own body leaves the thread to run until that body returns.

A body that races another thread, a stress, pauses once per slice of its running rather than once
per turn: `linux.schedule()` sleeps until a timer fires whatever the timeout, 0 included, so a pause
per turn starves the race the stress is for.

## Releases

A release is declared in `lunatik.h`, by `LUNATIK_VERSION_MAJOR_N` and `LUNATIK_VERSION_MINOR_N`,
which every module carries as its `MODULE_VERSION` and `lunatik -V` prints, and is named `Lunatik
<tag>`, as its announcement is, `[ANN] Lunatik <tag> released`. Publishing one runs
`.github/workflows/doc.yml` on the `release` event, which builds the site,
luainkernel.github.io/lunatik: the newest release of each line from 5.0, the highest at its root and
each other one under its version, `5.0/`, and master under `master/`. Once pages deploys, the root's
footer names the release and links every other version's pages:

    curl -s https://luainkernel.github.io/lunatik/ | grep -oE 'Lunatik [0-9.]+ ·|<a href="[^"]*">[^<]* docs</a>'

## Deciding what to change

The comparison starts in the kernel. Before a mechanism is written over a kernel primitive, the
kernel's own answer to the same problem is read, `Documentation/` for the family and the primitive's
users under `lib/` and `kernel/`, and the commit body names the facility the shape was compared with,
or the page that offers none: a reader that must block has SRCU, a walk that drops the lock has the
contract the comment on `rhashtable_walk_enter` states, and a deferral of frees while readers sleep,
written by hand, is SRCU again. `tools/checks/kernel-answer.sh` names a commit whose body carries no
such comparison. An object the binding keeps past the code that lent it is compared resource by
resource: each keeper the comparison reads, the kernel's own code that keeps such an object, is read
for every resource the object carries, a device, a route, a conntrack entry, and the body names the
line each keeper has for each. An earlier push of #2099 read `nf_queue` and the socket receive queue
for the device alone and dropped the copy's route, as `ip_frag_queue` does, where those two force it
with `skb_dst_force`, as the merged one does.

Of code another project wrote, what the Lua of `lua/` compiles
is exported from the Lunatik side, as `lunatik_core.c` exports `luaS_hash` for `luarcu`, what klibc
offers is linked, as `Kbuild` links its division helpers into `lunatik.ko`, and what neither offers is
written over the kernel's primitives. `tools/checks/copied.sh` names a function a change adds that
spells a run of another project's tokens under no note.

Every example `tools/checks/examples-touched.sh` lists for the changed files is named in the pull
request body with what it did, ran, only loaded or not run and why; `tools/checks/examples-named.sh`
fails a body that leaves one unnamed, and `pr-body-guard.sh` runs it when a pull request opens.

`tools/checks/shadowed-readers.sh` lists the readers of a field a change keeps its own copy of, each
one a decision (`harness/AGENTS.md`, *Deciding what to change*).

A primitive every class inherits, the lock, the allocator, the context check, is changed for the
caller that needs it, in the arm that caller takes. Widening it to every arm because that is simpler
is a contract change for the callers that were already correct, and it belongs in the first line of
the commit body, naming what moves, never in a footnote of the pull request. A kprobe handler writing an
`rcu.table` needs interrupts off, and #891 keyed that on `irqs_disabled()`, the kernel's own rule,
leaving netfilter and XDP under bottom halves. `tools/checks/blast-radius.sh` lists what a changed
primitive reaches, on the file it left as well as the file it arrived in. A bound on what every
script shares, the kernel stack the C budget prices among them, is measured over the forms the tree's
own tools ship a script in as well as over the suite as installed: chunks `lunatic` compiles, which
`BYTECODE=1` installs, and modules `tools/shade.sh` encrypted, required in chains. It holds where the
resource is spent, not where the bound is read: a recursion that consults nothing is outside it
whatever the measurement showed, and `tools/checks/recursion.sh` lists the ones in the Lua the kernel
links.

* A check removed as redundant is traced to whoever establishes its invariant (`harness/AGENTS.md`):
  `invoke`'s type check is redundant because `attach` validates the callback first, so it is always a
  function there; a `pcall` that would catch a bad value anyway is a second reason, not the trace.
  A binding's Lua half establishes invariants
  the same way: where it guarantees a precondition, the C takes it, and what stays in C is the check
  whose absence crashes the kernel. That is what the split is for, and re-validating in C undoes it.
  A context that makes a family of refusals unreachable removes those it covers, route by route, and
  keeps the ones its rule leaves open; a mechanism a removal makes necessary is the removal going past
  what the trace showed. `guards.sh` counts the context checks, `lunatik_checkarmed`,
  `lunatik_checkrtnl`, `lunatik_checkowner` and `lunatik_checkirqs`, so `guard-removed.sh` names one
  a change drops.
* Of the refusals `harness/AGENTS.md` calls a legitimate outcome, `tools/checks/idioms.sh` names a load
  of one mode.
* A hazard is refused before it is engineered around. Where a context makes an operation unsafe, the
  operation is refused in that context, and a context is made where none names it yet; a deferral, a
  queue or a worker that keeps the unsafe call working buys a capability, and is weighed as one against
  the refusal that makes the hazard unreachable. A netdevice callback runs under RTNL, and a softirq
  runtime closes that family: nothing in it sleeps, so nothing waits on RTNL, and `lunatik_checkarmed`
  refuses under RTNL the replay the registration delivers before the runtime is armed.
* A prohibition and a capability are two things. Where the safe form of an operation needs a facility
  a later kernel adds, the binding refuses the operation where the facility is missing and uses it
  where it exists, behind a version guard, and does not reimplement it: a copy of the kernel's answer
  written here is a mechanism every later change serves, and it outlives the releases it was written
  for. A facility is looked up by what it calls as well as by its name: #1718 first refused `print`
  under the runqueue lock, reading that no release exports `printk_deferred`, where its callee,
  `vprintk_emit` at `LOGLEVEL_SCHED`, is exported in every release of the range, and the maintainer
  then took that call in place of the refusal and of a buffer flushed from a worker.
* A guard keys on a property that is true by construction where it is enforced, never on a proxy that
  merely correlates. That a registration is global is such a property. A netfilter hook number is not:
  the same hook runs in softirq or in process context depending on the path the packet took.
* A refusal is written for the resource, not for the entry point that showed the hang: the matrix it
  is held to lists every route from Lua to the lock or the call it protects, found by grepping what
  acquires it, `lunatik_lock`, `lunatik_closeprivate`, `lunatik_run` or the kernel call, and each
  route names its refusal or why it needs none. A refusal of `runtime:stop()` for the
  runtime's own lock covers `runtime:resume()`, `percpu:resume()` and `thread.run` too, which take
  it. The routes are everything the path runs while it holds the lock, the binding's own calls among
  them, not only what a script calls: a raise the dispatch logs is a printk under that lock.
* A guard in the core is for the honest mistake: the wrong object at an index, a size no binding can
  serve, a call that sleeps from a hook. The registry, a class metatable and an object's `__gc` are
  the runtime's own bookkeeping, and a script that reaches into them, `obj:__gc()`,
  `debug.getregistry()`, `getmetatable(obj).__gc = nil`, is out of contract, as one that spins in a
  hook is: root loaded it on the machine it breaks, and no guard closes that. A finding whose stimulus
  is such a script closes as not a defect, whatever it traces from there.
* A change that puts a route out of contract, a prohibition the binding's documentation now states,
  reads the open issues filed on that route in the same breath: one whose stimulus the prohibition
  covers is a capability and not a defect, relabelled or closed with the reason.
* The core and its bindings are not shaped by a consumer or by an example. An example that cannot
  be written, or that reaches what it needs through a channel no contract states, is evidence of a
  gap in the API; what fills that gap is decided from what the binding is for, and the commit and
  the pull request argue it that way.

## Patches and commits

* A C binding of `lib/` and a move of the compiler's mount, `luaebpf/`, are two pull requests, each one
  mechanism (`harness/CONVENTIONS.md`), the binding's first and the move stacked on it, even where the compiler
  reads what the binding adds: #2235
  carried `skb:data()`'s read of a non-linear skb, in `lib/luadata.c`, `lib/luaskb.c` and `lib/luatc.c`,
  under the compiler's TC read, and the maintainer asked "why we need all these changes on luadata and
  why they are all bundled into this luaebpf PR? ... it should at very least split into many PRs".
  `tools/checks/bundled.sh` names a branch that carries both, and the Checks workflow fails it.

## Before opening a pull request

1. `make` is clean, with no new warnings, and a change that touches a `__percpu` pointer, or any
   other address-space annotated one, is clean under `make C=1` too: sparse models the annotation as
   an address space, as GCC 14 on x86 does for `__percpu` (`__seg_gs`), so a `void *` holding one, or
   a cast between the two, is a warning here and a build error there;
2. `sudo make install && sudo lunatik reload && sudo lunatik test` passes;
3. new API is documented and listed in `config.ld`, and `make doc-site LUA=lua5.5`,
   the CI target, exits zero: a C file that contributes to a module another file declares carries
   `@module` with the same name, which `merge = true` in `config.ld` folds, since `@submodule`
   deduces its section name from a path under `lib/`. Its exit status is read, not its output: LDoc
   quits on a module it cannot place with a line that says neither "warning" nor "error", so a grep
   for those passes a failed run; then the links are checked to land on types, not functions;
4. every example that uses a binding the change touches is run, not only loaded, through the
   example's own `setup.sh` and `cleanup.sh` where it has them, and the hand-back says of each
   one whether it ran, only loaded, or was not run, and why. A loaded script that never fired
   its hook is the green build the review rule warns about.

