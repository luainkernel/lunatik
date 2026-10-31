# Testing the Lua to eBPF compiler

Lunatik's tests are shell scripts emitting KTAP, driving a kernel Lua script and asserting on what
it prints to `dmesg` or on what userspace observes. A compiler is tested differently: by what it
emits, by what the verifier accepts, and by whether the compiled program computes what the
interpreted one does. `tests/xdp/` and `tests/tc/` are the closest existing suites (they build,
load and attach a program and drive a ping through it); `tests/bpf/` creates and reads pinned
maps from the shell. Read both, plus `tests/lib.sh`, before writing anything new.

Run everything with `sudo lunatik test`, one suite with `sudo lunatik test luaebpf`.

## What this suite needs that others do not

**A compiler on the host.** Every test compiles a program file with `lunatik bpf` at test time,
on the machine that runs it. The CLI's Lua runs the body from the chunk `lunatic` writes, and
`lunatic` is built by `make` and installed next to `lunatik`; a missing binary is a skip with a
message naming `make`.

**Three oracles, in this order.**

1. *The verifier.* Every object the suite produces is loaded on the running kernel, through
   `bpftool prog load` into a pin under `/sys/fs/bpf/luaebpf/`, and a rejection is a failure that
   prints the log. This is the test that matters most: the design's claim is that every emitted
   shape is one the verifier accepts by construction.
2. *The interpreter.* A compiled program is run with `bpftool prog run` (`BPF_PROG_TEST_RUN`,
   XDP and TC only) over a packet file, and the same Lua function is run on the host, from the
   bytecode `lunatic` compiled, in the CLI's Lua with a `data`-like proxy over the same bytes, so
   the oracle divides as the kernel does. The program file's own body is what runs it: it calls
   each function it declares and writes the answer beside the object, so no compiler feature
   exists for the tests and the two oracles stay the host VM and the kernel's JIT. The verdicts
   must match on every packet of a corpus. Where the interpreted side raises (an out-of-bounds
   read, a division by zero, a map key or value `string.pack` refuses), the compiled side must
   return the program's default verdict, and the test asserts that pairing, not equality. A loop
   past the budget the kernel gives `may_goto` stops with the default verdict where the interpreter
   makes every pass, so its test asserts the verdict alone.
3. *The wire.* The existing `xdp` and `tc` harness: a veth pair with its peer in a namespace, a
   ping, and a verdict that either blocks it or lets it through.

**Packet corpora, checked in.** From phase 2, `tests/luaebpf/packets.lua` holds them as hex: an
ARP, an IPv4 ICMP echo, a TCP SYN to 443, a TLS ClientHello with an SNI, a truncated
ClientHello. The program file's body writes the bytes beside its oracle, as it already writes
the oracle itself, so the compiled and the interpreted side read the same bytes and the corpus
needs no install rule of its own. Every differential test runs over the whole corpus so the
failure paths are exercised, not only the happy one. Phase 1 reads no packet, and its cases hand
`prog run` the fourteen bytes `BPF_PROG_TEST_RUN` demands of an XDP program.

**Proving the compiler discriminates.** Removing a mechanism from the emitter must fail the
suite. The emitter exposes a test hook, `LUAEBPF_DROP`, an environment variable the CLI has no
option for, naming one mechanism to drop: `divisor` (the test before a division), `maygoto` (the header
a loop without a proven bound needs), `lineinfo` (the `.BTF.ext` records), `verdict` (the write to
`R0`), and `bounds` (the `data_end` test before a packet load). Each has a test that asserts the
verifier rejects the program, that the log lacks the Lua line, or that the arithmetic changes.

**Pinned object cleanup.** Programs, maps and links pinned by a test outlive it. The cleanup
removes everything under `/sys/fs/bpf/luaebpf/` and under `/sys/fs/bpf/lunatik/tests/luaebpf/`
(the loader's root for the suite's scripts), in the `trap` and once up front, so a crashed run
does not poison the next.

**Feature skips, not failures.** A kernel without `may_goto` skips the runtime-bound loop tests
and asserts instead that the compiler refuses the loop with the documented message; a libbpf
without `bpf_program__attach_tcx` skips the TC attach tests; a machine without `bpftool` or
`clang` (needed once, for the runtime library at `make`) skips the suite with the reason.

## Test matrix

Fill this in as the phases land. Each row is one `.sh` plus the program file (and the kernel
script where the case needs one), following the convention that the description of the test lives
in the shell script and the Lua files carry a single line pointing back at it.

Coverage means the matrix of construct by outcome: accepted and refused, verified and rejected,
matching and failing, not a list of features.

### Phase 1: the translator and the object

