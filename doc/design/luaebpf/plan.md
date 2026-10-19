# Plan: Lua as a source language for eBPF

Execution plan for `luaebpf`: a compiler from a Lua subset to eBPF, a loader in the `lunatik`
CLI, and the tests that hold them to the verifier.

## Expected results

1. A Lua function becomes an eBPF program: the verifier checks it, the JIT runs it, and no
   interpreter runs per packet. The XDP and TC programs the tree ships as C stubs today can be
   written in Lua, including the SNI filter in `examples/filter`, whole.
2. `lunatik run <script>` loads, attaches and pins the compiled programs that belong to a script
   and `lunatik stop <script>` undoes it. No `clang`, no `bpftool prog load`, no `tc filter add`
   on the user's side; no `.bpf.c` beside the `.lua`.
3. A compile error names the Lua line, and a verifier rejection names the Lua line too, because
   the object carries `line_info` pointing at the source.
4. A compiled program calls the kernel Lua runtime through the existing kfunc where the program
   says so, with the arguments marshalled by the compiler and read by the callback as they are
   today (`ctx:argument()`).
5. A compiled program reads and writes eBPF maps the kernel Lua script also reads and writes,
   through the same `bpf.map` specs, with the maps created and pinned by the loader.
6. Programs that the trampoline cannot host by construction, sleepable LSM and tracing programs
   among them, are reachable from Lua.
7. A test suite that proves what the compiler emits against what the verifier accepts and against
   what the interpreter computes, and skips cleanly where the kernel or the toolchain lacks a
   feature.

## Where we are today

The eBPF surface of the tree at `22c5afe2` is a trampoline. Read it before changing it:

* `tests/xdp/xdp_pass.bpf.c` is the whole eBPF side of an XDP case: twelve lines that call
  `bpf_luaxdp_run` with a runtime name and a four-byte argument and return the verdict. Thirteen
  such stubs exist (`tests/xdp/*.bpf.c`, `tests/tc/*.bpf.c`, `examples/filter/https.c`,
  `examples/sniclassify/classify.c`), each with a Makefile that runs `clang -target bpf` against a
  `vmlinux.h` dumped by `bpftool`, and a test or README step that loads and attaches with
  `bpftool` or `tc`.
* `lib/luaxdp.c` and `lib/luatc.c` publish the kfuncs, `bpf_luaxdp_run` and `bpf_luatc_run`;
  `lib/luakfunc.h` holds the lookup, lock and `pcall` sequence they share, #561 having closed
  without one kfunc for every type. The callback
  runs in the kernel Lua VM, in an IRQ-context runtime, under the runtime lock, with the packet
  and the argument wrapped in two `data` objects reset per call.
* `lib/luabpf.c` and `lib/bpf/map.lua` give a kernel script typed access to pinned maps by path:
  the control plane exists.
* `examples/sniclassify/classify.c` is a partitioned program written by hand: a hash map decides
  the common case in eBPF and only a miss calls Lua; the LSM plan's phase 4 asks for the same
  shape on LSM.
