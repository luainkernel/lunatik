# The Lua to eBPF compiler

How `bin/luaebpf` takes a program file to a program attached to a device, for whoever changes the
compiler. What the author of a program file reads is the guide page,
[Compiling Lua to eBPF](../../guide/08-luaebpf.md).

## The pipeline

The compiler and the loader run on the host, in the CLI's Lua, `lua5.5`. What reaches the kernel
is the object, through libbpf, and the verifier is the last check a program passes.

### The program file

A program file, `<name>.bpf.lua`, has two halves. Its body is compile-time Lua: it runs once, when
the file is compiled, and every value it computes, a table of ports, an offset, a map declaration,
is a constant of the program. The functions it hands to a program constructor, `bpf.xdp.program`
or `bpf.tc.program`, are the program, and their bytecode is what the compiler translates. The body
computes with the kernel's arithmetic, so a constant it leaves is the one a kernel script would
compute: `10 / 4` is `2` there too.

### One chunk, two builds of Lua

`lunatic`, the `luac` built from `lua/` with the kernel's configuration, compiles the program file,
and the CLI's Lua runs that chunk. It cannot load the chunk as `lunatic` writes it: the header
carries an integer `lua_Number`, and the opcodes and the metamethod events are numbered without
those `_KERNEL` leaves out, the opcodes of floats, `LOADF`, `DIV`, `DIVK`, `POW` and `POWK`, and the
events of `/` and `^`. Three modules bridge the two builds:

* `bytecode.c` prints, as a Lua table, what reading a chunk takes from the build that wrote it: each
  opcode's number and argument mode, the metamethod events, the instruction layout and the chunk
  format. `make` builds it twice, with `lunatic`'s configuration and with the CLI's, into
  `luaebpf.bytecode.kernel` and `luaebpf.bytecode.host`, so no opcode number is written in Lua.
* `undump.lua` reads a chunk field by field, as `loadFunction` in `lua/lundump.c` does, and rewrites
  one in another build's numbering: the CLI's header on `lunatic`'s chunk, and each opcode and
  metamethod event renumbered by name. The two headers are one size, and every opcode of the
  kernel's Lua is one of the CLI's, so nothing else in the chunk moves.
* `proto.lua` runs `lunatic -o -` on the file and loads the rewritten chunk. `proto.read` hands the
  translator a function's prototype, read from the function's own `string.dump` and numbered back
  as the kernel's Lua numbers its opcodes, so the translator reads the bytecode the body ran from,
  which is the bytecode the kernel's Lua would run.

A refusal names a file and a line, so `proto.read` takes only a function of a chunk loaded this way
with its source name. A function a module of the CLI's Lua defines, or one of a chunk `lunatic -s`
stripped, is refused: "a compiled function is defined in the program file or a kernel script it
requires, installed as source".

### What the body requires

