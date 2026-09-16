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
* `lib/luaxdp.c` and `lib/luatc.c` publish the kfuncs; `lunatik_ebpf.h` factors the lookup, lock
  and `pcall` sequence they share; issue #561 turns it into one `lunatik_bpf_run`. The callback
  runs in the kernel Lua VM, in an IRQ-context runtime, under the runtime lock, with the packet
  and the argument wrapped in two `data` objects reset per call.
* `lib/luabpf.c` and `lib/bpf/map.lua` give a kernel script typed access to pinned maps by path:
  the control plane exists.
* `examples/sniclassify/classify.c` is a partitioned program written by hand: a hash map decides
  the common case in eBPF and only a miss calls Lua; the LSM plan's phase 4 asks for the same
  shape on LSM.
* `lunatikc` (#742, not merged) builds the kernel's own Lua on the host and dumps bytecode the
  kernel loads unchanged. Its `doc/design/luac/kernel-notes.md` states the fact this plan leans
  on: the kernel Lua is integer only, with `/` as integer division and five opcodes fenced out.

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

* `lunatikc` links the Lua core only; hosting a translator written in Lua adds the standard
  libraries to that link, and a way to hand a function's prototype (instructions, constants,
  upvalue descriptors, line info) to Lua code;
* the CLI is Lua 5.4 and has no C extension; the loader needs libbpf;
* nothing in the build compiles a BPF object at `make install`.

## Decisions

Each of these is a fork; the reason is recorded so it is not re-argued at every phase, and so a
change in the facts behind it can reopen it.

| Decision | Reason | What would reverse it |
|----------|--------|----------------------|
| The loader is the CLI over `bpf(2)`, not the module over `kern_sys_bpf` | The module path has no verifier log, no module BTF fd for the tree's kfuncs, no pinned object by path, and a symbol namespaced against it; the CLI has all four and runs on the same host, so it compiles against the same kernel (`kernel-notes.md`, first section) | A kernel that accepts a kernel log buffer and adds `BPF_BTF_GET_FD_BY_ID` and `BPF_OBJ_GET` to the allowlist; then the loader becomes a `bpf.prog` object in `lib/luabpf.c` and the CLI keeps the fallback |
| One loader, one back end | AGENTS.md: two mechanisms doing one job. A second loader (kernel) buys runtimes that start without a CLI process, which the pinned program already serves; a second back end (C for clang) buys LLVM's verifier-friendly shapes, which the emitter produces itself for the shapes the subset needs | A verified shape the direct emitter cannot produce |
| The compiler runs the kernel-configured Lua 5.5 (`lunatikc`), not the CLI's 5.4 | The translator folds constants and reads bytecode; doing that with the kernel's own arithmetic and opcode numbering makes the compiled program agree with the interpreted one by construction. This is #742's shape (a C driver the tree owns, which can host a translator); #743 builds upstream `luac.c` against the kernel configuration, a compiler driver the tree does not own | Nothing short of the kernel Lua leaving `_KERNEL` behind |
| The compiler does not wait for a benchmark | Three of its four reasons are independent of speed: contexts the trampoline cannot reach, the verifier checking the user's own code, and no C on the user's side. Speed is the fourth, and the only one the number decides | Nothing; the number changes what the docs claim about speed, not whether the compiler is built |
| The number is measured in phase 0 anyway | The design claims the per-call sequence of the trampoline as a cost; a cost claim without a number is a duplication, and the escape hatch's users need to know what a call into the VM costs on their hook | Not applicable |
| A precompiled BPF runtime library is out | Every function it was scoped for was traced to no caller, to two emitted instructions, or to a kernel helper, so the library would have been a build dependency and a link step with nothing left to hold: the header walks the examples repeat have no caller, since phase 6 compiles `examples/common/sni.lua` itself rather than duplicating it in C; a byte swap is two instructions the emitter already emits, and `examples/common/sni.lua` writes one in Lua today; the only comparison the subset needs is against a **constant**, whose length is known while compiling, so it is one test of the read length and a word compare per eight bytes, straight-line; and a bounded copy is a kernel helper, `bpf_skb_load_bytes` or `bpf_xdp_load_bytes`, which the emitter calls by number. This is the reversal the row for the library already named, at its extreme: what the emitter could have done in a few lines each, done there | A verified shape the direct emitter cannot produce and no kernel helper or kfunc offers. The linking is not the obstacle: `bpftool gen object` accepts every object the emitter writes today, keeping the program section, `.maps`, the `.ksyms` extern, `.BTF` and `.BTF.ext`, and the merged BTF still carries the Lua file name and source lines |
| The escape hatch is explicit, never inferred | A partition the compiler chooses silently falls back per packet and hides the cost; a refused construct is an error naming the line, and the program calls the runtime where it decides to (`api.md`) | A measured case where the compiler's split beats the author's; then offer inference as an opt-in, still reported |
| The interpreter-as-a-BPF-program is out | The objective is that the verifier checks the user's program. An interpreter verified once and fed bytecode as data gives the verifier's guarantee about the interpreter, not about the program, and its speed is by construction an interpreter's. It is a different project | A measured verification budget and a per-packet number for such an interpreter; neither exists |
| Lua-callable verified functions through a Lunatik `struct_ops` are a separate design | It needs Lunatik to define a program type of its own, with its own verifier ops and context; that is a kernel-side design this compiler would then feed, not part of it | Not applicable; it is deferred, not refused |
| Neither the `#line`-to-BTF mapping nor the scheduler lock claim is run first | The emitter writes its own `.BTF.ext`, so clang's `#line` handling is moot; struct_ops is out of scope, so the lock does not decide anything | Not applicable |

