# Working on Lunatik

Conventions for contributors, and for AI coding assistants working on this repository. If you are
using an assistant that reads a project file automatically (`AGENTS.md`, `CLAUDE.md`, `.cursorrules`),
point it here.

Lunatik runs Lua inside the Linux kernel. A mistake here does not raise an exception, it panics a
machine. Two rules follow from that and outrank everything else in this document:

1. **Verify, do not assume.** Before using a kernel API, read its declaration in
   `/usr/src/linux-headers-$(uname -r)/include` and confirm it is exported in `Module.symvers`. A
   kernel interface read at runtime rather than linked — a `/sys` or `/proc` path and the format it
   returns, the `/dev/lunatik` protocol — is held to the same rule: confirm it against the source
   across the supported kernel range (5.15 and later), not from the one kernel you happen to run.
   Signatures and formats change between releases. If you have not checked, say so instead of
   asserting.
2. **Know your execution context.** Code that may sleep must not run from softirq or hardirq context.
   See "Execution contexts" below.

## Layout

| Path | What lives there |
|------|------------------|
| `lunatik_*.c`, `lunatik.h` | core runtime, object model, C API |
| `lib/lua*.c` | kernel modules, one `.ko` each, exposing a Lua module |
| `lib/*.lua`, `lib/*/*.lua` | kernel side Lua libraries, installed to `/lib/modules/lua/` |
| `autogen/` | build time generation of `linux.*` constant tables from kernel headers |
| `bin/lunatik` | userspace CLI, talks to the kernel through `/dev/lunatik` |
| `tests/` | KTAP integration tests, one directory per suite |
| `examples/` | example kernel scripts |
| `tools/` | maintenance scripts, and the mechanical convention checks in `tools/checks/` |
| `.agents/skills/` | the recurring workflows packaged as agent skills (open `SKILL.md` format) |
| `doc/` | all documentation: the hand written C API reference (`doc/capi.md`), design notes (`doc/design/`), and generated LDoc output (everything else, gitignored) |
| `doc/design/` | design notes for work in progress: gap analysis, proposed APIs, verified kernel references, test strategy |

All documentation lives under `doc/`. There is exactly one documentation directory: never create a
second top level one (`docs/`, `documentation/`, and the like). Design notes go in `doc/design/<topic>/`,
the C API reference is `doc/capi.md`, and LDoc fills the rest of `doc/`.

## Build, install, test

    sudo apt install linux-headers-$(uname -r)     # after a kernel upgrade
    make                                           # build every module
    sudo make install                              # scripts, modules, examples, tests
    sudo lunatik reload                            # reload the modules
    sudo lunatik test                              # run every suite
    sudo lunatik test <suite>                      # run one suite

Use `sudo make install`, not the partial `*_install` targets. Use `sudo lunatik reload`, never
`rmmod`: the CLI knows the dependency order and unloads cleanly.

`lunatik reload` cannot always replace the core module while something still holds it. If you changed
`lunatik.ko` itself and the behaviour did not change, verify rather than assume the new core is live.

After a kernel upgrade the installed modules were built for the previous kernel and fail to load with
`Exec format error` (a vermagic mismatch). Reinstall the headers, `make clean && make`, and reinstall
before the next `reload`. The eBPF modules also need the running kernel's BTF at build time,
`sudo make btf_install` before `make`, or they log `missing module BTF, cannot register kfuncs` and
do not load; and the `bpftool` wrapper needs `linux-tools-$(uname -r)`, or every BPF program fails
to load.

A wedged device — a `lunatik` process in D state, usually below an oops in `dmesg` — is cleared only
by a reboot, and the reboot is the maintainer's to trigger: other sessions share the host. Before
asking, capture what the reboot erases with `tools/oops.sh`, write down which suites were pending
and which build was installed, and run nothing else against the device. After it, the suite that
oopsed runs twice: a second oops is a bug to trace, a clean pair is a symptom without its cause,
said as such. The lunatik-cycle skill orders both halves.

Never run two `lunatik` operations at once. Concurrent operations wedge `/dev/lunatik` and leave
processes in D state. Check with `ps` before starting one.

A worktree named for a task may belong to another session on the same machine. Check
`git worktree list` and the branch a worktree holds before a checkout or a reset there, and never
reset a branch checked out elsewhere. A review, or a build of a branch not your own, runs in a
worktree created for it (`git worktree add`, then `git submodule update --init`) and removed at the
end.

A tree with a conflict pending (`git status` showing `UU`) is not a test subject: a suite run over a
half-applied rebase or cherry-pick measures neither side. Resolve and commit, then build.

`lunatik reload` unloads only the modules the installed CLI lists. A module loaded from another
branch's install escapes it and pins the core: `rmmod` reports `Module lunatik is in use by ...`
while `lunatik list` is empty. Diff `lsmod` against the installed `lunatik/config.lua` to find the
orphan and `rmmod` it — the one case where a manual `rmmod` is the fix.

The autogen output (`autogen/linux/*.lua`, `autogen/.config`, `autogen/.stamp`) is untracked build
state and does not follow a branch switch. The symptom is a runtime `attempt to index a nil value`
on a `linux.*` constant, not a build error. Regenerate cleanly with
`rm -f autogen/.stamp autogen/linux/*.lua && make`; autogen recreates the files, not the directory.