* `lunatic` (#743) builds `luac.c` on the host against the `lua/` submodule with the `_KERNEL`
  configuration and dumps bytecode the kernel loads unchanged. That bytecode carries the fact
  this plan leans on: the kernel Lua is integer only, with `/` as integer division and five
  opcodes fenced out (`kernel-notes.md`, "The compiler host").

What exists for Lua-to-eBPF compilation: nothing in the tree, and nothing maintained elsewhere.
bcc's LuaJIT frontend (2016) is the closest ancestor and is bound to LuaJIT's bytecode and `ffi`;
`kernel-notes.md` has the numbers.

## What is missing

| Expected result | Gap |
|-----------------|-----|
| A Lua function becomes a program | No translator from Lua bytecode to `bpf_insn`, no type discipline that says which functions can, no object writer. |
| One command loads and attaches | The CLI knows `/dev/lunatik` and `modprobe`; it knows nothing of `bpf(2)`, links or pins. |
| Errors name the Lua line | No `.BTF`/`.BTF.ext` writer for `func_info` and `line_info`. |
| Call into the kernel runtime | The kfunc and its `arg`/`arg__sz` contract exist; nothing generates the call or the marshalling. |
| Shared maps | Maps are created by `bpftool map create` in the suites and by `SEC(".maps")` in the stubs; no declaration a Lua program and a Lua script share. |
| Sleepable and struct_ops contexts | Unreachable by construction of the trampoline (`kernel-notes.md`, "Sleeping"). |
| Tests | No harness compiles a program, loads it, runs it with a packet and compares. |

Supporting gaps:

* `lunatic` compiles and runs nothing, and the CLI's Lua, where the translator runs, refuses the
  chunk `lunatic` writes: its header carries an integer `lua_Number`, and its opcodes and
  metamethod events are numbered without the ones `_KERNEL` fences out. Running the body from that
  chunk takes a rewrite of it in the CLI's numbering, and handing a function's prototype
  (instructions, constants, upvalue descriptors, line info) to Lua code takes a reader of a chunk,
  both with the tables of the opcodes, the events and the format of each build;
* the CLI has no C extension; the loader needs libbpf;
* nothing in the build compiles a BPF object at `make install`.

## Decisions

Each of these is a fork; the reason is recorded so it is not re-argued at every phase, and so a
change in the facts behind it can reopen it.

| Decision | Reason | What would reverse it |
|----------|--------|----------------------|
| The loader is the CLI over `bpf(2)`, not the module over `kern_sys_bpf` | The module path has no verifier log, no module BTF fd for the tree's kfuncs, no pinned object by path, and a symbol namespaced against it; the CLI has all four and runs on the same host, so it compiles against the same kernel (`kernel-notes.md`, first section) | A kernel that accepts a kernel log buffer and adds `BPF_BTF_GET_FD_BY_ID` and `BPF_OBJ_GET` to the allowlist; then the loader becomes a `bpf.prog` object in `lib/luabpf.c` and the CLI keeps the fallback |
| One loader, one back end | AGENTS.md: two mechanisms doing one job. A second loader (kernel) buys runtimes that start without a CLI process, which the pinned program already serves; a second back end (C for clang) buys LLVM's verifier-friendly shapes, which the runtime library buys for the fixed algorithms without a second emitter | A verified shape the direct emitter cannot produce and the library cannot wrap |
| The translator runs under the CLI's Lua 5.5, which runs the body from the chunk `lunatic` writes | The bytecode decides what a compiled function means: `lunatic` compiles it with the kernel's own arithmetic, and the CLI's Lua loads that chunk, renumbered for its build, so the body computes as the kernel does and the functions it hands over are the bytecode compiled, with no second compilation to match them against. A driver hosting the translator under the kernel configuration was weighed and declined: a second host build of the kernel's Lua to keep in step with `_KERNEL`, where the renumbering takes two generated tables. So was the CLI's Lua compiling the file again from source to run the body: `10 / 4` is 2.5 there and 2 in the kernel, and each function the body hands over has to be found in `lunatic`'s chunk by its lines and its shape | An opcode the `_KERNEL` patch makes the VM run differently on integer operands; then the body needs the kernel's VM, not only its bytecode |
| The compiler does not wait for a benchmark | Three of its four reasons are independent of speed: contexts the trampoline cannot reach, the verifier checking the user's own code, and no C on the user's side. Speed is the fourth, and the only one the number decides | Nothing; the number changes what the docs claim about speed, not whether the compiler is built |
| The number is measured in phase 0 anyway | The design claims the per-call sequence of the trampoline as a cost; a cost claim without a number is a duplication, and the escape hatch's users need to know what a call into the VM costs on their hook | Not applicable |
| A precompiled BPF runtime library is in | Fixed algorithms (string compare, bounded copies, header walks) are C compiled once by clang at `make` and linked into every program by libbpf's linker, so the emitter emits straight-line code and calls; DTrace 2.0 ships this shape (`kernel-notes.md`) | The library growing past what the emitter could have done in a few lines each: then move those into the emitter and shrink it |
| The escape hatch is explicit, never inferred | A partition the compiler chooses silently falls back per packet and hides the cost; a refused construct is an error naming the line, and the program calls the runtime where it decides to (`api.md`) | A measured case where the compiler's split beats the author's; then offer inference as an opt-in, still reported |
| The interpreter-as-a-BPF-program is out | The objective is that the verifier checks the user's program. An interpreter verified once and fed bytecode as data gives the verifier's guarantee about the interpreter, not about the program, and its speed is by construction an interpreter's. It is a different project | A measured verification budget and a per-packet number for such an interpreter; neither exists |
| Lua-callable verified functions through a Lunatik `struct_ops` are a separate design | It needs Lunatik to define a program type of its own, with its own verifier ops and context; that is a kernel-side design this compiler would then feed, not part of it | Not applicable; it is deferred, not refused |
| Neither the `#line`-to-BTF mapping nor the scheduler lock claim is run first | The emitter writes its own `.BTF.ext`, so clang's `#line` handling is moot; struct_ops is out of scope, so the lock does not decide anything | Not applicable |

## Shape of the work

Four artefacts, none of them a kernel module:

* **the translator**, a Lua library, `luaebpf/`, a peer of `lib/` and `autogen/`, that the CLI's
  Lua runs through `lunatik bpf`: it has `lunatic` compile the program file, runs the body from
  that chunk, captures the functions it declares, reads their bytecode and emits `bpf_insn`,
  `.BTF`, `.BTF.ext` and the map definitions into a BPF ELF object. The chunk reader and rewriter,
  the BTF reader and the ELF writer are Lua inside the library; the tables they take, the opcodes,
  the metamethod events and the format, are generated from `lua/` at `make`;
* **the runtime library**, C under `luaebpf/rt/`, compiled by clang at `make`, shipped as one
  BPF object and linked into each program by libbpf's static linker as a step `make` runs;
* **the loader**, a libbpf C extension for the CLI's Lua: open, load, pin maps by name under a
  root, attach, pin the link, and the reverse;
* **the tests**, `tests/luaebpf/`, plus the existing `xdp` and `tc` suites gaining compiled
  programs.

The kernel modules are unchanged. `lib/luakfunc.h`, `lib/luaxdp.c` and `lib/luatc.c` stay what
they are and gain a caller: generated code instead of hand-written C. `lib/luabpf.c` and
`lib/bpf/map.lua` stay the control plane.

Two constraints shape everything. The first is where the compiler runs:

> The compiler runs on the machine that runs the program, reading `/sys/kernel/btf/vmlinux` for
> types and probing the kernel for the loop forms it accepts. There is no cross compilation, no
> CO-RE, no "which kernel is this for": the object is built for this kernel and loaded into it by
> the same command. `make install` compiles the program files beside the scripts they belong to.

The second is what a program is:

> The program file's body is compile-time Lua: it runs once, on the host, in the CLI's Lua, from
> the bytecode the kernel's own Lua build gives it, and every value it computes is a constant of
> the program. The functions it declares are the program: compiled from that same bytecode, they
> run in the kernel, verified, over a subset the translator can type. This mirrors
> the runtime model AGENTS.md describes for a script, where the body runs once in process context
> and the hooks run later under stricter rules.

### What it displaces

Naming what goes, as AGENTS.md asks:

* the C stubs that carry no logic beyond the kfunc call (`tests/xdp/xdp_pass.bpf.c` and its
  siblings, `examples/filter/https.c`) become Lua program files; `examples/sniclassify/classify.c`
  becomes a Lua program whose map lookup and call into the runtime are written in Lua. The stubs
  that exercise the kfunc against a hostile caller (`xdp_zerokey`, `tc_zerokey`) stay C: a compiler
  that never emits the hostile call cannot write them;
* the per-suite Makefiles and their `clang -target bpf` lines, `make ebpf`, `make ebpf_install`
  and `LUNATIK_EBPF_INSTALL_PATH`: compiled objects install beside their scripts;
* the `bpftool prog load` and `bpftool net attach` steps in the README and the suites, and the
  `tc qdisc`/`tc filter` steps in `tests/tc`: `lunatik run` does them;
* the LSM plan's phase 2 loader ("a small libbpf program that loads the object, attaches it and
  pins the link"): this design's loader is that program, for every type. The LSM stubs become
  program files once the `lsm` and `cgroup` kfuncs exist;
* `make btf_install` as a requirement for every user: needed only by programs that call into the
  kernel runtime.

Not displaced: the trampoline and `lib/luakfunc.h` (the escape hatch's kernel side),
`luabpf`/`bpf.map`, the runtime model, `lunatic`'s bytecode role.

## Prior art

* **bcc's LuaJIT frontend** (Marek Vavrusa, 2016, `src/lua/bpf/` in `iovisor/bcc`): bytecode in,
  abstract values with C types, proxies for the context and maps, an unrolled compare for string
  constants, an ELF writer, all in 3,254 lines of Lua. It has no loops (the 2016 verifier rejected
  every back edge), no BTF and no kfuncs, and it is LuaJIT's bytecode and `ffi`. Its design is
  this plan's translator; its code is not reusable.
* **ply** (Tobias Waldekranz): a direct emitter in C with a real IR and virtual registers, no
  LLVM, no loops, no BTF. The same point on the same curve.
* **DTrace 2.0 for Linux** (Oracle): a hand-written BPF code generator plus a library of BPF
  functions compiled once by `gcc-bpf` and linked at load. The runtime library here is that shape.
* **bpftrace**: an LLVM frontend, 7.7k lines of C++ against an API that moves every major. The
  cost this design declines to pay.
* **SystemTap's `stapbpf`**: a production direct emitter with loops only outside the kernel
  probes. Confirms that no shipping direct emitter with loops exists, which is the part of this
  work with no precedent at any size.
* **XDPLua** (Netdev 0x14, 2020): the same SNI filter in 200 lines of C "and much effort spent to
  circumvent the in-kernel verifier" against 37 lines of Lua; the pure-eBPF version could match
  one host name because the 2020 verifier had no loops. Both dropped 1.5 Mpps at 0.1 % CPU with a
  generator that could push no more. That 37-line program, compiled, is the target of phase 6.
* **`secmodel_sandbox`** (NetBSD, BSDCan 2017): a ruleset in C at roughly 70 ns per decision
  against roughly 4.5 µs when the interpreter ran (`doc/design/lsm-ebpf/plan.md`). The number that
  justifies keeping the hot path out of the VM.
* **"Kernel Extension DSLs Should Be Verifier-Safe!"** (Solleza et al., eBPF '25, DOI
  10.1145/3748355.3748368): a DSL compiler should emit only shapes the verifier accepts. Here that
  is a property of the subset, and a verifier rejection is a translator bug, not a user error.
* **"Characterizing and Bridging the Diagnostic Gap in eBPF Verifier Rejections"** (Zheng et al.,
  arXiv 2607.02748): 47 % of rejections surface as a bare `EINVAL`. The reason the loader must be
  where the log is.

## Phases

Each phase is one or more self contained pull requests.

### Phase 0: the number and the dependency decisions

Measure the trampoline on the tree's own XDP path with the benchmark's XDP event (#1912,
`doc/design/benchmark/plan.md`, Phase 3): packets per second through a native `XDP_PASS` program,
one whose callback only returns the verdict and one whose callback reads a packet byte first, in
one runtime and in a percpu one, with pktgen injecting on one CPU. Its numbers go into these
documents, and the same driver measures every later phase.

Settled with the maintainer: the translator runs in the CLI's Lua from the chunk `lunatic` (#743)
writes ("Decisions"), a program file is compiled by `lunatik bpf`, and the escape hatch calls the
kfunc of the program's type, `bpf_luaxdp_run` or `bpf_luatc_run`, since #561 closed without one
name for every type.

### Phase 1: the translator and the object

`luaebpf/` is created as a library with its own tests, and `lunatik bpf` calls it; the chunk
`lunatic` writes is rewritten in the CLI's numbering and loaded, and a reader hands each function's
prototype to Lua, with the tables of the opcodes, the metamethod events and the chunk format
generated from `lua/` at `make`. The translator gains a type lattice (integer,
boolean, constant, and the proxies of later phases),
arithmetic with Lua's floor semantics, comparisons, jumps, numeric `for` (bounded, or `may_goto`
when the bound is not constant), calls to functions the program file declares (subprograms, no
recursion), `return`; and an object writer for `.text`, `license`, `.BTF` and `.BTF.ext` with
`func_info` and `line_info` naming the Lua file and line. Refusals are compile errors with the
line. The first program type is XDP with a verdict computed from constants and arithmetic; no
context access yet.

Tests (`tests/luaebpf/`): every emitted program loads through `bpftool prog load`; a corpus of
functions run through `bpftool prog run` agree with the same functions interpreted on the host;
a refused construct fails with the documented message; a deliberately broken emission (a load
without its bounds check, injected by a test hook) produces a verifier log that names the Lua line.

### Phase 2: proxies, context, packet and maps

The context proxy (`ctx.data`, `ctx.data_end`, `ctx.ingress_ifindex` for XDP; `skb` fields for
TC), the packet proxy with the `data` object's method names (`getbyte`, `getuint16`, ...) and the
bounds check every access carries, BTF struct views over kernel types read from
`/sys/kernel/btf/vmlinux`, and map proxies declared with the `bpf.map` specs and emitted as
BTF-defined maps. `nil` from a lookup is a type the translator forces the program to test.

Tests: packet fields read through the proxy match the bytes handed to `bpftool prog run`; an
access past `data_end` takes the failure path and returns the default verdict; a map seeded by
`bpftool map update` decides the verdict.

### Phase 3: the loader

The CLI loads `<script>.bpf.o` when it exists: creates and pins the maps under
`/sys/fs/bpf/lunatik/<script>/`, starts the runtime, attaches with the target given on the
command line, pins the link; `stop` reverses it. `make install` compiles program files with
`lunatik bpf`. The `xdp` and `tc` suites gain compiled programs beside the C stubs that must stay;
the README's XDP section loses its `bpftool` lines.

Tests: `lunatik run` then `lunatik stop` leaves nothing pinned; a run with a missing target fails
before the runtime starts; the existing `xdp` and `tc` cases pass with a compiled program.

### Phase 4: the escape hatch

The callable proxy over the kernel runtime: `runtime(args...)` lowers to the kfunc call with the
arguments packed into `arg`, the return value mapped to `nil` on `-1`. The kernel side is what
`xdp.attach` and `tc.attach` are today, over `bpf_luaxdp_run` and `bpf_luatc_run`; the callback
reads `ctx:argument()` as it does now. `btf_install` becomes a requirement of this phase only.

Tests: a compiled program that defers to Lua on a miss sees the callback's verdict; the callback
receives the packed arguments; a program whose runtime is not loaded takes the default verdict.

### Phase 5: the runtime library, strings and loops beyond `for`

The C library (bounded copy, compare, byte-order helpers, the header walks the examples repeat),
linked by libbpf's linker at compile time; string constants and `getstring` into fixed buffers, so
a host name can be a map key; `while` and `repeat` under `may_goto`; open-coded iterators where
a kernel lacks `may_goto`.

Tests: the linked object loads and its library calls verify; a string compare against a constant
and a `c64`-keyed map lookup agree with the interpreter; a loop with a runtime bound terminates.

### Phase 6: examples and documentation

`examples/filter` rewritten with the SNI parser compiled whole (`examples/common/sni.lua` as the
source, shared with the interpreted path), `examples/sniclassify` with its map and its call into
Lua, the README module and usage sections, the LDoc for the compile-time modules, and the API
cleanup the examples expose. The benchmark's XDP event, run on the compiled filter, produces the
numbers these documents then quote.

## Sizing

Sized by what fits in a reviewable pull request.

| Scope | Phases |
|-------|--------|
| Minimum useful | 0 to 3. A verdict program in Lua, loaded and attached by `lunatik run`, with the verifier's log as the error. |
| Complete | 0 to 6. Maps, the call into Lua, strings, the examples compiled. |

Phase 3 is the boundary: before it, a compiled program is a test artefact loaded by `bpftool`;
from it on, a user runs one.

## Non goals

* **A new language.** The source is Lua as the kernel runs it. The subset is what the verifier can
  check; there is no syntax of its own and no annotation beyond the program constructor.
* **A kernel-side loader.** `kern_sys_bpf` is namespaced against this use and returns no log
  (`kernel-notes.md`). Revisited only if that changes upstream.
* **A C or LLVM back end.** The runtime library is the only C, compiled once. A second emitter is
  two mechanisms doing one job.
* **Cross compilation.** The compiler runs on the machine that runs the program. A build host
  that compiles for another kernel needs CO-RE and is a different tool.
* **Replacing the interpreter.** The kernel Lua VM stays the language for everything the subset
  refuses; the escape hatch is how a program reaches it.
* **An interpreter as a BPF program.** See "Decisions".
* **Lua-callable verified functions through a Lunatik `struct_ops`.** A separate design that
  would consume this compiler.
* **Runtime tables, strings and closures in a compiled function, `pcall`, coroutines, metatables
  beyond the translator's own proxies.** Refused with the line, by design.
* **The LSM plan's "no DSL, no compiler" non goal is not contradicted.** That non goal declines a
  policy language for the LSM binding. This design adds no language: a policy stays Lua, its
  ruleset stays a map written from Lua, and what the compiler produces is the stub the LSM plan
  writes by hand in C.

## Risks

| Risk | Mitigation |
|------|-----------|
| The emitter produces a shape the verifier rejects on some kernel | The subset is chosen so every shape is one the verifier accepts by construction; the suite loads every emitted program on the running kernel; the loop form is probed, not assumed |
| The verification budget is exhausted by `may_goto` loops in a real program | Measured in phase 1 with the budget line the log prints ("processed N insns"); global subprograms and iterators are the documented remedies |
| The subset proves too small for the programs the maintainer wants | The escape hatch keeps the whole language one call away; a program that calls Lua on every packet is the status quo generated instead of hand written, and the compiler reports every such call |
| The CLI's VM runs the kernel's bytecode differently from the kernel's VM | The `_KERNEL` patch to `lvm.c` removes the float paths and keeps the integer ones, so integer operands run alike; the body's own run is the interpreter oracle the compiled program is compared against, so a difference fails a differential case |
| The CLI's libraries hand the body a float the kernel's Lua would not (`math.sqrt`, a string coerced to a number) | A float reached from a compiled function is refused at the line that reaches it |
| libbpf on the target lacks `bpf_program__attach_tcx` (1.3.0) | The loader reports the missing attach as an error naming the version; the suite skips |
| A stale pinned program or link survives a failed run | `lunatik stop` and the suite cleanup unpin everything under the script's root, up front and in the trap |
| The compiled and the interpreted program disagree on an edge (division by zero, out-of-bounds) | The differential tests in `testing.md` run both on the same inputs; the failure path is specified as the program type's default verdict, and the interpreted side raises where the compiled side takes that path |

## Definition of done, per phase

1. `make` builds `lunatic`, the generated tables and the runtime library clean, no new warnings;
2. LDoc comments on every new compile-time module, listed in `config.ld` in alphabetical order;
3. a row in the README module table for the compile-time modules, and the XDP usage section
   updated when the loader lands;
4. a test in `tests/luaebpf/`, wired into that suite's `run.sh`, and described in
   `tests/README.md`;
5. the test skips (not fails) when the kernel lacks a feature, the toolchain lacks `bpftool` or
   libbpf, or `lunatic` is not built;
6. the full suite still passes: `sudo lunatik test`;
7. every refusal the phase adds has a test asserting its message and line;
8. commits are small and each one stands alone.

