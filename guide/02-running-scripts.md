# Running scripts

## The lunatik command

```Shell
usage: lunatik [-h | -V]
       lunatik [-i] [-e <chunk>]
       lunatik load | unload | reload | status
       lunatik run <script> [process | softirq | hardirq] [percpu]
       lunatik spawn | stop <script>
       lunatik list
       lunatik test [<suite>]
       lunatik compile [<lunatic argument>...]
```

* `-h`, `--help`: print the usage
* `-V`, `--version`: print the version of the loaded Lunatik, or fail when it is not loaded
* `-e <chunk>`, `--eval=<chunk>`: run the chunk in the kernel and print what it returns
* `-i`, `--interactive`: enter the REPL after `-e`

* `load`: load Lunatik kernel modules
* `unload`: unload Lunatik kernel modules
* `reload`: reload Lunatik kernel modules
* `status`: show which Lunatik kernel modules are currently loaded
* `test [suite]`: run installed test suites (see [Development](06-development.md))
* `compile <arguments>`: run `lunatic` with the given arguments (see [lunatic](#lunatic))
* `list`: show which runtime environments are currently running
* `run [process|softirq|hardirq] [percpu]`: create a new runtime environment to run the script `/lib/modules/lua/<script>.lua`, in process context by default; pass `softirq` for hooks that fire in softirq context (netfilter, XDP), or `hardirq` for hooks that fire in hardirq context (kprobes); optionally pass `percpu` to create one runtime per CPU id, dispatched to the runtime of the CPU the callback runs on. The script runs once per runtime and can read its id with `lunatik.cpu()`; the runtimes share a netfilter hook and a kprobe, and constructors whose registration is global fail at load in a percpu runtime. A runtime is a CPU, not a connection: see [Per-CPU scripts](03-percpu.md)
* `spawn`: create a new runtime environment and spawn a thread to run the script `/lib/modules/lua/<script>.lua`
* `stop`: stop the runtime environment created to run the script `<script>`
* `default`: start a _REPL (Read–Eval–Print Loop)_, with its banner and prompts on a terminal; on a
  pipe it runs each line it reads and prints only what the lines return

An operation the kernel refuses exits 1 with `lunatik: <message>` on stderr and nothing on stdout,
and a wrong invocation exits 2 with the usage on stderr.

## Execution contexts

A runtime is created in one of three contexts, and this decides what its code may do:

| Context | How | Allocation | Lock | May sleep |
|---------|-----|-----------|------|-----------|
| process | default, and always for `spawn` | `GFP_KERNEL` | mutex | yes |
| softirq | `lunatik run <script> softirq` | `GFP_ATOMIC` | `spin_lock_bh`; `spin_lock_irqsave` with IRQs already off | no |
| hardirq | `lunatik run <script> hardirq` | `GFP_ATOMIC` | `spin_lock_irqsave`, always | no |

Netfilter and XDP hooks fire in softirq, kprobes in hardirq; those scripts need the matching context.
The script body itself runs once, in process context, before the runtime is armed, so registering
hooks at its top level may sleep. Everything that runs later, from a hook, may not.

## lunatic

```Shell
usage: lunatic [options] [filenames]
```

`lunatic` is `luac` built with the host compiler from the same `lua/` sources and configuration
as `lunatik.ko`, so its chunks match the kernel's opcode set and integer-only number format;
chunks from the distribution `luac` are rejected by the kernel. The options are `luac`'s
(`-l` list, `-o` output, `-p` parse only, `-s` strip debug information, `-v` version) plus
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

`BYTECODE=1 make install` installs the kernel Lua libraries and the examples as stripped chunks
instead of source, so an error raised from one of them reads `?:?:`.


