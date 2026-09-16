# Proposed API: Lua programs that become eBPF

This is a design proposal, not a specification. Names and shapes are open for review; the
constraints behind them (in `kernel-notes.md`) are not. Anything here that conflicts with a
verifier rule loses.

## Two files, one script

A script that has a compiled program keeps its kernel Lua where it is and adds a program file
beside it:

    examples/filter/sni.lua        the kernel script, as today: runs in the kernel Lua VM
    examples/filter/sni.bpf.lua    the program file: compiled by lunatikc into sni.bpf.o

`lunatikc bpf sni.bpf.lua` produces `sni.bpf.o`, a BPF ELF object that `bpftool prog load` accepts
like any other. The driver is the only part that touches a file: `luaebpf.compile(path)` returns
the object as a string and raises on a refusal, so a program that does not compile leaves no
object behind by construction rather than by a cleanup path. `make install` compiles every program
file it installs and puts the object beside the script, under `/lib/modules/lua/`, so
`lunatik run examples/filter/sni` finds `/lib/modules/lua/examples/filter/sni.bpf.o` the way the
kernel finds `sni.lua`.

A program file may exist without a kernel script (a program that never calls into Lua), and a
kernel script may exist without a program file (everything the tree runs today).

## The program file has two halves

The body of the program file is **compile-time Lua**. It runs once, on the host, inside
`lunatikc`, under the kernel's own Lua build: integer arithmetic, the 80-opcode set, the standard
libraries. Every value it computes is a constant of the program: a table of ports, a set of host
names, a map declaration, an offset. The functions it hands to a program constructor are the
**compiled half**: they run in the kernel, verified, and are held to the subset below.

    local xdp    = require("bpf.xdp")
    local action = require("linux.xdp")

    return xdp.program(function(ctx)
        return action.PASS
    end)

That is the whole of `tests/xdp/xdp_pass.bpf.c`, minus the call into Lua. `xdp.program` records
the function; `lunatikc` reads its bytecode, types it, emits it and writes the object. The
program returns an XDP verdict from `linux.xdp`, the same table the kernel scripts use.

The split mirrors the runtime model AGENTS.md describes: a kernel script's body runs once, in
process context, and its hooks run later under stricter rules. Here the body runs once at compile
time and the functions run in the verifier's world.

## What a compiled function may do

A compiled function is Lua where every value has a type the translator can prove:

| Allowed | Lowered to |
|---------|-----------|
| integers, booleans, `nil` as an absent value | registers, `ALU64` |
| `+ - * // % & \| ~ << >>`, unary `-` and `~`, comparisons | `ALU64` ops with Lua's floor semantics; a division tests its divisor |
| `if`, `and`, `or`, `not` | fused compare-and-jump |
| numeric `for` | a bounded loop when the bounds are constants, a `may_goto` header otherwise |
| `while`, `repeat` | a `may_goto` header, or the open-coded iterators on a kernel without one |
| `packet:getstring(at, len)` | `bpf_skb_load_bytes` or `bpf_xdp_load_bytes` into a buffer of the frame |
| `==` between such a string and a string constant | the read length against the constant's, then the bytes |
| calls to functions the program file declares | BPF-to-BPF calls; no recursion, four register arguments |
| the context, the packet, a map, a struct view | proxies (next sections) |
| `return` | the program's verdict |
| constants captured from the body: numbers, booleans, strings used as bytes, tables of constants | folded at compile time |

Everything else is a compile error naming the line: runtime tables and strings, closures created
at runtime, varargs, `pcall`, coroutines, metatables other than the proxies', a global that is
not one of the compile-time modules, a call through a value the translator cannot resolve, a tail
call, a boolean or a `nil` where arithmetic requires a number, and an `==` between values whose
types the translator cannot pin, since a register carries `false`, `nil` and `0` as one word.
Refusing is the normal outcome; the message says which line and why, in one line:

    sni.bpf.lua:31: 'host' may be nil here; test it first
    sni.bpf.lua:40: recursion through 'walk'
    sni.bpf.lua:52: a table constructor cannot run in the kernel; build it in the file body