| Test | Proves |
|------|--------|
| `host.sh` | the body runs from the chunk `lunatic` compiles, rewritten for the CLI's Lua, and computes as the kernel does, a module installed as a kernel chunk included; `luaebpf.proto.read` hands back a function's own bytecode, `/` read as integer division, and refuses a function the CLI's Lua compiled |
| `pass.sh` | the constant-verdict program compiles, loads, and `prog run` returns the verdict |
| `arith.sh` | every integer operator over a corpus of operand pairs, negative operands included, matches the interpreter (`//` and `%` floor semantics, shifts past 63) |
| `divzero.sh` | a division by zero returns the default verdict where the interpreter raises |
| `branch.sh` | `if`, `and`, `or`, `not` and every comparison over signed and unsigned edges match |
| `forconst.sh` | a `for` with constant bounds runs the right count; a zero-trip and a descending loop included |
| `forvar.sh` | a `for` whose bound is a program value verifies with `may_goto` and terminates, or takes the default verdict past the kernel's budget; skips and asserts the refusal on a kernel without it |
| `call.sh` | a call to a file-declared function becomes a subprogram; the object carries one `func_info` per subprogram; a check that fails inside one takes the program's default verdict through the flag each frame raises in its caller's |
| `refuse.sh` | each refused construct (runtime table, closure, vararg, `pcall`, unknown global, tail call, `while`, `repeat`, a float the CLI's libraries return, a float literal `lunatic` refuses to parse, a function the CLI's Lua compiled from a string) fails with its message and line, and nothing is written; recursion and the five-argument call sit in `call.sh`, beside the calls they are the edges of |
| `lineinfo.sh` | the object's `.BTF.ext` names the `.lua` file, and a program broken by the test hook is rejected with a log that quotes the Lua line |
| `budget.sh` | the log's "processed N insns" line for the corpus programs, recorded and asserted under a ceiling, so a regression in emitted shape is caught before it reaches the 1M budget |

`refuse.sh` and `lineinfo.sh` are the ones that justify the design: a compiler that emits a
verifier-rejected shape for valid input is a bug, and the user must never see a bare `EINVAL`.

### Phase 2: proxies, context, packet and maps

| Test | Proves |
|------|--------|
| `packet.sh` | every accessor the kernel's `data` object publishes, `#`, a computed offset and a read inside a called function, over the corpus through `ctx:packet()` and `skb:data()`, match the interpreter's reads of the same bytes; a method neither proxy has is refused by name, and so is a read wider than a byte on a kernel without efficient unaligned access, which the program file's body stands for by setting `luaebpf.emit.unaligned` |
| `bounds.sh` | an access one byte past `data_end`, above the offset ceiling or at a negative offset takes the default verdict, through `ctx:packet()` and `skb:data()`; the same program with the bounds check dropped by the test hook is rejected |
| `nonlinear.sh` | a TC program attached to a veth's egress, and then to its ingress, takes its default verdict at `skb:data()` on a TCP segment whose payload sits in page fragments, where the kernel's `skb:data()` raises in a tc callback, and answers its own verdict on a linear ping of the same size |
| `ctx.sh` | `ctx:ingress()`, `ctx:queue()`, `#skb`, `skb:ifindex()`, `skb:hash()` and `skb:priority()` read back what `prog run` supplies, a `skb:priority(v)` write comes back in `ctx_out`, one past 32 bits the program computes takes the default verdict, and one object carrying both kinds loads with no type argument; a field read or assigned on either context, the fields the proxies read and one the skb object does not carry among them, a value given a boolean or a constant out of range, `ctx.data`, the packet opened under the other context's name and `skb:data` given a layer are refused with their lines |
| `mapget.sh` | the object's maps are created and pinned by `bpftool prog loadall ... pinmaps`, a map seeded by `bpftool map update` decides the verdict, a missing key is `nil`, a lookup spilled to the frame narrows there too, a computed key outside its spec takes the default verdict, and an untested use, a string key and a declaration the object cannot carry are refused at compile time; a key the compiler holds outside its spec sits in `refuse.sh` |
| `mapset.sh` | an update, an update under a key the program computed, a `nil` delete and a delete of a key that was never there are what `bpftool map lookup` finds afterwards; a computed value or key outside its spec takes the default verdict and leaves the map as it was, so does a write the map refuses, and a value that is not a number is refused; a value the compiler holds outside its spec sits in `refuse.sh` |
| `struct.sh` | a `struct` value spec yields field access with the right offsets and widths, one field per width and signedness plus a layout read out of the kernel's own BTF; a write to a field or to the whole value, an unknown field, an index into the value, one the program computes among them, a field no eBPF load covers and a spec that is neither a format nor a codec are refused, and an untested lookup is refused as the struct value it may be, and so is a field wider than a byte on a kernel without efficient unaligned access, as in `packet.sh` |
| `btfview.sh` | `luaebpf.vmlinux` reports a kernel struct's size and its members' byte offsets as `bpftool btf dump` does, and drops the bitfields and unions a layout cannot describe |