A worktree that has not run `make` cannot install: `scripts_install` needs the autogen output and
fails, and an install whose output was silenced fails unseen while the previous install stays in
place, so every run after it tests the wrong tree. Keep the install's output visible, and before
reading a result confirm that what sits under `/lib/modules/lua/` is the tree under test: its
timestamp, or a grep for a symbol only the branch has.

`lunatik test` reloads the modules before the suite and unloads them after it. A test script run
directly afterwards (`bash tests/<suite>/<test>.sh`) skips with `not loaded` until the next
`lunatik reload`; that unload is the CLI's, not a leak.

`make install` never removes a stray file from `/lib/modules/lua/`. A scratch script left there
shadows the module of the same name: `require` returns `true` and the failure surfaces later as
`attempt to index a boolean value`, far from its cause. Remove a scratch script right after
running it.

Trust the formal test over manual poking. Iterating by hand — `lunatik run`/`stop`, `iw`, `ip`,
`rmmod`, `modprobe` — leaves stale state that wedges the next run: an interface in the wrong mode, an
orphan `.ko` still pinning the core, a script still registered. A test's `.sh` does its own setup and
teardown; a green formal test is the authoritative result, not a red manual scratch fighting leftover
state. A known-clean baseline is a precondition for a valid observation, not an afterthought: restore
it before a run and again after, so what the next run sees is the code under test, not the residue of
the last one.

### Checks

`tools/checks/` holds the mechanical checks: comment and LDoc style on framework files
(`module-conventions.sh`), test scripts that cannot detect a failed load (`test-harness.sh`),
cppcheck on userspace test C (`cppcheck-tests.sh`), and the trailing blank line rule (`pre-commit`).
Each takes file paths and skips what does not apply, so any editor, assistant, or CI can run them.
The `Checks` workflow runs them over a pull request's diff: the trailing blank line rule fails the
run, the heuristic checks annotate it. Install the commit gate with:

    ln -s ../../tools/checks/pre-commit .git/hooks/pre-commit

`guard-removed.sh` names the crash guards a C file drops against `HEAD` (a checker, an
`argcheck`, a context check): removing one and running the test that covers it reproduces the
crash the guard prevents, and on the shared host that is a forced reboot. `crash-guard.sh`, wired
before a shell call like the review guard below, blocks an install, reload or run while any
worktree drops such a line, unless the command carries `CRASH_AB_OK=1`, set once the maintainer
authorized the experiment and named the machine it may take down.

`pr-body.sh` takes a pull request body file and fails it on more than three paragraphs, an em dash
or a "Test plan" section; `pr-body-guard.sh`, wired before a shell call like `crash-guard.sh`,
blocks a `gh` write to pulls that carries a body file the check fails on.

`review-post-guard.sh` reads the tool command on stdin instead of a file, for an assistant wired
to run it before a shell call (`PreToolUse`): it blocks a `gh` write to reviews or comments unless
the command carries the `REVIEW_POST_OK` marker, set once the exact text has been shown to the
maintainer and approved, or when the text gives a fixup reference as a backtick'd SHA, which
renders as code and does not link. The marker forces the show-then-post step; it cannot check that
the text was shown, only that it was set on purpose.

### Skills