The order in which `require` finds a module in the body is in
[Program files](../../guide/02-running-scripts.md#program-files). `compile`, in `init.lua`, builds
it: while the body runs, `package.path` is the compile-time modules in `bin/luaebpf/lib/` and
`package.cpath` is empty, a searcher `init.lua` adds finds the compiler's own `luaebpf.*` through
the host's path, and the last one, which `proto.lua` adds, loads a module under `/lib/modules/lua/`
through `lunatic`, as the program file is loaded. `linux.xdp` and `struct` come from there, and a function
a kernel script defines is compiled as one the program file defines.

### Programs and maps

A program constructor leaves each program in `programs.lua`: its function, its default verdict, its
name if the file gave one, the ELF section its kind names, `xdp`, `tcx/ingress` or `tcx/egress`,
from which libbpf reads the program type and the attach point, and its context: the kernel struct
the program reads, `xdp_md` or `__sk_buff`, the field each of its methods reads, the methods that
write, and the method that opens the packet. `bpf.map.hash`, `bpf.map.array` and `bpf.map.lru_hash`
check a map's spec and leave the map in `maps.lua`, and a table a compiled function reaches is a
map exactly when `maps.lua` holds it.

### Lowering

`emit.program`, in `emit/init.lua`, translates one program: its function, and every function that
function reaches, each compiled once for that program as a subprogram.
[The translator](#the-translator) is how.

### Instructions

`insn.lua` is the buffer the translator writes into. It holds records rather than bytes, so a jump
names a label placed later and a call names a function laid out afterwards, and every record
carries the Lua line it came from. `pack` resolves the jumps; a call to a subprogram and a
reference to a map keep the name the object relocates.

### The object

`write`, in `init.lua`, lays out the object with `elf.lua`, `btf.lua` and `strtab.lua`, in the
byte order of the kernel `lunatik.config` describes:

* each program's entry in the section its kind names, under a global symbol, and every subprogram
  in `.text`, under a local one, where libbpf resolves a call;
* `.maps`, each map BTF-defined: a struct of pointer-to-array members whose element counts libbpf
  reads as the map's type, entries, key size and value size, a `VAR` of that struct, and a
  `DATASEC` holding them;
* `license`, `Dual MIT/GPL`;
* `.BTF`, a `FUNC` and its `FUNC_PROTO` for each compiled function, every parameter a `long`, a
  program's result an `int` and a subprogram's a `long`, a program global and a subprogram static;
* `.BTF.ext`, each function's `func_info`, and the `line_info` that quotes the Lua line each
  instruction came from, which is how the verifier's log quotes the program file;
* `.symtab`, `.strtab`, and a relocation section for each section that calls a subprogram or names
  a map.

### The kernel it compiles for

`vmlinux.lua` reads the kernel's BTF, the file `lunatik bpf --btf=` names or else
`/sys/kernel/btf/vmlinux`, for the offset and the width of each context field a program reads, so
no offset is copied from a header; it reads the file in the byte order its magic says and refuses
one whose order is not the object's. Three facts come from `lunatik.config`, which `make` writes
from the kernel tree Lunatik is built against: the kernel's version, which says whether a loop can
take `may_goto`, 6.9 and later, whether the kernel has efficient unaligned access, which says
whether a read wider than a byte is compiled, and whether it is big-endian, which says the object's
byte order. A build host compiles for the kernel of the image it builds this way, with that tree's
config and that kernel's BTF. A kernel that publishes no BTF gets no object: `make install` leaves
the program files uncompiled there.

### The loader

`loader.c` is `luaebpf.loader`, a C module of the CLI's Lua over libbpf, 1.0 or later, and the half
of `lunatik run` that takes the object to the kernel. It opens the object with a buffer for the
verifier's log, gives each map a pin path under the script's root, loads the object, which creates
and pins the maps, attaches every program to the device, by XDP or by tcx as its section says, the
latter from libbpf 1.3.0, and pins each link; `detach` opens a pinned link and detaches it. What
`run`, `stop` and `unload` do with these is in
[Compiled programs](../../guide/02-running-scripts.md#compiled-programs).

### Building and installing

`make` builds `bin/lunatic`, the two bytecode tables and `bin/luaebpf/loader.so`. `make install`
puts `lunatic` beside `lunatik`, the compiler under the host's Lua path as `luaebpf/`, and the
loader under its C path, and then runs `lunatik bpf` over the program files of `examples/` and
`tests/`, but the `luaebpf` suite's, leaving each object beside its script, where `lunatik run`
looks for it ([Compiled programs](../../guide/02-running-scripts.md#compiled-programs)).

## The translator

### Types and the walk

A Lua register carries a type through the function besides its word, because Lua's truth cannot be
read off the bits: `0` is true, and `false` and `nil` are both stored as zero. A number, a boolean
and nil are words the kernel holds; the context, the packet, a map value the program has not tested
yet and a struct map value are pointers the kernel holds, read through their proxy; a table, a
function or a string the body computed, and the method a call on a proxy reads, are values only the
compiler holds. Each type is a bit the module that makes it declares, through `frame.type`, with
the classes `frame.lua`'s checks read: `word`, a value the kernel holds as a word, `proxy`, a pointer
read through its proxy, and `untested`, a word the program must test before the kernel reads it.

`emit/init.lua` walks a function's bytecode carrying an abstract state, the type of each register
and the value the compiler holds for it, if any. Each edge leaves its state at the instruction it
reaches, and where two paths meet, the join in `frame.lua` keeps the types of both and a value only
where both agree. A numeric `for` jumps backwards, so the walk runs again until no state widens, at
most 16 times, and the code of the last walk is the one kept; a function whose types do not settle
is refused: "the compiler did not settle on the types of this function".

A value the body computed becomes a constant where a compiled function reads it: an integer, a
boolean or nil is loaded into a register, a table, a function or a string stays with the compiler,
and a float is refused: "'half' is a float, which a compiled function cannot hold".

### Registers and the frame

Lua registers 0 to 3 live in R6 to R9, which a call preserves, and the others in the frame, so a
value survives a call without the translator tracking which are live. R0 to R5 hold what one
instruction's lowering computes. Each frame reserves four words: the flag a callee raises, the
address of its caller's flag, and a map key and a map value, which a helper takes by address. A
frame has 512 bytes, so a function uses at most 64 Lua registers, and one that needs more is
refused: "the function needs 520 bytes of stack, over the 512 eBPF allows".

### Where the interpreter would raise

A zero divisor, a read past the packet, a key or a value its map's spec cannot pack: where the
interpreter would raise, the compiled function jumps to its abort tail. In the program's own frame
the tail returns the program's default verdict. In a subprogram it stores a one through the address
its caller passed and sets R0, which the verifier reads on every path out, and the caller, which
reads the flag after every call, takes its own tail. A check that fails in any frame thus ends the
program with its default verdict.

### Calls

A call compiles its callee, a Lua function of the program file or of a kernel script it requires,
once per program, as a BPF-to-BPF subprogram, with the types of the arguments its first call passes;
a later call with other types or another count is refused: "'f' is called with a packet and
compiled with a number". The arguments go in R1 to R4 and the address of the caller's flag in the
register after them, so a function takes at most four: "a compiled function takes at most 4
arguments, not 5". An argument is a number or the packet: "argument #1 is a context, and a compiled
call passes numbers and packets". A call that closes a cycle is refused, "recursion through
'walk'", as the verifier refuses one. A callee answers one value, and Lua's nil fills every other
result a caller asks for.

### The lowerings

Each instruction is lowered by the module of `emit/` whose member carries its opcode's name, over
what `frame.lua` holds:

* `loads.lua`: `MOVE`, the `LOAD` opcodes, `GETUPVAL`, the table and field opcodes, `SELF` and
  `LEN`. A global or an upvalue resolves to the value the body left, a field of a table the
  compiler holds to that field's value, read when the function is compiled, and an index into a
  map to the map's helpers; a field of the context or of a struct map value goes to `context.lua`
  or `map.lua`, and a method call on a proxy is read back by `CALL`.
* `arithmetic.lua`: the arithmetic and bitwise opcodes and their forms with a constant, `UNM`,
  `BNOT` and `NOT`, with Lua's semantics over 64-bit integers. `MMBIN` and its kin, which the VM
  runs only when an operand is not a number, emit nothing, since an operand that is not a number is
  refused.
* `branch.lua`: the comparisons, `TEST`, `TESTSET` and `JMP`. A test the types decide is the jump
  or nothing; any other is a conditional jump. See [Branches](#branches).
* `forloop.lua`: `FORPREP` and `FORLOOP`, the numeric `for`, whose iterations are counted up front
  as `forprep` in `lua/lvm.c` counts them.
* `call.lua`: `CALL`, the returns, and the invocation of a subprogram. A `return` with no value, or
  with nil, in a program returns its default verdict, as a hook reads both alike.
* `context.lua`: a method of the context reads the field its constructor maps it to, after storing
  there the value a setter is called with, and `#skb` reads `len`.
* `packet.lua`: the reads of the packet proxy, each held to the packet's bounds, its length, and the
  dispatch of a method called on either proxy.
* `map.lua`: a lookup, an update and a delete through the kernel's helpers, the test that narrows
  a lookup, and the value or the struct field a lookup found.

An opcode none of them lowers is refused with the reason `emit/init.lua` keeps for it, a table
constructor's: "a table constructor cannot run in the kernel; build it in the file body".

`LUAEBPF_DROP`, an environment variable the CLI has no option for, names one mechanism the
compiler then leaves out, `divisor`, `bounds`, `maygoto`, `verdict` or `lineinfo`, so the suite
shows each one is what a case rests on ([testing.md](testing.md)).

## Limits

### What Lua writes that eBPF cannot run

eBPF has no heap, no call through a register and no recursion; its one exception, `bpf_throw`,
never returns to the program; and a compiled function calls no metamethod. So each of these is
refused at its line:

* a table constructor, and `..`: "'..' cannot be applied in a compiled function";
* a closure made at run time, an assignment to an upvalue or a global, a generic `for`, a
  to-be-closed variable and a `global` declaration;
* a vararg function, and a call with a variable number of values;
* a tail call, `return f(x)`, which is written `local r = f(x)` and `return r`: "a tail call cannot
  be compiled";
* `pcall`, the coroutines, and every other function written in C: "'pcall' is not a Lua function
  this program file declares";
* a call through a value the compiler cannot resolve, and recursion;
* a method call on a value that is not a proxy, and a function that returns more than one value;
* `nil` or a boolean in arithmetic, "attempt to perform arithmetic on a nil value", which Lua raises
  only when the line runs.

The verifier's rules behind them are in `kernel-notes.md`,
[Rules that shape the subset](kernel-notes.md#rules-that-shape-the-subset): no
recursion; no call through a register; three loop forms, a bounded loop the verifier walks, an
iterator and `may_goto`; `bpf_throw` unwinds one way; division and modulo by zero do not trap; no
heap.

### What eBPF offers that Lua does not reach

* A packet pointer. Lua has no pointer, so the packet is read through the methods of the kernel's
  `data` object, and the bounds are refused as numbers: "'data' is a packet bound, not a number;
  '#' on the packet is its length".
* An unsigned 64-bit integer. A Lua integer is signed, so the packet has no `getuint64`, "the packet
  has no method 'getuint64'", and every ordered comparison is signed.

### What the design gives up, and its way out

* A fifth argument. The register after the arguments carries the address of the caller's flag, so
  a function takes four; #2094 asks for five.
* Every name the kernel's objects do not publish. A proxy offers the names the object a kernel
  script reads offers, `luadata`'s reads, `luaxdp`'s and `luaskb`'s methods, since the interpreter
  running the same function is the oracle a compiled function is tested against
  ([testing.md](testing.md)): a read the kernel's `data` object lacks enters
  `luadata` first.
* A view from a layer. `skb:data(layer)` starts where the header its layer names does, which no
  compiled read reaches yet: "'data' with a layer is not compiled yet".
* A wide read the verifier would prove aligned, on a kernel without efficient unaligned access,
  where every read wider than a byte is refused (#2047): "'getuint16' reads more than a byte, and
  this kernel lacks efficient unaligned access".
* A `for` the compiler cannot bound, on a kernel before 6.9, which has no `may_goto`: "a 'for' the
  compiler cannot bound needs may_goto, which this kernel lacks".

The compiler does not price the verifier's own limits, the instructions it walks, the stack of a
chain of calls and the chain's depth ([Limits](kernel-notes.md#limits) in
`kernel-notes.md`): a program past them is refused at load, with the verifier's log, which
`lunatik run` prints and which quotes the Lua line.

## Branches

A comparison in Lua's bytecode is a test followed by a jump, which the VM takes when the condition
equals the opcode's `k`. Each one lowers to one conditional jump, taken under the same condition,
and an ordered one takes the signed jump, since an unsigned `BPF_JLT` reads a negative operand as
the larger. A comparison with a constant loads the constant into a register first.

Truth is read from a register's type, not from its bits. Lua calls `0` true and only `false` and
`nil` false, and a register holds `false`, `nil` and `0` as the same zero. So a number is true and
nil false when the function is compiled, and the test is the jump or nothing; a register whose
types are among boolean and nil is tested against zero at run time, since every zero it can hold is
false there. `if`, `and`, `or` and `not` lower over that reading, `TESTSET`'s copy of the value
included, and `not` of a register the types leave open is a one or a zero computed at run time.

An `==` between two registers of one type each is false where the types differ, as Lua makes it.
Between two numbers or two booleans it is a `BPF_JEQ` or a `BPF_JNE`; between two other values the
compiler holds, nil, a string, a table or a function, it is decided when the function is compiled.

A lookup is narrowed where the program tests it: `if v then` jumps on the pointer the helper
answered, reads the value on the branch that found it, and carries nil on the other, which is the
only place the verifier lets the pointer be read.