### Phase 3: the loader

| Test | Proves |
|------|--------|
| `load.sh` | `lunatik run` on a script with a program file pins the maps, starts the runtime, attaches and pins the link, in that order: the kernel script opens the map by its pin path, which it could only do if the map was pinned before the runtime started. A script with an object and no `.lua` runs the program alone |
| `stop.sh` | `lunatik stop` leaves no pin root and no directory above it that held only the root, nothing on the device even while another pin holds the link, and no runtime; a `run` after it attaches again, and a `run` over the root a crashed one left removes it rather than adopting its maps. A `run` of a script already running is refused with the live one untouched, and where no runtime holds the root the `run` redeploys; a `stop` of a name that only parents a live root, or that climbs out of the pins path, removes nothing, and a `stop` spelled with the `.lua` the runner drops takes the deployment down |
| `unload.sh` | `lunatik unload` leaves nothing under `/sys/fs/bpf/lunatik/` and no program on either device, for a program beside a kernel script and one with none, even while another pin holds a link; one that cannot detach a pin still removes the tree and exits 1, and one by a user other than root prints only the device's refusal |
| `undo.sh` | a run that fails at any step leaves no pin root, no runtime and nothing attached: one row per step, with the stimulus that fails it |
| `notarget.sh` | a run without `--dev=` for an XDP program fails before the runtime starts, with a message naming the option; so does a context for a script with no kernel side, and a name with a dot. A script with no object runs as it did before |
| `verifierlog.sh` | a program the verifier rejects makes `run` print the log with the Lua line and exit non-zero |
| `xdp compiled pass`/`drop`, `tc compiled pass`/`drop` | the `xdp` and `tc` suites' pass and drop cases from a compiled program, beside the C stubs rather than in place of them: the stubs are what exercises the kfunc, which no compiled program calls until phase 4 |

### Phase 4: the escape hatch

| Test | Proves |
|------|--------|
| `callback.sh` | a compiled program that calls `runtime(n)` reaches the callback, which reads `n` from `ctx:argument()` and sets a verdict the program returns |
| `miss.sh` | a call whose runtime is not loaded yields `nil`, and the program takes its default |
| `partition.sh` | `sniclassify` in Lua: the first packet of a flow calls Lua, the second is decided from the map, counted through an `rcu.table` delta |
| `report.sh` | the compiler's summary lists every call into Lua with its line |
| `nobtf.sh` | without module BTF the load fails naming the kfunc, and a program with no such call loads |

### Phase 5: the runtime library, strings and loops

| Test | Proves |
|------|--------|
| `library.sh` | an object linked with the runtime library loads, and a library call verifies inside a subprogram |
| `strcmp.sh` | a comparison against a string constant matches the interpreter over the corpus, including a prefix and an empty string |
| `strkey.sh` | `getstring` into a `c64` map key finds an entry written by the kernel script |
| `while.sh` | a `while` with a runtime bound terminates under `may_goto` and matches the interpreter |
| `iter.sh` | the same loop lowered to the iterator kfuncs on a kernel without `may_goto` |

### Phase 6: examples

| Test | Proves |
|------|--------|
| `example_filter.sh` | the SNI filter compiled whole blocks the listed host on the veth pair and passes another |
| `example_sniclassify.sh` | the classifier sets the priority from the map on a cached flow and from Lua on a new one |
| `example_speed.sh` | the benchmark's XDP event runs against the compiled filter; informational, not a gate |

## Conventions to follow

* skip, do not fail, when the kernel lacks a feature, the toolchain lacks a tool, or `lunatic`
  is not built, and say which;
* mark `dmesg` before the run, read only what came after, and `check_dmesg` at the end;
* clean up in a `trap`, and run the cleanup once up front as well;
* `lunatik run` exits 0 even when the script fails to load; assert on output, never on exit
  status. `lunatik run` with a program file exits non-zero when the load fails; that exit is the
  loader's, and the tests assert on the log text as well;
* one `.sh` per row above, wired into `tests/luaebpf/run.sh` and described in `tests/README.md`
  in the same commit as the code it tests.

## Verifying on more than one kernel

The suite runs on one kernel, and the emitted shapes depend on it: `may_goto` (v6.9), iterators
(v6.4), the tree's kfuncs (v6.4). Before a phase that adds a loop form or a kfunc call is called
done, run the suite on a kernel below the feature's release and confirm the skip and the refusal
paths, not only the green run on the development machine. `# Totals: pass:0 fail:0 skip:20` is
not a passing phase.

