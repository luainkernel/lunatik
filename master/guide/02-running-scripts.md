# Running scripts

## The lunatik command

```Shell
usage: lunatik [-h | -V]
       lunatik [-i] [-e <chunk>]
       lunatik load | unload | reload | status
       lunatik run [-c process | softirq | hardirq] [-p] <script>
       lunatik spawn <script>
       lunatik stop <script>...
       lunatik list
       lunatik test [<suite>]
       lunatik compile [<lunatic argument>...]
```

* `-h`, `--help`: print the usage
* `-V`, `--version`: print the version of the loaded Lunatik, or fail when it is not loaded
* `-e <chunk>`, `--eval=<chunk>`: run the chunk in the kernel and print what it returns, as
  `sudo lunatik -e 'return _VERSION'` does; unlike a REPL line, an expression needs its `return`
* `-i`, `--interactive`: enter the REPL after `-e`
* `-c <context>`, `--context=<context>`: the context `run` creates the runtime in
* `-p`, `--percpu`: `run` creates one runtime per CPU id

* <code>load</code>: load Lunatik kernel modules; one that fails to load does not fail the command:
  `modprobe` prints its error on stderr and the load goes on, so read `lunatik status` and the kernel log
* `unload`: stop every running script, then unload Lunatik kernel modules
* `reload`: stop every running script and reload Lunatik kernel modules, failing with
  `couldn't replace <modules>: loaded from another build` when a module that could not be unloaded
  is not the installed file
* `status`: show which Lunatik kernel modules are currently loaded, and name a loaded module that
  is not the installed build
* `test [suite]`: run installed test suites (see [Development](06-development.md))
* `compile <arguments>`: run `lunatic` with the given arguments (see [lunatic](#lunatic))
* `list`: show which runtime environments are currently running, one script a line, in order of name
* `run [-c softirq | hardirq] [-p] <script>`: create a new runtime environment to run the script `/lib/modules/lua/<script>.lua`; pass `--context=softirq` for hooks that fire in softirq context (netfilter, XDP), or `--context=hardirq` for hooks that can fire inside an interrupt handler or with interrupts off (kprobes); optionally pass `--percpu` to create one runtime per CPU id, dispatched to the runtime of the CPU the callback runs on. The script runs once per runtime and can read its id with `lunatik.cpu()`; the runtimes share a netfilter hook and a kprobe, and constructors whose registration is global fail at load in a percpu runtime. A runtime is a CPU, not a connection: see [Per-CPU scripts](03-percpu.md)
* `spawn <script>`: create a new runtime environment for the script `/lib/modules/lua/<script>.lua`,
  always in process context, and run the function it returns in a kernel thread; it takes no
  context and no percpu, and the function follows the rules of *Kernel threads* below
* `stop <script>...`: stop the runtime environment created to run each script, failing on a script nothing runs
* no command, `sudo lunatik`: start a _REPL (Read–Eval–Print Loop)_, with its banner and prompts on
  a terminal; on a pipe it runs each line it reads and prints only what the lines return. Each
  entry is a chunk of its own, so a `local` is gone on the next line while a global stays; an entry
  that is not complete yet continues on the next line. Every invocation of the CLI, `-e` included,
  runs its chunks in one process-context runtime, so a hook that needs softirq or hardirq is
  registered from a script started with `lunatik run --context=<context>`

An operation the kernel refuses exits 1 with `lunatik: <message>` on stderr and nothing on stdout,
and a wrong invocation exits 2 with the usage on stderr.

The CLI reaches the kernel through `/dev/lunatik`, whose protocol is internal to it: a tool drives
Lunatik through the `lunatik` command, not through the device. A driver whose reply carries no
status, as the one a release before 5.0 loads, fails every command that reaches it with
`lunatik: couldn't read /dev/lunatik: loaded from another build`; unload that release with its own
CLI before installing another over it, or reboot.

## Execution contexts

A runtime is created in one of three contexts, and this decides what its code may do:

| Context | How | Allocation | Lock | May sleep |
|---------|-----|-----------|------|-----------|
| process | default, and always for `spawn` | `GFP_KERNEL` | mutex | yes |
| softirq | `lunatik run --context=softirq <script>` | `GFP_ATOMIC` | `spin_lock_bh`; `spin_lock_irqsave` with IRQs already off | no |
| hardirq | `lunatik run --context=hardirq <script>` | `GFP_ATOMIC` | `spin_lock_irqsave`, always | no |

A binding that registers a hook checks that the runtime registering it has the context the hook
fires in, and raises `runtime context mismatch: <class> needs <context>` from a runtime of another
context. A class whose objects may sleep is a process-context class, and creating one of its
objects from a softirq or hardirq runtime raises `'<class>': process-context class in
interrupt-context runtime`. A method of a shared object whose lock is a spinlock, a softirq or
hardirq one, runs under that lock, and the runtime that calls it allocates with `GFP_ATOMIC` until
it returns, a process runtime included.

The script body itself runs once, in process context, before the runtime is armed, so registering
hooks at its top level may sleep. Everything that runs later, from a hook, may not. A runtime is
armed once its script body returns; from then on, in a softirq or hardirq runtime, a call that
sleeps, such as creating or stopping a kprobe, raises `not allowed once the runtime is armed`.

## Kernel threads

A script for `spawn` returns the thread body. The body polls `thread.shouldstop()` and yields, and
bounds every call that blocks with a timeout: `lunatik stop` waits for the body to return, and a body
that never returns keeps it waiting. An error the body raises goes to the kernel log.

```Lua
local thread = require("thread")
local linux  = require("linux")

return function()
	while not thread.shouldstop() do
		-- non blocking work only
		linux.schedule(100)
	end
end
```

## lunatic

```Shell
usage: lunatic [options] [filenames]
```

`lunatic` is `luac` built with the host compiler from the same `lua/` sources and configuration
as `lunatik.ko`, so its chunks match the kernel's opcode set and integer-only number format;
chunks from the distribution `luac` are rejected by the kernel. The options are `luac`'s
(`-l` list, <code>-o</code> output, `-p` parse only, `-s` strip debug information, `-v` version) plus
`-e big|little`, the byte order of the target when it is not the host's, and `lunatik compile` runs
it with the same arguments.

A chunk is installed and run under the usual `.lua` name; the kernel detects it by its signature.
Several inputs make one chunk that runs them in order, as with `luac`, so compile one file per
call. `-s` drops the source name and the line numbers, so a stripped chunk reports an error as
`?:?: ...`; keep the full chunk while developing:

```Shell
lunatik compile -o hello.luac hello.lua
sudo install -m 0644 hello.luac /lib/modules/lua/hello.lua
sudo lunatik run hello
```

`sudo make install BYTECODE=1`, after `make`, installs the kernel Lua libraries and the examples as stripped chunks
instead of source, so an error raised from one of them reads `?:?:`.


