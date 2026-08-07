# Working on Lunatik

Conventions for contributors, and for AI coding assistants working on this repository. If you are
using an assistant that reads a project file automatically (`AGENTS.md`, `CLAUDE.md`, `.cursorrules`),
point it here.

Lunatik runs Lua inside the Linux kernel. A mistake here does not raise an exception, it panics a
machine. Two rules follow from that and outrank everything else in this document:

1. **Verify, do not assume.** Before using a kernel API, read its declaration in
   `/usr/src/linux-headers-$(uname -r)/include` and confirm it is exported in `Module.symvers`.
   Signatures change between releases. If you have not checked, say so instead of asserting.
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
| `docs/design/` | design notes for work in progress: gap analysis, proposed APIs, verified kernel references, test strategy |
| `doc/` | generated LDoc output, plus the hand written C API reference |

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
before the next `reload`.

Never run two `lunatik` operations at once. Concurrent operations wedge `/dev/lunatik` and leave
processes in D state. Check with `ps` before starting one.

Trust the formal test over manual poking. Iterating by hand — `lunatik run`/`stop`, `iw`, `ip`,
`rmmod`, `modprobe` — leaves stale state that wedges the next run: an interface in the wrong mode, an
orphan `.ko` still pinning the core, a script still registered. A test's `.sh` does its own setup and
teardown; a green formal test is the authoritative result, not a red manual scratch fighting leftover
state.

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
* Kernel headers first, then a blank line, then `#include <lunatik.h>`. Do not remove that blank line.
* `<lua.h>` and `<lauxlib.h>` are already pulled in by `lunatik.h`.
* Every file ends with a trailing blank line. A pre commit hook rejects files that do not.
* Lunatik has no floats. Do not check `lua_isinteger`.
* Multi line macros use the `do { ... } while (0)` form.
* Do not duplicate a struct defined by another module; use its exported API.
* Prefer a named `static inline` helper over an open coded repetition, and do not inline an existing
  named helper into its callers while refactoring; they exist for readability and symmetry.
* When a two line pattern repeats in every method, collapse it into one helper or macro.
* `/*** @section name */` separates logical sections in a merged C file and groups them in the docs.
* Two short mutually exclusive calls read better as a ternary than a four line if/else; void arms are
  fine. This does not transpose to Lua (see Lua style).
* Function pointers get a named typedef: `lua<libname>_<role>_t`.
* For every raise after acquiring a resource, know what is already held and who releases it; validate
  before acquiring whenever the check does not need the resource.

## Lua style

* Line length 120.
* Localize stdlib functions at the top of a new module: `local insert = table.insert`.
* `require("x")` with parentheses.
* Use `table.insert`, not `t[#t+1] = v`.
* No nested function definitions; helpers go at module level.
* Hooks and callbacks are named `local function`s referenced by name, never anonymous functions inline
  in a table field.
* Named constants at the top: `local PORT <const> = 5562`. No magic numbers.
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

Inside a CLI dostring, require once at startup and call by name afterwards:

    lunatik.foo = require("lunatik.foo")
    lunatik.foo.method(...)

Never `require("foo").method()`.

## Comments and documentation

* Comments describe the present, not the history. No "was", "no longer", "used to".
* No comments restating obvious kernel or Lua API usage. Non obvious rationale is welcome.
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
  above it.

## Tests

Tests are shell scripts emitting KTAP plus a kernel side Lua script.

* the description of what a test does goes in the `.sh`. The `.lua` gets one line pointing back at it;
* skip, do not fail, when the kernel lacks a required config;
* mark `dmesg` before the run, read only what came after, and `check_dmesg` at the end;
* clean up in a `trap`, and run the cleanup once up front as well;
* coverage means the matrix of operation by type by outcome, including the successes, not a list of
  features and not only the error paths.

A test is not done until `tests/README.md` describes it, the suite's `run.sh` runs it, and, for a new
suite, the top level `README.md` lists it. Same commit, or a fixup of it.

## Patches and commits

* Small, auditable, incremental commits. Each one stands alone and adds value.
* Change only what the task requires. Do not reformat untouched lines, do not move code, do not
  rename variables in passing. Compare `git diff` against `git diff -w` before committing to catch
  stray whitespace.
* No cosmetic changes inside a feature or fix commit, not even a blank line.
* Never remove an existing comment unless the change made it factually wrong.
* Restoring something that was removed puts it back exactly where and how it was.
* Subject line says what changed and why, not how. A body only when there is something the diff does
  not say: a new API, a behaviour change, a non obvious rationale. No bullet list of every detail.
* Corrections to a commit on your own branch are `git commit --fixup=<hash>`, not a standalone
  "address review comments" commit. Never fixup a commit that is already on `master`; that becomes a
  new commit on a new branch.
* If a branch adds something in one commit and removes it in another, the second is a fixup of the
  first.
* After squashing, re read the comments and commit bodies so they describe the final state rather than
  the path taken.
* Do not commit directly to `master`.
* Copyright years: a new file carries the current year; a modified file extends its range to include
  it.

## Before opening a pull request

1. `make` is clean, with no new warnings;
2. `sudo make install && sudo lunatik reload && sudo lunatik test` passes;
3. new API is documented and listed in `config.ld` and the README;
4. new tests are wired into their suite and described;
5. error paths audited: for each raise, everything already acquired is released;
6. commits are small, ordered, and none of them undoes another.