## The context and the packet

`xdp.program` hands the function a context proxy. Its fields are the `struct xdp_md` fields the
verifier lets an XDP program read -- `ingress_ifindex` and `rx_queue_index`, neither writable --
at the offsets the running kernel's own BTF reports, and `ctx:packet()` is the packet as a proxy
with the method names of the `data` object a kernel script sees: `getbyte`, `getuint8`,
`getint8`, `getuint16`, `getint16`, `getuint32`, `getint32`, `getint64`, `getnumber`, `getstring`
and `#`. There is no `getuint64`, because the kernel object has none: a Lua integer is 64-bit
signed and an unsigned 64-bit value has no distinct representation, so a program that asks for it
is refused with the method's name. A field the struct does not carry is refused by name too, so
is a write the kernel would not take and one given something other than a number, and `ctx.data`
and `ctx.data_end` are refused as the packet bounds they are: the only Lua-meaningful thing to do
with them is their difference, which `#ctx:packet()` already spells. The same helper therefore
reads the same bytes on both sides:

    local function u16(packet, at)
        return packet:getbyte(at) << 8 | packet:getbyte(at + 1)
    end

is `examples/common/sni.lua`'s helper, unchanged, and it compiles.

`getstring(at, len)` answers the packet's bytes, read into a buffer of the reading function's
frame: a fixed region of 64 bytes, zeroed before the read, holding what the length asked for. The
compiler carries the region's offset and the Lua register carries the length, which is what makes
the comparison below exact. The length is the **program's own**: the emitter tracks an upper bound
on an integer register and narrows it where the program compares it against a constant, so

    local n = packet:getbyte(at)
    if n > 64 then return action.PASS end
    local host = packet:getstring(at + 1, n)

compiles, and a length the compiler cannot bound, or one bounded above 64, is an error naming the
line. Nothing is clamped: a compiled program that silently read fewer bytes than its interpreted
twin would be the disagreement the whole design exists to avoid. A buffer lives in the frame that
read it, so a compiled function neither returns a string nor takes one; its only uses are `==`
against a string constant, exact in length and bytes, and a `c<n>` map key. `getstring` with no
length -- the kernel object's "to the end" form -- is refused, since the bound would be the
packet's length, which is not a compile-time fact. An XDP program on a kernel that publishes no
`bpf_xdp_load_bytes` (below v5.18) is refused by the helper's name and the kernel's, since the
compiler runs on the machine that loads what it emits and can know.

The offset is an argument like any other, and an accessor called without one, or with one that
is not a number, is refused at its line. Every packet access carries a bounds check against
`data_end`, and tests its offset first against 65535 less its width, the last offset a read that
wide can start at, since the verifier refuses arithmetic between a packet pointer and a register
whose range it does not know. An access that fails either does not raise (there is nothing to
raise to): the function returns the program's **default verdict**, the type's safe answer
(`PASS` for XDP, `ACT_OK` for TC), overridable in the constructor:

    return xdp.program(function(ctx) ... end, {default = action.DROP})

Division by zero and every other check the interpreter would turn into an error take the same
path, from any frame. A subprogram returns to its caller rather than to the hook, so every
compiled function takes one argument beyond its own: a pointer to a word in its caller's frame. A
check that fails there stores a one through it and returns; the caller reads the word and takes
its own failure path, which is the default verdict in the program's own frame. That is the fifth
register argument, and why a compiled function takes four of its own. This is the compiled
analogue of what the trampoline does today, where a raising callback makes the kfunc return `-1`
and the stub falls back.

TC programs get `skb`, a proxy over the `__sk_buff` fields the kernel lets a program read --
`len`, `hash`, `ifindex` and `ingress_ifindex` -- plus `priority`, the one of them it also lets
a program write, and `skb:packet()`. `tc.program(fn, {egress = true})` puts the entry in
`tcx/egress` rather than `tcx/ingress`, which is how libbpf reads the attach point back.

## Maps

