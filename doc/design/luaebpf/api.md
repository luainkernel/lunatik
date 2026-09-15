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
the function; `lunatikc` reads its bytecode, types it, emits it, links the runtime library and
writes the object. The program returns an XDP verdict from `linux.xdp`, the same table the kernel
scripts use.

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
| `while`, `repeat` | `may_goto` headers (phase 5) |
| calls to functions the program file declares | BPF-to-BPF calls; no recursion, five register arguments |
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
verifier lets an XDP program read, and `ctx:packet()` is the packet as a proxy with the method
names of the `data` object a kernel script sees (`getbyte`, `getuint16`, `getuint32`,
`getstring`, `#`). The same helper therefore reads the same bytes on both sides:

    local function u16(packet, at)
        return packet:getbyte(at) << 8 | packet:getbyte(at + 1)
    end

is `examples/common/sni.lua`'s helper, unchanged, and it compiles.

Every packet access carries a bounds check against `data_end`. An access that fails it does not
raise (there is nothing to raise to): the function returns the program's **default verdict**, the
type's safe answer (`PASS` for XDP, `ACT_OK` for TC), overridable in the constructor:

    return xdp.program(function(ctx) ... end, {default = action.DROP})

Division by zero and every other check the interpreter would turn into an error take the same
path. This is the compiled analogue of what the trampoline does today, where a raising callback
makes the kfunc return `-1` and the stub falls back.

TC programs get `skb`, a proxy over the `__sk_buff` fields (`hash`, `priority` writable,
`ifindex`, `len`) and `skb:packet()`.

## Maps

A program file declares the maps it uses with the specs `bpf.map` already takes in the kernel:

    local map = require("bpf.map")

    local flows = map.hash{key = "I4", value = "I4", entries = 65536}
    local hits  = map.array{key = "I4", value = "I8", entries = 1}

`bpf.map` on the host is the compile-time twin of `lib/bpf/map.lua`: the same spec strings, the
same names, and it produces BTF-defined maps in the object instead of opening pinned ones. Inside
a compiled function a map is a table proxy with `bpf.map`'s semantics: indexing looks up,
assignment updates, assigning `nil` deletes.

    local cached = flows[skb.hash]
    if cached then
        skb.priority = cached
        return action.ACT_OK
    end

`flows[key]` has the type "value or nil", and the translator refuses to use it as a number until
the function has tested it, which is what the verifier requires of the pointer underneath. A
`struct` spec yields a proxy of fields rather than a scalar.

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

    local flows = map.hash{key = "I4", value = "I4", entries = 65536}
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
the key the kfunc looks up, defaulting to the script this program file belongs to; the call
lowers to `bpf_luatc_run(key, key__sz, skb, &args, sizeof(args))` (or #561's name once it lands),
with each argument packed as a native 64-bit integer in order. The kernel side is what it is
today: `tc.attach(callback)`, `ctx:argument():getint64(0)` for the first argument, `ctx:action`
for the verdict, `ctx:skb()` for the packet. A verdict of `-1` from the kfunc (no runtime under
that name, or a raise in the callback) becomes `nil`.

The compiler reports every such call in its summary, with the line, so a program that calls Lua
on every packet is visible for what it is: the trampoline, generated.

A program that calls into the runtime needs the module's BTF (`make btf_install`), as every stub
in the tree does today. A program that does not needs nothing from the modules.

## Loading and attaching

    sudo lunatik run examples/sniclassify/sni softirq dev=eth0
    sudo lunatik stop examples/sniclassify/sni

When `<script>.bpf.o` exists, `run`:

1. opens the object with libbpf, resolves the tree's kfuncs through the module BTF, creates the
   maps and pins them under `/sys/fs/bpf/lunatik/<script>/`;
2. starts the runtime, as today, so the kernel script finds its maps;
3. attaches the program to the target named on the command line (`dev=` for XDP and TC,
   `cgroup=` for cgroup programs, nothing for an LSM hook, which the program names itself) and
   pins the link under the same root.

The order matters: the maps exist before the script opens them, and the program attaches after
the runtime is up, so its first packet finds a callback if it calls one. `stop` runs it backwards:
unpin the link (which detaches), stop the runtime, unpin the maps. A failure at any step undoes
the steps before it; a stale pin from a crashed run is removed by the next `run` of the same
script, since the root is the script's.

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

1. Whether the deployment target belongs on the command line (`dev=eth0`) or in the program file
   with a command-line override. The proposal keeps it out of the source because a program file
   is installed once and attached wherever an operator says.
2. Whether a map declared by a program file that a kernel script also declares (`map.hash(path,
   ...)`) should be checked at `run` for a matching spec, or left to the size check `bpf.map`
   already performs on open.
3. Whether `getstring` into a fixed buffer should be spelled as today (`packet:getstring(at,
   len)`, with `len` bounded by the buffer) or as a new method that names the bound. The proposal
   keeps the name so `examples/common/sni.lua` compiles unchanged.
4. Whether the per-argument marshalling of the runtime call (native 64-bit integers, in order)
   should instead take a `string.pack` format, so the kernel side can keep `getuint32(0)` where it
   has it.
5. Whether `lunatik run` should refuse a program file without a kernel script, or run the program
   alone with an empty runtime. The proposal runs it alone; a program that calls no Lua needs no
   script.