`.agents/skills/` packages the recurring workflows — the build/test cycle, a new binding, a new
test suite, preparing a pull request — as agent skills in the open `SKILL.md` format
([agentskills.io](https://agentskills.io)), discovered by any compatible assistant. Each one
defers to this file as the authority and orders the steps; none replaces reading it.

For Claude Code, `CLAUDE.md` imports this file, `.claude/settings.json` runs `review-post-guard.sh`
and the file checks as hooks, and `.claude/skills/` links to `.agents/skills/`; nothing there holds
logic of its own.

### Running a script

    lunatik run <script> [softirq|hardirq]   # one shot
    lunatik spawn <script>                   # in a kernel thread, always sleepable
    lunatik stop <script>
    lunatik list

Scripts are resolved under `/lib/modules/lua/`. The CLI loads the kernel modules a script needs by
itself, through `require()`. Never tell a user to `modprobe lua*` by hand.

`lunatik run` exits 0 even when the script fails to load; the error only appears on stdout. Test
harnesses must assert on output, not on exit status.

## Execution contexts

A runtime is created in one of three contexts, and this decides what its code may do:

| Context | How | Allocation | Lock | May sleep |
|---------|-----|-----------|------|-----------|
| process | default, and always for `spawn` | `GFP_KERNEL` | mutex | yes |
| softirq | `lunatik run <script> softirq` | `GFP_ATOMIC` | `spin_lock_bh` | no |
| hardirq | `lunatik run <script> hardirq` | `GFP_ATOMIC` | spinlock, IRQs off | no |

Netfilter and XDP hooks fire in softirq, kprobes in hardirq; those scripts need the matching context.

The script body itself runs once at runtime creation, in process context, before the runtime is armed.
So registering hooks at the top level of a `softirq` script is legal and may sleep. Everything that
runs later, from a hook, may not.

Use `lunatik_cannotsleep(L, ...)` to reject a sleeping entry point called from an IRQ context runtime
rather than letting it deadlock the machine.

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

Unbounded blocking calls in a kernel thread make it unstoppable: the thread body runs holding the
runtime lock, and `stop()` waits for the body to return, which a `sock:receive()` with no timeout never
does — the socket layer does not check `kthread_should_stop()`. To wait indefinitely, bound each call
(a receive timeout, or `MSG_DONTWAIT`) and poll `shouldstop()` in the loop.

## Object model

`lunatik_newobject(L, class, size, opt)` allocates and pushes a userdata;
`lunatik_createobject(class, size, ...)` allocates without a Lua state.

* `.pointer = true` means `object->private` is a pointer Lunatik does not own and will not free. The
  `release` callback still runs.
* Cleanup belongs in an explicit `detach`/`stop`, not hidden in `release`. `release` should be a noop
  unless there is no alternative.
* Do not name a C internal allocator `luaXXX_new`. That name implies the object is constructible from
  Lua. Use `luaXXX_attach` when it is not.
* Large allocations use `kvmalloc`, and therefore must be freed with `kvfree`, never `kfree`.
* Objects a C module pre allocates but exposes to Lua use `lunatik_createobject` plus
  `lunatik_cloneobject`, which requires `.shared = true`.

A registration a percpu script makes once for all its instances, a hook or a kernel thread, lives
in the private of an object from `lunatik_percpudata`, of a class the binding declares for it, whose
`release` the percpu object runs before closing the instances. A binding that keeps a global list
or a use count of its own to find what the other instances registered is doing the object's job.

The registry pattern for a reusable per hook object (`lunatik_getregistry`, reset, pass to Lua, clear
afterwards) is used by `lib/luanetfilter.c` for its `skb`. Follow it rather than inventing a variant.

## C style

* C99: initialize at declaration.
* `else` on its own line, never `} else {`.
* Single statement `if` without braces.
* Block comments `/* */`, never `//`.
* Symbols in a library are prefixed `LUA<LIBNAME>_` or `lua<libname>_`.
* The `l` prefix on a Lua binding (`lunatik_lruntime`) exists to disambiguate from a C function of
  the same name. Without that collision, the plain name is the right one.
* A name matches what the tree already calls the same thing; grep for it before choosing. A Lua stack
  index is `ix`, a callback `cb`. Importing `arg` or `callback_ref` where the base settled on a
  shorter word is a deviation.
* Kernel headers first, then a blank line, then `#include <lunatik.h>`. Do not remove that blank line.
* `<lua.h>` and `<lauxlib.h>` are already pulled in by `lunatik.h`.
* Every file ends with a trailing blank line. `tools/checks/pre-commit` rejects a commit that does
  not.
* Lunatik has no floats. Do not check `lua_isinteger`.
* Multi line macros use the `do { ... } while (0)` form.
* Do not duplicate a struct defined by another module; use its exported API.
* Prefer a named `static inline` helper over an open coded repetition, and do not inline an existing
  named helper into its callers while refactoring; they exist for readability and symmetry.
* A function does one thing; whether to do it is its caller's decision. An early return added at the
  top of a function that creates something, guarded by a lookup with its own stack juggling, moves
  that decision into the wrong place: the lookup becomes a `has`/`is` predicate beside the ones the
  header already has, and the caller that loops over the work tests it. `lunatik_newclass` grew such
  a guard and gave it back to `lunatik_newclasses` through `lunatik_hasclass`.
* When a two line pattern repeats in every method, collapse it into one helper or macro.
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
  fine. This does not transpose to Lua (see Lua style).
* Function pointers get a named typedef: `lua<libname>_<role>_t`.
* A check on the runtime or the execution context raises with `luaL_error` and is named for what it
  examines, as `lunatik_checkruntime` and `lunatik_checkclass` are; the polarity belongs in the
  message, not in the identifier. `luaL_argcheck` is for a value that arrived at an index and is
  wrong: using it for a context error blames argument #1 for something no argument could have fixed.
* A sentinel value gets a name as soon as it appears in more than one place: `cpu != LUNATIK_CPU_NONE`
  says what `cpu >= 0` only implies, and ties the definition, the default and every test of it.
* For every raise after acquiring a resource, know what is already held and who releases it; validate
  before acquiring whenever the check does not need the resource.
* The minimal representation: a raw pointer where a struct would wrap one field, a fresh allocation
  where a cache would need invalidating, a function where a macro is not clearer. A structure earns
  its place by what it buys, not by looking more complete.
* A log or error message is one terse line naming the condition, in the tree's voice — `couldn't find
  X`, lowercase, no trailing period — not a sentence spelling out the cause and its caveats. The
  reasoning behind a failure belongs in a code comment or the commit message, not the runtime log; a
  `pr_err` that reads as a paragraph is the smell.

## Lua style

* Line length 120.
* Localize stdlib functions at the top of a new module: `local insert = table.insert`.
* `require("x")` with parentheses.
* Use `table.insert`, not `t[#t+1] = v`.
* No nested function definitions; helpers go at module level.
* Hooks and callbacks are named `local function`s referenced by name, never anonymous functions inline
  in a table field.
* Named constants at the top: `local PORT <const> = 5562`. No magic numbers.
* CAPS `<const>` marks a scalar constant; a table used as a lookup, dispatch, or allow-list is a
  lowercase name by role — `codecs`, `tokens`, `fields` — never caps, even when it is `<const>`.
* Prefer the standard library (`string.match`, `string.gsub`, `table.*`) over hand written loops.
* The kernel Lua state has no `math.type`; use `type(x) == "number"`.
* A call repeated with the same arguments in one flow is resolved once into a local:
  `local kind = type(spec)`, then compare `kind`.
* Dispatch over a type or a key uses a table whose handlers are declared in place —
  `function codecs.string(format)` — not an if/elseif chain. Look the handler up once and guard the
  result with `== nil`; a looked-up constructor is named `new`, never the same name as what it builds.
* `cond and f() or g()` only when `f` is guaranteed to return a truthy value: if `f()` returns nil or
  false, `g()` runs too. Side effects and doubtful returns take if/else.
* Name variables by role, not by structure: `proxy`, not `tbl`; `openproxy` to pair with `openqueue`,
  not `opentable`.
* A module that makes objects returns a class or namespace table, never a bare function; that return
  is for builders like `class` and `struct`. The object holds its underlying handle in a named field
  — `socket`, `tfm` — not one prefixed with an underscore, and is constructed through `.new` or a
  `:__call` method on the class, as `hkdf` and `inet` do, not a metatable wrapped around the module to
  make it callable, which nothing in the tree does. The instance metatable is named for what it is,
  not `mt`.
* A proxy's metamethods do not allocate per access. `bpf.map`'s `view` resolves a key in one lookup;
  an `__index` that builds a closure on every method fetch, or composes `"get" .. key`, pays that on
  every packet in a softirq path, and the composed name collides with a real method spelled the same.
  A fixed set of fields is a table looked up once, not a name assembled each time.

Inside a CLI dostring, require once at startup and call by name afterwards:

    lunatik.foo = require("lunatik.foo")
    lunatik.foo.method(...)

Never `require("foo").method()`.

## Comments and documentation

* Comments describe the present, not the history. No "was", "no longer", "used to".
* No comments restating obvious kernel or Lua API usage. Non obvious rationale is welcome.
* A comment is one line carrying the reason the code is not obvious, nothing the code below already
  says. State the why; the what and the how are the code's job.
* A comment about a specific call goes on that call's line, not above the function signature.
* When the surprise is the call itself, a `put` where the tree would `stop`, the comment on the
  call's line gives the one reason it is not the expected call, `/* last reference: a stop would
  lock, and this can run in softirq */`; when the alternative is the other arm of the same `if`,
  the reason alone, `else /* this arm may sleep */`. The comment states the choice, not the world
  behind it; the invariant the choice rests on is the commit body's.
* Reaching for a comment is a signal to reconsider the code's clarity first: a name that states the
  intent, a helper that names the step, an enum instead of a bare constant. Comment what the code
  cannot be made to say, not what a clearer shape would.
* An internal `static inline` helper carries no block comment — `lunatik.h` keeps none on any of its
  own. A comment describing what such a helper does restates the code; the fix is removing it, not
  trimming it. A block survives only for a reason the code cannot state, as `checkkey`'s zero-size
  note does.
* Public functions and object types get LDoc comments. Use `@type <class>` names that do not collide
  with a function name, or LDoc will attach the wrong things.
* LDoc does not surface a method a class inherits. To show it on the subclass's page, add a doc-only
  `@function <class>:<method>` block there, with no function under it. A `--` comment placed directly
  before a `---` doc block silences that block; keep any rationale note above the doc block or inside
  the function.
* A new module needs an entry in `config.ld`, inserted in alphabetical order, and a row in the README
  module table.
* Do not insert code between a doc block and the function it documents.
* A doc block states the contract, not how it was found. Keep the debugging story — the crash that
  motivated a guard, the scenario that produced a stale state — in the commit body, where history
  belongs.
* The same holds for inline rationale: say why the code is what it is, not what it would take if
  something changed. Speculation about a future refactor ages badly and reads as doubt.
* Enumerate in one place only, and prefer none: a list of modules that adopt a rule rots on the next
  adoption, and the list of who calls a guard is the code. Restrictions on using a function are
  documented on that function, in its own `@raise`, where the caller reads.
* A doc block and the code it describes share vocabulary: an `@raise` states its condition in the
  same words as the error message it documents, and a rename in the code is a rename in the prose
  above it. An error message that names an API element quotes its canonical name, `rcu.table` and
  not a paraphrase of it; the name is looked up, never composed.

## Tests

Tests are shell scripts emitting KTAP plus a kernel side Lua script.

* the description of what a test does goes in the `.sh`. The `.lua` gets one line pointing back at it;
* skip, do not fail, when the kernel lacks a required config;
* mark `dmesg` before the run, read only what came after, and `check_dmesg` at the end;
* clean up in a `trap`, and run the cleanup once up front as well;
* the cleanup undoes everything any case can create, not only what the happy path stops inline: a case
  that fails before its own teardown leaves its runtime registered, and the next run finds it already
  there. A new case extends the cleanup in the commit that adds it, so the up-front run clears the
  leak and a green formal test stays authoritative;
* a test that guards a kernel crash is not proved by removing the guard: that reproduces the crash,
  and on the shared host it is a forced reboot. Its discrimination rests on the message it asserts.
  An experiment that does remove a guard is authorized by the maintainer beforehand, names the
  machine it may take down, and runs after the commit it is meant to prove; `crash-guard.sh` blocks
  the install or run until `CRASH_AB_OK=1` says that happened;
* a case tears down before it reads its verdict: every program it attached, pin it made and script it
  started is undone before the first check, so a failing check leaves nothing for the next case to
  trip on. A case that returns from a check with its program still attached turns one failure into
  one per case after it;
* a test does not depend on what else runs on the host: when a host process — a network manager, say
  — can race it by acting on a resource the test created, make the test robust to any such process,
  not wired to silence one by name, which does not carry to another distro or to CI;
* coverage means the matrix of operation by type by outcome, including the successes, not a list of
  features and not only the error paths;
* prove the test discriminates: disable the mechanism it covers, watch it fail, restore. Commit
  first, since restoring is a `git checkout --` that takes any uncommitted work with it;
* a test for an exactly once property runs on the path where that property is structural, and the
  header says which path and why. The same assertion on a path that can migrate CPUs mid way passes
  for the wrong reason;
* a test that guards a kernel crash is not proved by removing the guard. Say that its discrimination
  rests on the message it asserts, and prove the rest of the suite the usual way.

A test is not done until `tests/README.md` describes it, the suite's `run.sh` runs it, and, for a new
suite, the top level `README.md` lists it. Same commit, or a fixup of it.

## Deciding what to change

Code on `master` is not settled. When a new design makes an existing mechanism simpler, or subsumes
it, change or remove it. Working around it to keep a diff small leaves two mechanisms doing one job,
and every later change has to serve both. Authorship is not a reason to keep code, and neither is how
recently it was merged; a commit that removes or subsumes something already on `master` names it in
the body.

Reshaping or renaming an API means updating every consumer, grepped for — including consumers in
stacked or sibling pull requests that will rebase onto the change. A caller left on the old shape
compiles against a Lua module and only fails when its code path runs: `skb.attr` became a class with
`.new` and a pure attribute view, and `sniclassify`'s `skbattr(...)` / `skb:data()` — written for the
old factory — kept building and broke at the first packet.

* Do not land an implementation you already intend to replace. A guarantee that holds only on some
  paths is not a guarantee: make it structural or do not offer it. Merging a half measure and opening
  a follow up that deletes it pollutes the history across pull requests the same way a commit that
  undoes another one pollutes a branch.
* Removing a check as redundant is verified, not asserted: trace the invariant to whoever establishes
  it and confirm every path that sets the value does. `invoke`'s type check is redundant because
  `attach` validates the callback first, so it is always a function there; a `pcall` that would catch
  a bad value anyway is a second reason, not the trace.
* A function's contract — that it only reads, that it never sleeps, what it returns — is read from its
  body, not inferred from its name or its place in a method table. `connmark` reads and writes through
  one overloaded method despite sitting among read-only accessors; calling it read-only from where it
  sits is a guess, not a trace.
* Refusing is a legitimate outcome. When a combination has no sound semantics yet, refuse it where it
  is registered, with an error that names the reason, rather than shipping an approximation. Lifting
  the refusal afterwards is one line and a test.
* A guard keys on a property that is true by construction where it is enforced, never on a proxy that
  merely correlates. That a registration is global is such a property. A netfilter hook number is not:
  the same hook runs in softirq or in process context depending on the path the packet took.
* A call the conventions here already settle is made, not escalated: decide it, note it in a line, and
  move on. A question is for a genuine fork — where the answer changes the outcome and no rule,
  precedent, or test resolves it. Asking whether to add a comment the tree's macros never carry spends
  the maintainer on a call this document already made.
* "The tree does it" is a fact about the tree, not a reason. A choice is defended by what it buys and
  what it costs; prevalence says whether it is common, never whether it is right, and a tree can be
  wrong in a hundred places. When the only support for a line is a precedent, say so and judge it
  again.

## Patches and commits

* Small, auditable, incremental commits. Each one stands alone and adds value.
* A commit is one change and everything that change entails, even across modules: a new core check
  adopted by four bindings is one commit. Independent fixes are separate commits, even when a single
  review finding uncovered them all; the finding is the reviewer's unit, not the committer's.
* A change to a function is read against the whole function, not the lines it touches: re-read it
  and take the simplification the change enables. A guard left standing that the new shape made
  redundant — `!cond || check(cond)` where the call now sits inside `if (cond)` — is a partial fix.
* Change only what the task requires. Do not reformat untouched lines, do not move code, do not
  rename variables in passing. Compare `git diff` against `git diff -w` before committing to catch
  stray whitespace.
* No dead or unnecessary code. A branch that cannot execute — a nil check on a call that raises
  instead of returning nil — is noise that misstates the API's contract.
* No cosmetic changes inside a feature or fix commit, not even a blank line.
* Never remove an existing comment unless the change made it factually wrong.
* Restoring something that was removed puts it back exactly where and how it was.
* Subject line says what changed and why, not how. A body only when there is something the diff does
  not say: a new API, a behaviour change, a non obvious rationale. No bullet list of every detail.
* A pull request title and body follow the same rule: what and why, nothing the commits already say.
  No "Test plan" section, and no em dashes.
* The body opens with the failure or the need in one plain sentence — what a script can do today,
  what breaks, what has nowhere to live — then says what the change does, in a few lines, and what
  it depends on. Three short paragraphs at most. How the problem was found, what was measured and
  what was tried belong in the commits; a body a reviewer has to study is not a summary.
  `tools/checks/pr-body.sh` holds a body file to this.
* A pull request is one mechanism, read in one screen of diff and one paragraph of body. A body that
  needs a section per mechanism describes several pull requests: stack them, each on the one below.
* No session links or assistant footers in a commit or a pull request beyond the `Co-Authored-By`
  trailer. The project settings turn the link off; one that slipped in is removed with a reword.
* A root cause named in a commit body or a pull request rests on a captured stack or a source-traced
  chain, not a correlated log line or a plausible mechanism. Until it is traced it is a hypothesis,
  labelled as one; a fix may land on the observed behaviour without naming a cause it has not proven.
* Corrections to a commit on your own branch are `git commit --fixup=<hash>`, not a standalone
  "address review comments" commit. Never fixup a commit that is already on `master`; that becomes a
  new commit on a new branch.
* If a branch adds something in one commit and removes it in another, the second is a fixup of the
  first.
* After squashing, re read the comments and commit bodies so they describe the final state rather than
  the path taken.
* Naming an existing literal is done by visiting every call site of what carries it: sweep for the
  function's callers or the field's users, not for the literal, which misses positional arguments.
* Changing the value of a field visits every reader of it, in the code and in the field's doc, and
  asks what each does with the value: `class->name` is the type name a type error quotes and the
  key `lunatik_require` registers the library under, and renaming `rcu` to `rcu.table` for the
  first opened `luarcu` twice in every runtime through the second. A reader that merely compiles
  against the new value is not accounted for.
* A force-push that restructures a branch is not done until the pull request title and body are
  re-read against it. They describe the branch; a rewrite that drops or replaces a mechanism turns
  them into fiction the reviewer reads first.
* Do not commit directly to `master`.
* Copyright years: a new file carries the current year; a modified file extends its range to include
  it.

## Reviewing your own change

The conventions in this document are a checklist to run against your own diff before showing it, not
reference to reach for after a reviewer objects. Code shown without that pass makes the reader the
reviewer, and the deviations they then find — a prefix nothing else in the file uses, a comment on a
body the file leaves bare, a handle closed by hand where the file uses `<close>` — were already rules
here. The failure is not the missing rule; it is not running the ones that exist.

Before presenting a change to an existing file, read the file as the authority and measure the
addition against it — naming, comment density, idioms, resource handling, duplication — then prove
the behaviour on the operation in isolation, not a round trip that hides a partial result: `unload`
reaching zero, not `reload` returning to a full set. The pass covers the prose the change ships with,
too: after any rewrite or force-push, the commit message and the pull request body go through the
same review against the final code — a claim the code does not support, a mechanism the branch
dropped or a rationale its call sites contradict, is caught there, as *Patches and commits* requires.
Saying the prose matches is not the check; showing the claim-to-code mapping is. A change shown
without that pass is not done.

Before the hand-back, every function the diff touches is re-read whole, not by its changed lines:
a new branch is asked whether it is this function's job or its caller's, a condition with stack
juggling is asked whether it is a predicate helper, and a guard the new shape made redundant is
removed. The maintainer reading a function and finding it dirtier than before is the pass not run.

The hand-back lists each finding of your own review that the change does not apply, with the
reason. A finding dropped in silence is found again by the maintainer, who then doubts the whole
review; and "few sites" is not a reason against a rule that collapses a repeated pattern — three
class tests written by hand where the checker takes the classes were that.

## Before opening a pull request

1. `make` is clean, with no new warnings;
2. `sudo make install && sudo lunatik reload && sudo lunatik test` passes;
3. new API is documented and listed in `config.ld` and the README;
4. new tests are wired into their suite and described, and the hand-back carries the matrix the
   change is held to: for each guard or mechanism it adds, the operations by types by outcomes,
   each cell naming its test or saying why it is not covered. Wiring is what a check confirms; the
   matrix is what a rewrite inherits from the branch it replaces unless it is written down;
5. error paths audited: for each raise, everything already acquired is released;
6. commits are small, ordered, and none of them undoes another;
7. every helper the change introduces has a caller. A helper extracted to remove duplication but
   left unused, while the duplication it replaces still stands, is the refactor half-done. Grep the
   new symbols for a caller before sending.
8. the branch is handed back merge-ready, not as a working scratch: the session's commits grouped into
   a clean history that none of them undoes, nothing left to squash, the pull request title and body
   describing the final state. On a harness or docs pull request you author, tidy it before returning
   it, unasked — what comes back is reviewed and merged, not tidied first.
9. the simplification pass, before sending. For each helper, collection, or loop the change adds, name
   what it buys over the minimal shape — weighing the whole cost, not the line count at one call site.
   A loop that vanishes locally by generating a build-time list can add more surface than it removes
   (an extra argument, an emitted table, a file to keep in sync); prefer the ground truth the system
   already exposes — the kernel's own "Used by" list, a field already on the struct — over a structure
   invented to encode it, and keep a loop that is doing honest work. The same holds for a comment: one
   non-obvious reason, one line, at the site that needs it — not spread over two, not repeated wherever
   the feature is touched.

## Reviewing a pull request

A review produces two things: the comments, and a branch showing what the comments ask for. Neither
is posted before the maintainer has seen both, and the checklist below is the reviewer's own — a
review that fails it is not ready, whatever the code looks like.

The checklist runs whole on every pull request, whoever wrote it: the maintainer's own, another
session's, or this session's earlier work. Authorship shortens nothing. A change that arrives with
a rationale attached — a comment beside the line, a body that explains the choice, a prior session
that "already reviewed it" — is reviewed against the code, not against the rationale: a comment
beside `raw_cpu_ptr` about a preemptible caller that does not exist is a finding to run to ground
against the kernel's own idiom, not a reason to pass the line. Reading the rationale as the review
is how a mutex in softirq and a crash reachable from Lua were passed.

### Before the verdict

1. Check out the author's branch, build it, and run the suite. Reading the diff misses what the
   machine already knows. A change with no test of its own — an example, a script — is run directly,
   not merely built: an entry point that never fires hides a runtime crash behind a green build, and
   an approval says it ran. If it does not run, that is a hypothesis to trace, not a finding: separate
   the artifact under test from the tool exercising it — the same program the distribution's loader
   rejects may load under a current one — and exhaust the working path before writing "could not run".
   A reviewer with the machine drives it to ground rather than asking the author to confirm what the
   machine could have said. The base to diff against is `origin/master`, not the local `master`, which
   may have drifted; `git rev-list --count origin/master..master` says whether it did.
2. List every file the pull request touches (`gh pr view <n> --json files`) and read from that list.
   The patch spans the repo, not the feature's folder, so a claim that the PR contains or lacks a file
   is grounded in that changeset, never in a directory listing scoped to where you assumed it would
   live — "no README in the PR", from an `ls` of the example directory while the PR edited the
   repo-root `README.md`, is the shape of that error.
3. Read the PR's own conversation, not only its diff. An author's comment may raise a question or
   propose an alternative the review has to engage; a verdict that ignores an open author thread is
   incomplete.
4. A PR based on another branch rather than `master` is stacked: review it against its own base, and
   read the whole stack first, because what one PR seems to delete may have moved to a PR stacked on
   top of it — check there before reporting a deletion as a loss.
5. Work on `review/<pr number>`, started from the author's head. The number is what lets the author,
   and the next reviewer, find the branch; a name of your own choosing does not.

### Findings

* A finding is worded softly even when its trace is hard. A prescriptive "should" lands as a ruling
  on the author's work: say what the code does, what impression the name or contract gives, and
  offer the fix conditioned on the intent. The trace can be categorical; the phrasing is not.
* A finding names its severity from what is traced, not from what is feared. A crash is a crash only
  when a reachable path reaches it; short of that it is a contract or parity gap, said as one. A cost
  claim — "overhead", "slow", "expensive" — is a measurement, not an adjective: unmeasured, what you
  have is a duplication or an extra call, named as that, not as a hot path. When a number would decide
  the point and is not in hand, say it was not measured.
* A symptom seen while poking by hand is not a finding until a clean run reproduces it. Reload to a
  fresh slate, run once, apply one stimulus, read the result — that is authoritative; a scratch
  fighting leftover state is not. An absence of errors counts only if you exercised the path that
  raises them: zero because the code never ran is not zero because it ran clean. A "serious bug"
  escalated from stale-environment noise and nearly filed against someone's PR is the failure this
  guards against. Non-determinism is the tell: a symptom that shows on one run and not the next, from
  the same inputs, is environment state, not a code path — the variable is the leftover, so control it
  (a fresh reload, a pinned CPU, the program cut down to the one call under test) rather than theorise
  a bug. The minimal isolating reproduction settles in one run what reading the noisy end-to-end path
  never does. When the variable is a stimulus the host may or may not supply — a stray packet in a
  window — supply it yourself and reproduce the signature on demand, and log what the hook actually
  saw before naming the packet. A mechanism proved by injection is reported as that, not as the
  trigger of the run that failed, which was not captured.
* A finding is resolved, not parked. When something looks wrong, run it to ground — reproduce it, find
  the cause, then fix it or dismiss it. "I'll flag it to the author", "let's look into it separately",
  or asking whether to investigate is dropping it, not handling it. Deferral is for work that belongs
  in another pull request, captured as an issue linked from the comment that defers it — not for the
  hard half of the finding in hand.
* Cover the whole change, and flag across all of it — the author's code and your own fixups alike.
  "It is the author's code" or "my line, not the feature" is never a reason to pass over a defect;
  what is scoped is the fixup, which touches only what a finding requires, not the finding. A review
  that reads the one file it expected the bug in and skips the rest is half a review, and the half it
  skipped is where the reader assumes it looked.
* A review holds new code to the conventions this file records; it does not impose preferences beyond
  them. Where the tree itself is inconsistent and a style seems worth settling, that is an exclusive
  pull request that fixes the whole tree and records the convention here — never a finding on someone's
  feature work. A name that deliberately mirrors a kernel symbol keeps its spelling: `TC_H_MAKE` ported
  from the kernel macro stays upper-case though Lua functions are lower-case, because the recognition
  is the point. Check what a name mirrors, and read the author's stated reason, before calling it a
  violation.
* A new module is read for its shape, not only its logic. How a module of its kind returns, names its
  handle field, constructs, and documents is measured against the nearest existing sibling —
  `socket.inet` for a wrapper, `bpf.map`'s `view` for a proxy — and correct code in a shape the tree
  does not use is a finding. That a form conforms is found in the tree by grepping for the peer that
  uses it, not felt.
* The base can be the outdated one. When new code diverges from it, check which side is right before
  aligning — pulling the new code down to match a sibling that is itself behind is the wrong fix.
  `tc`'s BPF programs were right to declare `Dual MIT/GPL`; the `xdp` ones still on `GPL` are what a
  separate cleanup fixes.
* Missing tests are a finding of their own, written as such, not a remark appended to another comment.
  The review writes the matrix the change is held to and reads the tests against it; a test set
  taken as given because it came with the branch is the review not done.
* A contract the author documented is not redesigned by the review. An ergonomics preference, `nil`
  against an object whose methods raise, is stated with its trade-off and left to the maintainer;
  shipped as a fixup, it asks the author to un-decide.

### Fixups

* A code finding ships as the fixup that makes it, not as a paragraph in the imperative — "use
  `set.labeled`", "name these offsets", "please follow that" hands the author work you could have done
  and shown, and is the review half-done. The prose points at the fixup and says why; the fixup is the
  change. A code finding with no commit behind it is not ready to post, and a review posted as comments
  with no branch is the lazy half of the two the review owes.
* One fixup per finding, `git commit --fixup=<the author's commit>` — not one per file, and not one
  per target commit: a comment pointing at a commit that does three unrelated things cannot be accepted
  in parts, and the author is the one who autosquashes what they accept. A fixup touches only what the
  pull request introduced; check the symbol's provenance first, since one already on `master` is a
  separate change on its own branch, and a design note under `doc/design/` that mentions the old
  shape is a snapshot of a plan, not the API's documentation, and stays out. A fixup is the
  reviewer's code with no reviewer, so it gets the pass the author's code got. A consistency fix on
  the branch's own code is done now, not deferred.
* A script or command handed to the author is one you ran, not one you syntax-checked or copied from a
  doc. `bash -n` passing is not the script working, and "it is the README's own command" is not "it
  runs here". If the environment cannot verify it — a stale module, a skewed signature in the way —
  the verdict is "unverified", said plainly, not "it works".
* Rebase the review branch when `master` moves under it, so the fixups still apply to what the author
  will rebase onto. A linked fixup's SHA is a published reference the moment the comment posts;
  amending or rebasing after that leaves the link pointing at the superseded version, so leave the
  branch be once posted, and when a change is unavoidable, refresh the SHAs in the comments it moved.

### Comments and the verdict

* Draft the comments and hand them over. The repository's public voice is the maintainer's; a reviewer
  writes, the maintainer posts. Do not comment on a pull request or an issue unless asked, and having
  offered earlier is not authorization. Being told to post is not a license to post words the
  maintainer has not read: show the exact text, get the go-ahead on it, then post — the approval is of
  the wording, and "post it" or "where is it?" asks for the draft, not for it to already be public.
* A code finding is posted inline, anchored on the line it addresses; the review body carries the
  verdict and opens addressing the author by handle. A finding in the body, away from its line,
  makes the reader hunt for where it applies — and a submitted review cannot be deleted, only
  dismissed, so the placement is decided before posting, not repaired after.
* Each comment links its fixup as a full commit URL — never a backtick'd SHA, which renders as code and
  does not link. A reply to an author's comment @-mentions the author and opens with a quote of the
  line it answers: an issue comment does not thread and need not even notify them, so the @-mention
  reaches them and the quote makes it a reply, not a stray remark. A request for changes is not a place
  for praise; padding buries the change being asked for.
* Write a finding plainly and no longer than it needs to be: the defect, the fix, and the trace,
  without metaphor, restatement, or throat-clearing. Padding buries the finding the way praise does.
* A claim that rests on source outside the diff — a kernel accessor, a sibling module, a spec — links
  that source the way a fixup is linked: a stable, line-anchored URL at a pinned ref, a commit or tag
  blob, never a moving `master` link that drifts off the line. The reference is the evidence; a finding
  that names an accessor or a pattern without a link asks to be trusted, not checked.
* The verdict states whether the pull request can merge as it stands: a finding that must be folded is
  a request for changes, however small; a comment review is for observations that do not gate. Once it
  is clean, the verdict is an Approve, not a comment — a comment saying it looks good leaves an earlier
  request-for-changes standing and the gate closed. Say it plainly and flip the state.
* A further request-for-changes, when the PR already carries your changes-requested, does not surface:
  GitHub stores it and the API shows it, but the conversation gains no new item because the gate did
  not move — so it "posted" by every check you can run and is still invisible. When the gate is already
  closed and there is more to say, comment. And feedback lives in one artifact: when you fall back to a
  comment, or correct or move a comment, edit or supersede the one that carries it — never leave two
  copies to drift.
* A stacked pull request is merged after its base, never before: GitHub merges it into the base
  branch, the base pull request grows a commit nobody reviewed there, and the stacked one closes
  as merged with nothing on `master`. A verdict on a stacked pull request says "after #N".
* Approving is the reviewer's to state; merging is the maintainer's to trigger. Even a clean, approved
  PR is not merged on the reviewer's initiative — pushing or merging to `master` is irreversible and
  public, and the click is the maintainer's alone. A question about state — "can we merge?", "is it
  ready?", "what's the status?" — asks for the readiness, the way "where is it?" asks for a draft, not
  for the merge. Wait for the imperative, "merge it"; report the state and stop.

### After a round

* Re-read your own review before it goes out, against the exact branch: the overstated severity, the
  file left unopened, the fixup whose comment drifted from what it does. The self-audit the code gets
  is owed to the review too.
* A re-review re-fetches the author's branch and reads what changed there — not the review branch you
  built last round. Diff the author's new head against what you last saw: re-reading your own fixups
  reviews your work, not theirs, and misses what they folded wrong, spelled differently, or left out.
  Confirming that prior findings were folded and the build is green is where a re-review starts, not
  where it ends.