A program file declares the maps it uses with the specs `bpf.map` already takes in the kernel,
naming each one:

    local map = require("bpf.map")

    local flows = map.hash("flows", {key = "I4", value = "I4", entries = 65536})
    local hits  = map.array("hits", {key = "I4", value = "I8", entries = 1})

The name comes first, as it does in both siblings -- the kernel's `map.hash(pathname, ...)` opens
by path, and `xdp.program(fn, opts)` takes the subject then a table. A map needs one whether or
not a compiled function references it, since that is what the loader pins it under and what a
kernel script opens it by, so it cannot be recovered from a reference.

`bpf.map` on the host is the compile-time twin of `lib/bpf/map.lua`: the same spec strings, the
same names, and it produces BTF-defined maps in the object instead of opening pinned ones. What
the twin takes and the object cannot carry is refused at the declaration: a name BTF cannot spell,
an array keyed by anything but the four bytes the kernel creates one with, and a spec naming a
byte order other than the host's, which is the only one an eBPF load and store take. Inside
a compiled function a map is a table proxy with `bpf.map`'s semantics: indexing looks up,
assignment updates, assigning `nil` deletes. A value is a number, as the spec packs it; a key is
a number, or a run of bytes where the spec says `c<n>` and the key is a string `getstring` read.
Anything else is refused at the line that wrote it.

A `c<n>` key is what lets a host name key a map both sides share:

    local flows = map.hash("flows", {key = "c64", value = "I4", entries = 4096})

The emitter hands the helper the buffer's own address rather than copying it into a key slot, and
the width read is the spec's, not the buffer's, so a `c16` key reads sixteen of the sixty-four
bytes. The buffer was zeroed before the read, so its tail is the NUL padding `string.pack("c64",
name)` writes: the entry a kernel script wrote with the same spec is the entry the program finds.
A string bounded wider than the key spec is refused, naming both widths -- the bound is a
compile-time fact here, so there is nothing to truncate at run time -- and so is a spec wider
than the sixty-four bytes a read fills, which the helper would go past into the frame.

    local cached = flows[skb.hash]
    if cached then
        skb.priority = cached
        return action.ACT_OK
    end

`flows[key]` has the type "value or nil", and the translator refuses to use it as a number until
the function has tested it, which is what the verifier requires of the pointer underneath. The
test is `if cached then`, the form the verifier narrows the pointer at; `cached == nil` is
refused with the same message, since a comparison does not reach that narrowing. A `struct` spec
yields a proxy of fields rather than a scalar, read-only until a phase needs otherwise: writing
one, or a field of one, is refused at the line that does it. A value is read with the spec of the
map it came from, so a register that lookups in two different maps merge into is refused where it
is read rather than lowered against one of them.

The loader creates the maps and pins them under `/sys/fs/bpf/lunatik/<script>/<name>`, so the
kernel script opens the same map by that path with the API it has today:

    local map = require("bpf.map")

    local flows <close> = map.hash("/sys/fs/bpf/lunatik/examples/sniclassify/sni", "I4", "I4")
    flows[0x1234] = nil