## Shape of the work

Three artefacts, none of them a kernel module:

* **the translator**, a Lua library, `luaebpf/`, a peer of `lib/` and `autogen/` rather than a
  part of `lunatikc`: `luaebpf.compile(chunk)` loads the program file, captures the functions it
  declares, reads their bytecode and emits `bpf_insn`, `.BTF`, `.BTF.ext` and the map definitions
  into a BPF ELF object. The BTF reader and the ELF writer are Lua inside the library, so compiling
  needs no C. `lunatikc` hosts it: a subcommand that stands up the kernel-configured Lua with the
  standard libraries and a prototype accessor and calls `luaebpf.compile`. The library is what the
  tests exercise and what any other host reuses; the driver is a dozen lines;
* **the loader**, a libbpf C extension for the CLI's Lua: open, load, pin maps by name under a
  root, attach, pin the link, and the reverse;
* **the tests**, `tests/luaebpf/`, plus the existing `xdp` and `tc` suites gaining compiled
  programs.

The kernel modules are unchanged. `lunatik_ebpf.h`, `lib/luaxdp.c`, `lib/luatc.c` and #561 stay
what they are and gain a caller: generated code instead of hand-written C. `lib/luabpf.c` and
`lib/bpf/map.lua` stay the control plane.

Two constraints shape everything. The first is where the compiler runs:

> The compiler runs on the machine that runs the program, reading `/sys/kernel/btf/vmlinux` for
> types and probing the kernel for the loop forms it accepts. There is no cross compilation, no
> CO-RE, no "which kernel is this for": the object is built for this kernel and loaded into it by
> the same command. `make install` compiles the program files beside the scripts they belong to.

The second is what a program is:

> The program file's body is compile-time Lua: it runs once, on the host, under the kernel's own
> Lua, and every value it computes is a constant of the program. The functions it declares are the
> program: they run in the kernel, verified, over a subset the translator can type. This mirrors
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

Not displaced: the trampoline and #561 (the escape hatch's kernel side), `luabpf`/`bpf.map`, the
runtime model, `lunatikc`'s bytecode role.

## Prior art

* **bcc's LuaJIT frontend** (Marek Vavrusa, 2016, `src/lua/bpf/` in `iovisor/bcc`): bytecode in,
  abstract values with C types, proxies for the context and maps, an unrolled compare for string
  constants, an ELF writer, all in 3,254 lines of Lua. It has no loops (the 2016 verifier rejected
  every back edge), no BTF and no kfuncs, and it is LuaJIT's bytecode and `ffi`. Its design is
  this plan's translator; its code is not reusable.
* **ply** (Tobias Waldekranz): a direct emitter in C with a real IR and virtual registers, no
  LLVM, no loops, no BTF. The same point on the same curve.
* **DTrace 2.0 for Linux** (Oracle): a hand-written BPF code generator plus a library of BPF
  functions compiled once by `gcc-bpf` and linked at load. The library half is the shape this
  design weighed and declined: its functions here are one helper call or a few instructions.
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

