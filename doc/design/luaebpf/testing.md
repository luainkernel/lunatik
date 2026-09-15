# Testing the Lua to eBPF compiler

Lunatik's tests are shell scripts emitting KTAP, driving a kernel Lua script and asserting on what
it prints to `dmesg` or on what userspace observes. A compiler is tested differently: by what it
emits, by what the verifier accepts, and by whether the compiled program computes what the
interpreted one does. `tests/xdp/` and `tests/tc/` are the closest existing suites (they build,
load and attach a program and drive a ping through it); `tests/bpf/` creates and reads pinned
maps from the shell. Read both, plus `tests/lib.sh`, before writing anything new.

Run everything with `sudo lunatik test`, one suite with `sudo lunatik test luaebpf`.

## What this suite needs that others do not

**A compiler on the host.** Every test compiles a program file with `lunatikc` at test time, on
the machine that runs it. `lunatikc` is built by `make` and installed next to `lunatik`; a
missing binary is a skip with a message naming `make`.

**Three oracles, in this order.**

1. *The verifier.* Every object the suite produces is loaded on the running kernel, through
   `bpftool prog load` into a pin under `/sys/fs/bpf/luaebpf/`, and a rejection is a failure that
   prints the log. This is the test that matters most: the design's claim is that every emitted
   shape is one the verifier accepts by construction.
2. *The interpreter.* A compiled program is run with `bpftool prog run` (`BPF_PROG_TEST_RUN`,
   XDP and TC only) over a packet file, and the same Lua function is run on the host under
   `lunatikc` with a `data`-like proxy over the same bytes. The program file's own body is what
   runs it: it calls each function it declares and writes the answer beside the object, so no
   compiler feature exists for the tests and the two oracles stay the host VM and the kernel's
   JIT. The verdicts must match on every packet of a corpus. Where the interpreted side raises
   (an out-of-bounds read, a division by zero), the compiled side must return the program's
   default verdict, and the test asserts that pairing, not equality.
3. *The wire.* The existing `xdp` and `tc` harness: a veth pair with its peer in a namespace, a
   ping, and a verdict that either blocks it or lets it through.

**Packet corpora, checked in.** From phase 2, small hex files under `tests/luaebpf/packets/`: an
ARP, an IPv4 ICMP echo, a TCP SYN to 443, a TLS ClientHello with an SNI, a truncated ClientHello.
Every differential test runs over the whole corpus so the failure paths are exercised, not only
the happy one. Phase 1 reads no packet, and its cases hand `prog run` the fourteen bytes
`BPF_PROG_TEST_RUN` demands of an XDP program.

**Proving the compiler discriminates.** Removing a mechanism from the emitter must fail the
suite. The emitter exposes a test hook, `LUAEBPF_DROP`, an environment variable the CLI does not
read, naming one mechanism to drop: `divisor` (the test before a division), `maygoto` (the header
a loop without a proven bound needs), `lineinfo` (the `.BTF.ext` records), `verdict` (the write to
`R0`), and from phase 2 the bounds check before a packet load. Each has a test that asserts the
verifier rejects the program, that the log lacks the Lua line, or that the arithmetic changes.
The library reads the variable from `/proc/self/environ`, since the host Lua carries no `os`.

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
| `host.sh` | the state `lunatikc` stands up for a program file's body: the standard libraries, `linux.xdp`, and `luaebpf.proto.read` on a known function; a host with no accessor makes `compile` raise a message naming it |
| `pass.sh` | the constant-verdict program compiles, loads, and `prog run` returns the verdict |
| `arith.sh` | every integer operator over a corpus of operand pairs, negative operands included, matches the interpreter (`//` and `%` floor semantics, shifts past 63) |
| `divzero.sh` | a division by zero returns the default verdict where the interpreter raises |
| `branch.sh` | `if`, `and`, `or`, `not` and every comparison over signed and unsigned edges match |
| `forconst.sh` | a `for` with constant bounds runs the right count; a zero-trip and a descending loop included |
| `forvar.sh` | a `for` whose bound is a program value verifies with `may_goto` and terminates; skips and asserts the refusal on a kernel without it |
| `call.sh` | a call to a file-declared function becomes a subprogram; the object carries one `func_info` per subprogram; a check that fails inside one takes the program's default verdict through the flag each frame raises in its caller's |
| `refuse.sh` | each refused construct (runtime table, closure, vararg, `pcall`, unknown global, tail call, `while`, `repeat`) fails with its message and line, and nothing is written; recursion and the five-argument call sit in `call.sh`, beside the calls they are the edges of |
| `lineinfo.sh` | the object's `.BTF.ext` names the `.lua` file, and a program broken by the test hook is rejected with a log that quotes the Lua line |
| `budget.sh` | the log's "processed N insns" line for the corpus programs, recorded and asserted under a ceiling, so a regression in emitted shape is caught before it reaches the 1M budget |

`refuse.sh` and `lineinfo.sh` are the ones that justify the design: a compiler that emits a
verifier-rejected shape for valid input is a bug, and the user must never see a bare `EINVAL`.

### Phase 2: proxies, context, packet and maps

| Test | Proves |
|------|--------|
| `packet.sh` | `getbyte`, `getuint16`, `getuint32` and `#` over the corpus match the interpreter's `data` reads |
| `bounds.sh` | an access one byte past `data_end` takes the default verdict; the same program with the bounds check dropped by the test hook is rejected |
| `ctx.sh` | `ctx.ingress_ifindex` and the `skb` fields read back what `prog run` supplies; an unknown field, a write the kernel refuses, and `ctx.data` are refused with their lines |
| `mapget.sh` | a map seeded by `bpftool map update` decides the verdict; a missing key is `nil` and an untested use is refused at compile time |
| `mapset.sh` | an update and a `nil` delete from the program are visible to `bpftool map lookup` |
| `struct.sh` | a `struct` value spec yields field access with the right offsets and widths |
| `btfview.sh` | `luaebpf.vmlinux` reports a kernel struct's size and its members' byte offsets as `bpftool btf dump` does, and drops the bitfields and unions a layout cannot describe |

### Phase 3: the loader

| Test | Proves |
|------|--------|
| `run.sh` | `lunatik run` on a script with a program file pins the maps, starts the runtime, attaches and pins the link, in that order (checked by what exists after a failure injected at each step) |
| `stop.sh` | `lunatik stop` leaves nothing under the script's pin root, and a second `run` after a killed one succeeds |
| `notarget.sh` | a run without `dev=` for an XDP program fails before the runtime starts, with a message naming the option |
| `xdp_compiled.sh`, `tc_compiled.sh` | the `xdp` and `tc` suites' pass and drop cases with a compiled program in place of the C stub |
| `verifierlog.sh` | a program the verifier rejects makes `run` print the log with the Lua line and exit non-zero |

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
| `example_speed.sh` | the phase 0 script runs against the compiled filter; informational, not a gate |

## Conventions to follow

* skip, do not fail, when the kernel lacks a feature, the toolchain lacks a tool, or `lunatikc`
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

