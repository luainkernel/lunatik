# Running scripts

## The lunatik command

```Shell
usage: lunatik [-h | -V]
       lunatik [-i] [-e <chunk>]
       lunatik load | unload | reload | status
       lunatik run [-c process | softirq | hardirq] [-p] [--dev=<ifname>] <script>
       lunatik spawn <script>
       lunatik stop <script>...
       lunatik list
       lunatik test [<suite>]
       lunatik compile [<lunatic argument>...]
       lunatik bpf [--btf=<file>] [-o <object>] <program>
```

* `-h`, `--help`: print the usage
* `-V`, `--version`: print the version of the loaded Lunatik, or fail when it is not loaded
* `-e <chunk>`, `--eval=<chunk>`: run the chunk in the kernel and print what it returns, as
  `sudo lunatik -e 'return _VERSION'` does; unlike a REPL line, an expression needs its `return`
* `-i`, `--interactive`: enter the REPL after `-e`
* `-c <context>`, `--context=<context>`: the context `run` creates the runtime in
* `-p`, `--percpu`: `run` creates one runtime per CPU id
* `--dev=<ifname>`: the device `run` attaches the script's compiled program to (see
  [Compiled programs](#compiled-programs))
* `-o <object>`, `--output=<object>`: the object `bpf` writes
* `--btf=<file>`: the kernel BTF `bpf` reads the types of, `/sys/kernel/btf/vmlinux` by default
  (see [Program files](#program-files))

* <code>load</code>: load Lunatik kernel modules; one that fails to load does not fail the command:
  `modprobe` prints its error on stderr and the load goes on, so read `lunatik status` and the kernel log
* `unload`: take down every compiled program a `run` attached, stop every running script, then
  unload Lunatik kernel modules
* `reload`: take down every compiled program, stop every running script and reload Lunatik kernel
  modules, failing with
  `couldn't replace <modules>: loaded from another build` when a module that could not be unloaded
  is not the installed file
* `status`: show which Lunatik kernel modules are currently loaded, and name a loaded module that
  is not the installed build
* `test [suite]`: run installed test suites (see [Development](06-development.md))
* `compile <arguments>`: run `lunatic` with the given arguments (see [lunatic](#lunatic))
* `bpf [--btf=<file>] [-o <object>] <program>`: compile a program file into a BPF object (see
  [Program files](#program-files))
* `list`: show which runtime environments are currently running, one script a line, in order of name
* `run [-c softirq | hardirq] [-p] [--dev=<ifname>] <script>`: create a new runtime environment to run the script `/lib/modules/lua/<script>.lua`; pass `--context=softirq` for hooks that fire in softirq context (netfilter, XDP), or `--context=hardirq` for hooks that can fire inside an interrupt handler or with interrupts off (kprobes); optionally pass `--percpu` to create one runtime per CPU id, dispatched to the runtime of the CPU the callback runs on. The script runs once per runtime and can read its id with `lunatik.cpu()`; the runtimes share a netfilter hook and a kprobe, and constructors whose registration is global fail at load in a percpu runtime. A runtime is a CPU, not a connection: see [Per-CPU scripts](03-percpu.md). Where `/lib/modules/lua/<script>.bpf.o` exists, `run` also loads and attaches that program: see [Compiled programs](#compiled-programs)
* `spawn <script>`: create a new runtime environment for the script `/lib/modules/lua/<script>.lua`,
  always in process context, and run the function it returns in a kernel thread; it takes no
  context and no percpu, and the function follows the rules of *Kernel threads* below
* `stop <script>...`: stop the runtime environment created to run each script and take down the
  compiled program its run attached, failing on a script nothing runs
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
instead of source, so an error raised from one of them reads `?:?:`. `class` stays source, since the CLI's Lua reads
it too.

## Program files

Program files and their compiler are experimental: what this section and the next describe may
change in a minor release, as [Compiling Lua to eBPF](08-luaebpf.md) says.

`lunatik bpf` compiles a **program file** into a BPF ELF object, `<program>` with `.lua` replaced
by `.o` unless `-o` names another, so `filter.bpf.lua` becomes `filter.bpf.o`. `lunatic` compiles
the file, and its body is compile-time Lua: it runs once, here, from that bytecode in the CLI's Lua,
so it computes as the kernel would, and hands the functions it declares to a program constructor.
Those functions are the program: their bytecode is compiled to eBPF and held to the subset the
verifier can check. Anything outside it is an error naming the Lua file and line, and no object is
written.

```Shell
lunatik bpf filter.bpf.lua
```

A program that [calls a kernel Lua runtime](08-luaebpf.md#calls-into-a-kernel-lua-runtime), named
by `bpf.xdp.runtime` or `bpf.tc.runtime`, runs the interpreter on the packet path at each call, so
`lunatik bpf` prints on stdout a line per call it compiled,
`<file>:<line>: calls the runtime '<name>'`, and nothing for a file with none.

`lunatik run` is what loads and attaches the object: see [Compiled programs](#compiled-programs).

The object is compiled for the kernel `lunatik.config` describes, which `make` writes from the tree
it builds the modules against: that kernel's version and whether it reads a word at any address
decide what a program may emit, and its byte order is the object's. The types a program reads, its
context's struct and any layout `luaebpf.vmlinux` answers, come from that kernel's BTF:
`/sys/kernel/btf/vmlinux` unless `--btf` names a raw BTF file, the bytes that path serves.

A build host compiles for the kernel an image ships in three steps:

1. it builds Lunatik against that kernel's tree, so `make` writes that kernel's
   `autogen/lunatik/config.lua`;
2. it dumps the `.BTF` section of the image's `vmlinux` with an `objcopy` that reads the image's
   architecture, the first command below;
3. it compiles with that `autogen/lunatik/config.lua` ahead of the one `make install` links into its
   Lua path, and with that BTF, the second command.

```Shell
objcopy --dump-section .BTF=vmlinux.btf vmlinux /dev/null
LUA_PATH="$PWD/autogen/?.lua;;" lunatik bpf --btf=vmlinux.btf filter.bpf.lua
```

The image then only loads the object.

A BTF of the other byte order than the object's is refused, naming both, since it describes another
kernel: the build host's own, read by default, in a compile for a kernel of the other order. A kernel
script the body requires is still read from the build host's `/lib/modules/lua/`, so its `linux.*`
tables are the ones last installed there.

`require` in the body finds the compile-time modules first, `bpf.xdp`, `bpf.tc` and `bpf.map`,
which declares a map rather than opening the kernel's, then the compiler's own `luaebpf` modules,
then `/lib/modules/lua/`, whose modules `lunatic` compiles as it does the program file, installed
as source or, with `BYTECODE=1`, as chunks. It finds nothing else the CLI's Lua would, so a Lua or
C module the host installs never stands in for a kernel script. `10 / 4` is `2` in the body as in
the kernel; the CLI's libraries can still return a float, as `math.sqrt` does, and one reaching a
compiled function is refused at the line that reaches it.

## Compiled programs

When `/lib/modules/lua/<script>.bpf.o` exists, the object compiled from `<script>.bpf.lua`,
`lunatik run --dev=<ifname> <script>`:

1. takes down what a previous run of the script left under `/sys/fs/bpf/lunatik/<script>/`, then
   creates the maps the program file declares and pins each there under its name;
2. starts the runtime for `<script>.lua`, when there is one, whose script opens those maps by that
   path;
3. attaches every program the object declares to `<ifname>`, an XDP program to the device and a TC
   one to its tcx ingress or egress, and pins each link at
   `/sys/fs/bpf/lunatik/<script>/<program>-link`, which keeps the program attached once the command
   has exited. bpffs refuses a dot in a name, so the suffix takes a hyphen, which no map name
   carries.

```
  sudo lunatik run --dev=eth0 filter

  /lib/modules/lua/filter.bpf.o            /lib/modules/lua/filter.lua
             |                             the kernel script, if any
             | 1. open the object                       |
             | 2. remove what a previous run pinned     |
             | 3. load: create and pin each map, then   |
             |    the verifier checks each program; if  |
             |    it refuses one, its log, quoting the  |
             |    Lua line, and exit 1                  |
             v                                          |
  /sys/fs/bpf/lunatik/filter/counts                     |
             ^                                          | 4. the runtime
             |   bpf.map opens it by that path          |    starts; its
             +------------------------------------------+    body runs
             |
             | 5. attach each program to eth0, an XDP program to the
             |    device, a TC one to its tcx ingress or egress, and pin
             |    its link at /sys/fs/bpf/lunatik/filter/<program>-link
             v
  the command exits; the pinned link keeps the program on eth0

  a step that fails undoes the steps before it, and the command exits 1

  sudo lunatik stop filter
     detaches each link, stops the runtime, removes the pins
```

The maps exist before the script opens them, and the programs attach once the runtime is up. A
failure at any step undoes the steps before it and exits 1 with that step's message, the verifier's
own log when the kernel rejects a program, which quotes the Lua line; libbpf's own warnings, which
name what failed where the kernel logs nothing, print on stderr before it. Once attached, a program
logs nothing: a packet it cannot compute gets its default verdict, as
[What a program returns](08-luaebpf.md#what-a-program-returns) says. `lunatik stop <script>`
runs it backwards: it detaches each link, stops the runtime and removes the pins, the root and each
directory above it the root leaves empty. A root holds pins and nothing else, so a stop of a name
that only parents other scripts' roots leaves them alone. `lunatik unload`, and `reload` and `test`
with it, detaches every link under `/sys/fs/bpf/lunatik/` and removes the tree before it stops the
runtimes, so no program outlives it, not even one with no runtime to stop.

A run of a script that is already running is refused before anything is touched. A script with an
object and no `<script>.lua` runs the program alone, with no runtime: it takes no `--context` and no
`--percpu`, and with no runtime to refuse it, a second run redeploys it. `--dev` is required where
there is an object and refused where there is none, both exiting 2 with the usage. A name with a
dot has no root, since bpffs refuses the dot, and neither has one with an empty component, a leading
or a doubled `/`, which would spell the root of a run registered under the other spelling: its run
is refused, and its stop reaches no root. A TC program needs a libbpf
of 1.3.0 or later, where tcx begins; below it `run` refuses with `tcx needs libbpf 1.3.0`.

```Shell
sudo lunatik bpf -o /lib/modules/lua/filter.bpf.o filter.bpf.lua
sudo lunatik run --dev=eth0 filter
sudo lunatik stop filter
```

`sudo make install` compiles every program file of `examples/` and `tests/`, but the `luaebpf`
suite's, whose cases compile their own, and puts the object beside the script it belongs to, where
the kernel publishes the BTF the compiler reads. The program file itself stays out of
`/lib/modules/lua/`: its body runs on the host, and the kernel's `require` never loads it.