Measure the trampoline on the tree's own XDP path: a native `XDP_PASS` program against
`xdp_pass.bpf.c` calling a Lua callback that sets the verdict, on the `tests/xdp` veth pair, with
a packet generator, reporting packets per second and CPU. The script lives under `tools/`, its
numbers go into these documents, and the same script measures every later phase.

Settle, with the maintainer: that `lunatikc` lands in #742's shape (a C driver in the tree, which
this design extends by one subcommand; with the translator a library, the driver's whole job is to
stand up the state and `require` it, which #742 gives in a dozen lines and #743's upstream `luac.c`
cannot host), and that #561 lands before phase 4 (the escape hatch calls whatever name the module
publishes, so phases 1 to 3 do not wait for it).

### Phase 1: the translator and the object

`luaebpf/` is created as a library with its own tests; `lunatikc` gains the standard libraries, a
way to hand a function's prototype to Lua, and the subcommand that calls the library, and nothing
else of the compiler lives in it. The translator gains a type lattice (integer, boolean, constant, and the proxies of later phases),
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

What the corpora cost the verifier on 6.12.88, as `budget.sh` records them, against the million
the verifier allows: the constant-verdict programs 4 processed instructions, the arithmetic rows
22, the division rows 13, the branch rows 20, the constant-bound loops 249, the loops under a
`may_goto` header 319, and the calls 253. The ceiling the case asserts is 20,000, two orders of
magnitude above what the emitted shapes cost today and two below the limit.

### Phase 2: proxies, context, packet and maps

The context proxy (`ctx.ingress_ifindex` and `ctx.rx_queue_index` for XDP, the `skb` fields for
TC, with `data` and `data_end` refused as the packet bounds they are), the packet proxy with the
`data` object's method names (`getbyte`, `getuint16`, ...) and the bounds check every access
carries, kernel struct layouts read from `/sys/kernel/btf/vmlinux`, and map proxies declared with
the `bpf.map` specs and emitted as BTF-defined maps. `nil` from a lookup is a type the translator
forces the program to test. A check that fails inside a called function reaches the program's
default verdict through a flag the callee raises in its caller's frame, which costs the fifth
argument register and leaves a compiled function four of its own.

Tests: packet fields read through the proxy match the bytes handed to `bpftool prog run`; an
access past `data_end` takes the failure path and returns the default verdict; a map seeded by
`bpftool map update` decides the verdict.

What the phase 2 corpora cost, beside the phase 1 figures above: the context rows 15 processed
instructions, the packet rows 74, the out-of-bounds rows 23, the map reads 95, the map writes 35
and the struct value rows 21. The packet proxy re-reads `data` and `data_end` on every access
rather than keeping a pointer pair live, and the figures say what that costs: the heaviest packet
program, nine accessors over one packet, sits at 74, two orders of magnitude under the ceiling.

### Phase 3: the loader

The CLI loads `<script>.bpf.o` when it exists: creates and pins the maps under
`/sys/fs/bpf/lunatik/<script>/`, starts the runtime, attaches with the target given on the
command line, pins the link; `stop` reverses it. `make install` compiles program files with
`lunatikc`, beside the scripts they belong to. The `xdp` and `tc` suites gain compiled programs
beside the C stubs that must stay; the README's `lunatikc bpf` block loses its `bpftool prog load`
line. `make ebpf` and `LUNATIK_EBPF_INSTALL_PATH` stay: their only consumers are the two examples'
C stubs, whose whole body is the kfunc call, so they go in phase 6 with the examples they serve.

Tests: `lunatik run` then `lunatik stop` leaves nothing pinned; a run with a missing target fails
before the runtime starts; the existing `xdp` and `tc` cases pass with a compiled program.

### Phase 4: the escape hatch