This is the control plane the tree already has, with the map's owner moved from `bpftool map
create` to the program that reads it.

## Calling the kernel Lua runtime

The escape hatch is a call the program writes, at the point it chooses:

    local tc     = require("bpf.tc")
    local map    = require("bpf.map")
    local action = require("linux.tc")

    local HTTPS <const> = 443

    local flows = map.hash("flows", {key = "I4", value = "I4", entries = 65536})
    local lua   = tc.runtime()      -- the kernel script of the same name

    local function u16(packet, at)
        return packet:getbyte(at) << 8 | packet:getbyte(at + 1)
    end

    return tc.program(function(skb)
        local cached = flows[skb.hash]
        if cached then
            skb.priority = cached
            return action.ACT_OK
        end

        local packet = skb:packet()
        local ihl    = (packet:getbyte(14) & 0x0f) * 4
        local tcp    = 14 + ihl
        if packet:getbyte(23) ~= 6 or u16(packet, tcp + 2) ~= HTTPS or packet:getbyte(tcp + 13) & 0x08 == 0 then
            return action.ACT_OK
        end

        local payload = tcp + (packet:getbyte(tcp + 12) >> 4) * 4
        local verdict = lua(payload)
        if verdict == nil then
            return action.ACT_OK
        end
        flows[skb.hash] = skb.priority
        return verdict
    end)

That is `examples/sniclassify/classify.c`, in Lua. `tc.runtime(name)` names a kernel runtime by
the key the kfunc looks up; the call lowers to `bpf_luatc_run(key, key__sz, skb, &args,
sizeof(args))` (or #561's name once it lands), with each argument packed as a native 64-bit
integer in order -- not a `string.pack` format, so the kernel side reads `getint64(0)` and its
successors whatever the program passed. The kernel side is otherwise what it is today:
`tc.attach(callback)`, `ctx:argument():getint64(0)` for the first argument, `ctx:action` for the
verdict, `ctx:skb()` for the packet.

The default key is the script this program file belongs to: its path with the scripts root
(`/lib/modules/lua/`) and the `.bpf.lua` suffix removed, which is the name `lunatik run` registers
a script under. A program file compiled from inside its own directory has no root to strip and
gets a bare name, so one that cares names its runtime.

A verdict of `-1` from the kfunc becomes `nil`, and the program must test it -- `if v then` or
`v == nil` -- before reading it as a number, the way a map lookup is tested. `-1` is what the kfunc
answers for no runtime under that name, for a process-context one, and for a raise in the
callback, and a callback that sets `-1` itself is indistinguishable from all three: that is the
trampoline's own contract, not something the compiler adds.

The kfunc is the program type's, carried on the declaration beside the context, so `xdp.runtime`
and `tc.runtime` differ only in which namespace publishes them: a runtime declared through one
and called from the other program type still calls the right name.

The compiler reports every such call in its summary, with the line, so a program that calls Lua
on every packet is visible for what it is: the trampoline, generated.

A program that calls into the runtime needs the module's BTF (`make btf_install`), as every stub
in the tree does today, and needs the module loaded when the object is loaded, since that is where
libbpf resolves the kfunc. `lunatik run` loads every configured module when `/dev/lunatik` is
absent, which is the ordinary case; with the module gone the load fails with the message naming
the kfunc. A program that calls no runtime needs nothing from the modules.

## Loading and attaching

    sudo lunatik run examples/sniclassify/sni softirq dev=eth0
    sudo lunatik stop examples/sniclassify/sni

When `<script>.bpf.o` exists, `run`:

1. opens the object with libbpf, resolves the tree's kfuncs through the module BTF, creates the
   maps and pins them under `/sys/fs/bpf/lunatik/<script>/`;
2. starts the runtime, as today, so the kernel script finds its maps;
3. attaches every program the object declares to the target named on the command line (`dev=` for
   XDP and TC, `cgroup=` for cgroup programs, nothing for an LSM hook, which the program names
   itself) and pins each link at `/sys/fs/bpf/lunatik/<script>/<program>-link`. The suffix is a
   hyphen because bpffs reserves a dot in a pin name; a map name and a program name are both C
   identifiers, so nothing else keeps a link's pin and a map's apart in one root.

The order matters: the maps exist before the script opens them, and the program attaches after
the runtime is up, so its first packet finds a callback if it calls one. `stop` runs it backwards:
unpin the link (which detaches), stop the runtime, unpin the maps. A failure at any step undoes
the steps before it; a stale pin from a crashed run is removed by the next `run` of the same
script, since the root is the script's. A run of a script already running is refused before that
removal, since the root would be the live run's; where no runtime holds the root the run redeploys,
detaching the link it finds rather than leaving its release scheduled. Every teardown here removes
the pins the root holds and then the directory, never the tree below it: a root holds pins and
nothing else, so a name that merely parents other scripts' roots is not a deployment, and a `stop`
of one leaves them running.

What the command line owes is read off the object before anything is created: a program whose
section this phase cannot attach is refused by that section's name, an option the object does not
ask for is refused by its own, and a missing one names what it is missing.

The verifier's log is the error `run` prints when the load fails, and its `line_info` names the
Lua file and line. `lunatik list` is unchanged.

What the program declares and what the command supplies: the program type and the hook are
properties of the program (`xdp.program`, `tc.program{egress = true}`,
`lsm.program("bprm_check_security", ...)`); the device or cgroup is a property of the
deployment, and goes on the command line, as it does with `bpftool net attach` today.

## Program types

| Module | Program type | Context | Verdicts | Default |
|--------|-------------|---------|----------|---------|
| `bpf.xdp` | `BPF_PROG_TYPE_XDP` | `ctx` with `ctx:packet()` | `linux.xdp` | `PASS` |
| `bpf.tc` | `BPF_PROG_TYPE_SCHED_CLS`, tcx ingress or egress | `skb` with `skb:packet()` | `linux.tc` | `ACT_OK` |
| `bpf.lsm` | `BPF_PROG_TYPE_LSM` on a named hook | the hook's arguments as struct views | `0` or `-linux.errno.*` | `0` |
| `bpf.cgroup` | `BPF_PROG_TYPE_CGROUP_SOCK_ADDR` | `sock_addr` view | as `lsm`, translated to 1/0 by the emitter | allow |

`bpf.lsm` and `bpf.cgroup` follow the LSM epic, which owns their kfuncs and their kernel-side
`ctx`; the compiler gives them the same shape as XDP and TC once those exist. An LSM program can
be loaded sleepable, which the trampoline's callback never is (`kernel-notes.md`, "Sleeping").

## The compile-time environment

What the body of a program file can `require`:

* `bpf.xdp`, `bpf.tc`, later `bpf.lsm` and `bpf.cgroup`: the program constructors and their
  proxies;
* `bpf.map`: map declarations;
* `linux.*`: the autogen constant tables, loaded from the same files the kernel scripts use;
* `string`, `table`, `math`, `utf8`: the standard libraries the kernel build ships, for building
  constants;
* other program files or Lua modules on the host path, for shared helpers such as
  `examples/common/sni.lua`.

What a compiled function may reference from the body: constants (numbers, booleans, strings,
tables of those, folded), map proxies, runtime proxies, and other functions declared in the file.
A body value of any other type reached from a compiled function is a compile error at the line
that reaches it.

## Open questions for review

1. ~~Whether the deployment target belongs on the command line (`dev=eth0`) or in the program file
   with a command-line override.~~ Settled as proposed: the target is a `key=value` argument to
   `lunatik run`, and the object says which keys it asks for.
2. ~~Whether a map declared by a program file that a kernel script also declares (`map.hash(path,
   ...)`) should be checked at `run` for a matching spec, or left to the size check `bpf.map`
   already performs on open.~~ Settled as the second: the loader creates the map from the program
   file's declaration and the script's open checks its own spec against the map's sizes, so a
   mismatch raises where the script reads it.
3. ~~Whether `getstring` into a fixed buffer should be spelled as today (`packet:getstring(at,
   len)`, with `len` bounded by the buffer) or as a new method that names the bound.~~ Settled as
   proposed, with the bound the program's own rather than the buffer's: the name stays
   `getstring`, and a length the compiler cannot bound is a compile error naming the line rather
   than a clamp, since a clamp is a compiled program quietly disagreeing with its interpreted
   twin. `examples/common/sni.lua` still does not compile whole, for a reason of its own: it
   returns the string from a subprogram, and a buffer does not outlive its frame. Phase 6 owns
   that.
4. ~~Whether the per-argument marshalling of the runtime call (native 64-bit integers, in order)
   should instead take a `string.pack` format, so the kernel side can keep `getuint32(0)` where it
   has it.~~ Settled as proposed: native 64-bit integers in order, and no format argument. A
   kernel script written for a compiled caller reads `getint64(0)` and its successors.
5. ~~Whether `lunatik run` should refuse a program file without a kernel script, or run the program
   alone with an empty runtime.~~ Settled as proposed, with no runtime at all rather than an empty
   one: a program that calls no Lua needs no script, and an execution context given to such a run
   is refused, since there is nothing for it to apply to.

