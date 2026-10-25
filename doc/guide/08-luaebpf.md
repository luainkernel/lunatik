# Compiling Lua to eBPF

**Experimental.** The compiler and what a program file reaches through it, `lunatik bpf`,
`lunatik run --dev`, the modules a program file's body requires and the part of Lua it compiles,
may change in a minor release.

`lunatik bpf` compiles a program file into a BPF ELF object, and `lunatik run` loads it, as
[Program files](02-running-scripts.md#program-files) and
[Compiled programs](02-running-scripts.md#compiled-programs) describe. This page is the part of
Lua it compiles, and how its translation keeps Lua's semantics where the eBPF instruction computes
something else. How the compiler is built is in [compiler.md](../design/luaebpf/compiler.md), the
decisions behind it and the kernel references it rests on are in the
[design notes](../design/luaebpf/README.md), and its code is in [bin/luaebpf](../../bin/luaebpf).

## The translation

A construct the compiler lowers computes what the kernel's Lua computes, or is refused at its line.
Where the eBPF instruction alone computes something else, the compiler emits what lies between:

| Lua | Lua computes | The instruction alone | The compiler emits |
|-----|--------------|-----------------------|--------------------|
| `-7 // 2` | `-4`, the floor | `-3`: `BPF_SDIV` truncates | the quotient less one where the remainder is not zero and the signs differ, as `luaV_idiv` |
| `-7 % 2` | `1`, the divisor's sign | `-1`: `BPF_SMOD` truncates | the divisor added where the remainder is not zero and its sign is not the divisor's, as `luaV_mod` |
| `x // -1`, `x % -1` | `-x` and `0`, so `math.mininteger // -1` is `math.mininteger` | the same, where the overflow of `math.mininteger` over -1 wraps, as the instruction set says it does | a test for -1, then a negation or a zero, as `luaV_idiv` and `luaV_mod` take it, so the signed division never meets that overflow |
| `x // 0`, `x % 0` | raises | `0` and `x` | a test of the divisor, which takes the default verdict |
| `1 << 64` | `0` | `1`: the count is masked to 63 | the count tested against 64 and -64, past which the result is zero |
| `1 << -1` | `0`: a negative count shifts the other way | `math.mininteger`: -1 masked is 63 | a negative count negated into the other shift; `x >> n` is `x << -n`, as in Lua |
| `x & 0xffffffff` | the low 32 bits of `x` | `x`: a 32-bit immediate, sign-extended, reads -1 | the constant in a register, by a `MOV` of its immediate where it fits 32 bits and by `LD_IMM64` otherwise |
| `x + y`, `x - y`, `x * y`, `-x`, `~x`, the bitwise operators | the result wrapped to 64 bits | the same | one `ALU64` instruction; `-x` a subtraction from zero, `~x` an exclusive or with -1 |
| `x < 1` with `x` at -1 | `true` | `false` under `BPF_JLT`, which reads -1 as the largest value | the signed jump, `BPF_JSLT`, and its kin for `<=`, `>` and `>=` |
| `if n then`, `n` a number at `0` | taken: `0` is true | not taken: the word is zero | the jump or nothing, from the register's type ([Branches](../design/luaebpf/compiler.md#branches)) |
| `for i = 1, n, s` | the iterations counted up front, so the loop never passes `n` by overflowing | a back edge, which the verifier walks iteration by iteration or refuses | the count as `forprep` computes it, with an unsigned division; a bounded loop where the compiler holds the three values, a `may_goto` header otherwise |
| `for` with a step of `0` | raises | `BPF_DIV` by zero gives a count of 0, one pass through the body | a step the compiler holds refused, "'for' step is zero", and one the program computes tested, which takes the default verdict |
| `f(x)` | the callee's value, and its raise | a call, which answers R0 and nothing else | the arguments in R1 to R4, the address of the caller's flag after them, and the flag read after the call |
| `p:getint16(n)` | two bytes at `n`, signed; raises past the packet | a load the verifier refuses until the program tests the end | the offset tested unsigned against 65535 less the width, the end against `data_end`, and the sign extended by a shift left and an arithmetic shift right, where `BPF_MEMSX` would extend it |
| `#p` | the bytes the `data` object views | no instruction: the context holds the two bounds | `data_end` less `data`, both read from the context |
| `skb:data()` on an skb that is not linear | raises in a tc callback | `data_end` ends the linear head, short of the packet | `len` compared with the head's length, which takes the default verdict where they differ |
| `skb:priority(v)` | raises outside 0 to `U32_MAX` | a four-byte store keeps the low 32 bits | a value the compiler holds checked against the field's width, and one the program computes tested, which takes the default verdict |
| `m[k]` | the value, or nil | the helper answers a pointer, or NULL, which the verifier lets the program read only past a test | the helper, and a value typed "value or nil" until `if v then` reads it, on the branch that found it |
| `m[k] = v`, `m[k] = nil` | the kernel's `bpf.map` raises when the map refuses the update, or refuses the delete for any reason but an absent key | the helper's return code | the helper, and the default verdict on any code but zero, or `-ENOENT` from a delete |
| `m[k]` with `k` outside the key's spec | `string.pack` raises | a store that keeps the low bytes | a key the compiler holds packed when the function is compiled, and one the program computes tested, which takes the default verdict; a value alike |
| `v.field` of a struct value | the field the codec decodes | a load the verifier refuses until the program tests the lookup | a load at the field's offset and width, the sign extended where the field is signed |

The shift pair stands for `BPF_MEMSX`, which the s390 JIT of 6.6 does not take. A read is of the
kernel's byte order on both sides: the kernel's `data` object reads one so, and a map spec of another
order is refused when the body declares it.

The sources are `lua/lvm.c`,
[`luaV_idiv`](https://github.com/luainkernel/lua/blob/74f1f100cb58a23b4ff7625a99715394540beba9/lvm.c#L812-L824),
[`luaV_mod`](https://github.com/luainkernel/lua/blob/74f1f100cb58a23b4ff7625a99715394540beba9/lvm.c#L832-L844),
[`luaV_shiftl`](https://github.com/luainkernel/lua/blob/74f1f100cb58a23b4ff7625a99715394540beba9/lvm.c#L866-L875)
and [`forprep`](https://github.com/luainkernel/lua/blob/74f1f100cb58a23b4ff7625a99715394540beba9/lvm.c#L223-L262);
[the eBPF instruction set](https://github.com/torvalds/linux/blob/v6.8/Documentation/bpf/standardization/instruction-set.rst),
for `BPF_SDIV`, `BPF_SMOD`, the shift mask, the zero divisor and `BPF_MEMSX`; and `kernel-notes.md`,
[Rules that shape the subset](../design/luaebpf/kernel-notes.md#rules-that-shape-the-subset) and
[The packet a network program reads](../design/luaebpf/kernel-notes.md#the-packet-a-network-program-reads).

## Where a compiled function parts from Lua

Each place a compiled function would answer otherwise than Lua is a refusal at its line, with the
reason the bits cannot settle it:

* An `==`, or a truth test, on a register a join left with several types: "a value cannot be
  compared with a number here", "a value has no truth value in a compiled function". Lua decides it
  from the value's type when it runs, and the register's word holds `false`, `nil` and `0` as one.
* An ordered comparison of a value that is not a number: "attempt to compare a context with a
  number". Lua raises only when the line runs, and the compiler refuses when it compiles.
* An `==` with nil on a lookup: "'flows' may be nil here; test it first". The compiler narrows a
  lookup only where a truth test reads it, `if v then` or `if not v then`, and the same message
  refuses any other use of a lookup the program has not tested.
* A register two maps' lookups merged into, read as a value: "a map value here comes from more than
  one map". The word is a pointer into one map or the other, and which one decides how its value
  is read.
* A program's verdict that may be nil: "the verdict may be nil here; test it first". A nil verdict
  is the default one, and the register holds nil and `0` as one word.
* A jump backwards, a `while`, a `repeat` or a backward `goto`: "'while' and 'repeat' are not
  compiled yet".

Two places where master answers otherwise are open defects: a `for` under a `may_goto` header
leaves the loop with what it held once the kernel's budget runs out (#1944), and a program's
verdict outside the hook's actions reaches the kernel as it is (#1945).