The callable proxy over the kernel runtime: `runtime(args...)` lowers to the kfunc call with the
arguments packed into `arg`, the return value mapped to `nil` on `-1`, and the answer a type the
program must test before reading it as a number. The kernel side is what `xdp.attach` and
`tc.attach` are today (or #561's `lunatik_bpf_run` once it lands); the callback reads
`ctx:argument()` as it does now. `btf_install` becomes a requirement of this phase only. The
object grows what libbpf reads a kfunc call out of -- a BTF `FUNC` of extern linkage in a `.ksyms`
DATASEC, an undefined symbol and an `R_BPF_64_32` relocation -- and `lunatik run` reports what
libbpf said, since a kfunc it cannot resolve never reaches the kernel and leaves no verifier log.

Tests: a compiled program that defers to Lua on a miss sees the callback's verdict; the callback
receives the packed arguments; a program whose runtime is not loaded takes the default verdict.

What the escape hatch costs, beside the figures above: the `callback` corpus 29 processed
instructions, against the same 20,000 ceiling. A call is three stores of the key, one store per
argument, five registers, the call and the two shifts that sign-extend the answer; the key's
stores are what a longer runtime name adds, and a call inside a loop pays them per iteration.

### Phase 5: strings and loops beyond `for`

`packet:getstring(at, len)` into a buffer of the reading function's frame, lowered to
`bpf_skb_load_bytes` in a TC program and `bpf_xdp_load_bytes` in an XDP one, over a buffer zeroed
first; an upper bound on an integer register, narrowed where the program compares it against a
constant, so a read whose length the compiler cannot bound is an error naming the line rather than
a clamp the interpreted twin would disagree with; comparison against a string constant, length
first and then the bytes; a `c<n>` map key built from such a read, which is what lets a host name
key a map both sides open with the same spec; `while` and `repeat` under `may_goto`; open-coded
iterators where a kernel lacks `may_goto`. The runtime library this phase was scoped to build is
not built: see the decision row above.

The helper and the loop form are probed rather than read off the kernel's release, since
`bpf_xdp_load_bytes` landed in v5.18 and the tree supports 5.15; `LUAEBPF_PROBE` replaces the
probe's answer with an allow-list, which is what exercises every lowering and every refusal on one
host.

Tests: a string compare against a constant and a `c64`-keyed map lookup agree with the interpreter;
a loop with a runtime bound terminates.

What the phase 5 corpora cost, beside the figures above: the reads 62 processed instructions, the
comparisons 81, the keyed lookups 68.

### Phase 6: examples and documentation

`examples/filter` rewritten with the SNI parser compiled whole (`examples/common/sni.lua` as the
source, shared with the interpreted path), `examples/sniclassify` with its map and its call into
Lua, the README module and usage sections, the LDoc for the compile-time modules, and the API
cleanup the examples expose. The phase 0 script produces the numbers these documents then quote.

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
* **A C or LLVM back end.** The emitter writes every shape the subset needs, and a kernel helper
  covers what would have been a C library. A second emitter is two mechanisms doing one job.
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
| `lunatikc` lands in #743's shape, or not at all | Phase 0 settles it; the translator needs a host state running the kernel's Lua with the libraries, which #742's driver provides in a dozen lines |
| The compiler grows into `lunatikc` and the two become one tool | The translator is a library with its own API and tests, `luaebpf/`; `lunatikc` hosts it through one subcommand. A separate binary was weighed and declined: it would be a second host build of the kernel's Lua to keep in step with the kernel configuration, for a boundary the library already draws |
| libbpf on the target lacks `bpf_program__attach_tcx` (1.3.0) | The loader reports the missing attach as an error naming the version; the suite skips |
| A stale pinned program or link survives a failed run | `lunatik stop` and the suite cleanup unpin everything under the script's root, up front and in the trap |
| The compiled and the interpreted program disagree on an edge (division by zero, out-of-bounds) | The differential tests in `testing.md` run both on the same inputs; the failure path is specified as the program type's default verdict, and the interpreted side raises where the compiled side takes that path |

## Definition of done, per phase

1. `make` builds `lunatikc` clean, no new warnings;
2. LDoc comments on every new compile-time module, listed in `config.ld` in alphabetical order;
3. a row in the README module table for the compile-time modules, and the XDP usage section
   updated when the loader lands;
4. a test in `tests/luaebpf/`, wired into that suite's `run.sh`, and described in
   `tests/README.md`;
5. the test skips (not fails) when the kernel lacks a feature, the toolchain lacks `bpftool` or
   libbpf, or `lunatikc` is not built;
6. the full suite still passes: `sudo lunatik test`;
7. every refusal the phase adds has a test asserting its message and line;
8. commits are small and each one stands alone.

