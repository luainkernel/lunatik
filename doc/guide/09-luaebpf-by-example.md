# Lua to eBPF by example

**Experimental**, as [Compiling Lua to eBPF](08-luaebpf.md) is.

What a compiled function computes, construct by construct. The table below says what Lua computes,
what the eBPF instruction alone would compute and what the compiler emits between the two. Each
section after it compiles a program file whose operands come from the packet, so that `lunatic`
folds none of them, lists the object with each instruction annotated, and traces one input to the
result. The rows of [The Lua a program may use](08-luaebpf.md#the-lua-a-program-may-use) link to
these sections.

## What the compiler emits

A construct the compiler lowers computes what the kernel's Lua computes, or is refused at its line.
Where the eBPF instruction alone computes something else, the compiler emits what lies between:

| Lua | Lua computes | The instruction alone | The compiler emits |
|-----|--------------|-----------------------|--------------------|
| `-7 // 2` | `-4`, the floor | `-3`: `BPF_SDIV` truncates | the quotient less one where the remainder is not zero and the signs differ, as `luaV_idiv` |
| `-7 % 2` | `1`, the divisor's sign | `-1`: `BPF_SMOD` truncates | the divisor added where the remainder is not zero and its sign is not the divisor's, as `luaV_mod` |
| `x // -1`, `x % -1` | `-x` and `0`, so `math.mininteger // -1` is `math.mininteger` | for `math.mininteger`, a divide error on x86-64 before Linux 6.12, whose verifier patches the instruction to give `math.mininteger` and `0`, as arm64 always gave | a test for -1, then a negation or a zero, as `luaV_idiv` and `luaV_mod` take it, so the signed division never meets that case |
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
| `return v`, the verdict | the kernel's Lua answers a value outside its type's actions, or a boolean, with the hook's fallback | `r0`, whose low 32 bits the kernel reads as an action, a boolean as 1 or 0 | `v` tested against the first and the last action, which takes the default verdict outside them; a boolean refused, and so is a known `v` outside them |

The shift pair stands for `BPF_MEMSX`, which the s390 JIT of 6.6 does not take. A read is of the
kernel's byte order on both sides: the kernel's `data` object reads one so, and a map spec of another
order is refused when the body declares it.

The sources are `lua/lvm.c`,
[`luaV_idiv`](https://github.com/luainkernel/lua/blob/74f1f100cb58a23b4ff7625a99715394540beba9/lvm.c#L812-L824),
[`luaV_mod`](https://github.com/luainkernel/lua/blob/74f1f100cb58a23b4ff7625a99715394540beba9/lvm.c#L832-L844),
[`luaV_shiftl`](https://github.com/luainkernel/lua/blob/74f1f100cb58a23b4ff7625a99715394540beba9/lvm.c#L866-L875)
and [`forprep`](https://github.com/luainkernel/lua/blob/74f1f100cb58a23b4ff7625a99715394540beba9/lvm.c#L223-L262);
[the eBPF instruction set](https://github.com/torvalds/linux/blob/v6.8/Documentation/bpf/standardization/instruction-set.rst),
for `BPF_SDIV`, `BPF_SMOD`, the shift mask, the zero divisor and `BPF_MEMSX`;
[bpf: Fix a sdiv overflow issue](https://github.com/torvalds/linux/commit/7dd34d7b7dcf9309fc6224caf4dd5b35bedddcb7),
for `math.mininteger` over -1; and `kernel-notes.md`,
[Rules that shape the subset](../design/luaebpf/kernel-notes.md#rules-that-shape-the-subset) and
[The packet a network program reads](../design/luaebpf/kernel-notes.md#the-packet-a-network-program-reads).

## Reading a listing

A listing is `llvm-objdump -d` of the object `lunatik bpf` writes, with the hexadecimal left out,
each jump given its target, and the Lua line each instruction came from. That line is in the
object's `.BTF.ext`, which `llvm-objdump` does not read: the verifier's log quotes the same lines,
and so does `bpftool prog dump xlated` of a loaded program, after the kernel has rewritten its
context reads. An `llvm-objdump` that predates the instructions Linux 6.6 added, LLVM 14's among
them, prints a signed division as an unsigned `/=` and a signed modulo as `<unknown>`; the
listings write them `s/=` and `s%=`.

The registers:

* `r1` holds the context when the program starts, and `r0` what it returns.
* `r6` to `r9` hold Lua registers 0 to 3, the function's first locals, and a call leaves them
  alone. Lua registers 4 and up live in the frame, at `r10 - 40`, `r10 - 48` and on down.
* `r10` is the frame. `r10 - 8` holds the flag a called function raises, `r10 - 16` the address of
  its caller's flag, and `r10 - 24` and `r10 - 32` the key and the value a map helper takes.
* `r1` to `r5` hold what one line computes.

Every listing ends with the instructions where the function stops: the default verdict, and the
exit. A program that returns a value it computes tests it first against the actions of its type,
two jumps to the default verdict, as [The verdict](#the-verdict) shows.

## The packet

A packet read, `p:getuint16(16)`, held to the bounds of the packet:

```Lua
local xdp = require("bpf.xdp")

return xdp.program(function(ctx)
	local p = ctx:packet()
	local length = p:getuint16(16)
	return length
end)
```

Byte 16 of an Ethernet frame that carries IPv4 is the total length of the IPv4 packet, two bytes
in network order.

```
     line 3: return xdp.program(function(ctx)
  0  r6 = r1                       ctx
     line 4: local p = ctx:packet()
  1  r8 = r6                       the packet: the context register
  2  r7 = r8                       p
     line 5: local length = p:getuint16(16)
  3  r9 = r7
  4  r1 = 16
  5  *(u64 *)(r10 -40) = r1
  6  r4 = *(u64 *)(r10 -40)        the offset
  7  r1 = *(u32 *)(r9 +0)          xdp_md.data
  8  r2 = *(u32 *)(r9 +4)          xdp_md.data_end
  9  if r4 > 65533 goto 20         past 65535 less the width: stops
 10  r1 += r4                      data + 16
 11  r4 = r1
 12  r4 += 2
 13  if r4 > r2 goto 20            past the end of the packet: stops
 14  r1 = *(u16 *)(r1 +0)          two bytes, in the kernel byte order
 15  r8 = r1                       length
     line 6: return length
 16  r0 = r8
 17  if r0 s< 0 goto 20            not an XDP action: stops
 18  if r0 s> 4 goto 20
 19  exit
     line 7: end)
 20  r0 = 2                        XDP_PASS, the default verdict
 21  exit
```

Instruction 13 is the test the verifier asks for before instruction 14 reads: it takes the load
only on the path where `data + 16 + 2` is not past `data_end`. Instruction 9 stops the program at
an offset no packet reaches, and at a negative one too, since the test is unsigned. A signed read,
`p:getint16(n)`, adds a shift left and an arithmetic shift right after the load, as
instructions 15 and 16 of [Floor division and modulo](#floor-division-and-modulo) do for a byte.
`#p` is `data_end` less `data`, both read from the context.

| Frame | Instructions | What they compute | The program returns |
|-------|--------------|-------------------|---------------------|
| 34 bytes, IPv4, total length `00 1c`, 28 | 13, 14, 18 | 18 is within 34; `00 1c` read little-endian is 7168, `0x1c00`, past `XDP_REDIRECT` | 2, `XDP_PASS` |
| 14 bytes, an Ethernet header alone | 13 | 18 is past 14 | 2, `XDP_PASS` |

The kernel's Lua reads the same 7168 from `p:getuint16(16)` on arm64 and x86. Read a byte at a
time, `p:getbyte(16) << 8 | p:getbyte(17)`, the length is 28 on every kernel.

## Arithmetic

`a + b`, `a - b`, `a * b` and the bitwise operators are one `ALU64` instruction each, as
instruction 30 of [Loops](#loops) adds a byte to `s`; `-a` is a subtraction from zero and `~a` an
exclusive or with -1. A constant that does not fit 32 bits signed is loaded whole, by `LD_IMM64`.
`//`, `%` and the shifts compute something else than the instruction alone, and the compiler emits
what lies between.

### Floor division and modulo

```Lua
local xdp = require("bpf.xdp")

return xdp.program(function(ctx)
	local p = ctx:packet()
	local a = p:getint8(14)
	local b = p:getint8(15)
	return a // b
end)
```

`a` and `b` are read from the packet, so `lunatic` folds nothing and the division is compiled. In
the kernel's Lua `a / b` is `a // b`, and it compiles to the same instructions.

```
     line 3: return xdp.program(function(ctx)
  0  r6 = r1                       ctx
     line 4: local p = ctx:packet()
  1  r8 = r6
  2  r7 = r8                       p
     line 5: local a = p:getint8(14)
  3  r9 = r7
  4  r1 = 14
  5  *(u64 *)(r10 -40) = r1
  6  r4 = *(u64 *)(r10 -40)        the offset
  7  r1 = *(u32 *)(r9 +0)          xdp_md.data
  8  r2 = *(u32 *)(r9 +4)          xdp_md.data_end
  9  if r4 > 65534 goto 56         past 65535 less the width: stops
 10  r1 += r4
 11  r4 = r1
 12  r4 += 1
 13  if r4 > r2 goto 56            past the end of the packet: stops
 14  r1 = *(u8 *)(r1 +0)           the byte
 15  r1 <<= 56                     its sign extended by a shift pair
 16  r1 s>>= 56
 17  r8 = r1                       a
     line 6: local b = p:getint8(15)
 18  to 32: the same read at 15
 33  r9 = r1                       b
     line 7: return a // b
 34  r1 = r8                       a
 35  r2 = r9                       b
 36  if r2 == 0 goto 56            Lua raises: stops
 37  if r2 == -1 goto 47           a // -1 is -a
 38  r3 = r1
 39  r4 = r1
 40  r4 s%= r2                     BPF_SMOD: the remainder, truncated
 41  r1 s/= r2                     BPF_SDIV: the quotient, truncated
 42  if r4 == 0 goto 50            exact: nothing to correct
 43  r3 ^= r2                      negative where the signs differ
 44  if r3 s>= 0 goto 50           the same signs: nothing to correct
 45  r1 += -1                      the floor: one less
 46  goto 50
 47  r3 = r1                       b is -1
 48  r1 = 0
 49  r1 -= r3                      0 - a, which wraps for math.mininteger
 50  *(u64 *)(r10 -40) = r1        the result, in Lua register 4
 51  r0 = *(u64 *)(r10 -40)
 52  r0 = r0
 53  if r0 s< 0 goto 56            not an XDP action: stops
 54  if r0 s> 4 goto 56
 55  exit
     line 8: end)
 56  r0 = 2                        XDP_PASS, the default verdict
 57  exit
```

The correction is Lua's `luaV_idiv`: the quotient less one where the remainder is not zero and the
signs differ. Bytes 14 and 15 at `f9 02`, so `a` is -7 and `b` is 2:

| Instructions | What they compute | Value |
|--------------|-------------------|-------|
| 9, 13 | 14 is under 65535, and 15 is within the 16 bytes | no jump |
| 14 to 17 | the byte `f9`, its sign extended | `a` is -7 |
| 33 | the byte `02` | `b` is 2 |
| 36, 37 | `b` is neither 0 nor -1 | no jump |
| 40 | -7 s% 2 | `r4` is -1 |
| 41 | -7 s/ 2 | `r1` is -3, what `BPF_SDIV` alone gives |
| 42 | the remainder is not 0 | no jump |
| 43, 44 | -7 ^ 2 is -5, negative: the signs differ | no jump |
| 45 | -3 - 1 | `r1` is -4 |
| 50 to 52 | `r0` is -4 | |
| 53 | -4 is below `XDP_ABORTED`, 0 | jump to 56: the program returns 2 |

Lua computes `-7 // 2` as -4, which is no XDP action, so the program returns its default verdict,
2, `XDP_PASS` ([The verdict](#the-verdict)). With `b` at 0, instruction 36 jumps to 56, and the
program returns 2 too.

`a % b` is the same program with `return a % b`; instructions 0 to 33 read `a` and `b` as above:

```
     line 7: return a % b
 34  r1 = r8                       a
 35  r2 = r9                       b
 36  if r2 == 0 goto 52            Lua raises: stops
 37  if r2 == -1 goto 45           a % -1 is 0
 38  r1 s%= r2                     BPF_SMOD: the remainder, truncated
 39  if r1 == 0 goto 46            exact: 0
 40  r3 = r1
 41  r3 ^= r2                      negative where the signs differ
 42  if r3 s>= 0 goto 46           the same signs: nothing to correct
 43  r1 += r2                      the remainder takes the sign of b
 44  goto 46
 45  r1 = 0                        b is -1
 46  *(u64 *)(r10 -40) = r1
 47  r0 = *(u64 *)(r10 -40)
 48  r0 = r0
 49  if r0 s< 0 goto 52            not an XDP action: stops
 50  if r0 s> 4 goto 52
 51  exit
     line 8: end)
 52  r0 = 2                        XDP_PASS, the default verdict
 53  exit
```

The correction is Lua's `luaV_mod`. With -7 and 2, instruction 38 gives -1, what `BPF_SMOD` alone
gives; -1 ^ 2 is negative, so instruction 43 adds 2, and the program returns 1, as Lua computes
`-7 % 2`.

### Shifts

The same program with `return a << n`, `n` read from byte 15; instructions 0 to 33 read `a` and
`n`:

```
     line 7: return a << n
 34  r1 = r8                       a
 35  r2 = r9                       n
 36  if r2 s< 0 goto 40            a negative count shifts right
 37  if r2 s>= 64 goto 44          64 or more: every bit shifted out
 38  r1 <<= r2
 39  goto 45
 40  if r2 s<= -64 goto 44         -64 or less: every bit shifted out
 41  r2 = -r2
 42  r1 >>= r2                     logical: Lua fills with zeros
 43  goto 45
 44  r1 = 0
 45  *(u64 *)(r10 -40) = r1
 46  r0 = *(u64 *)(r10 -40)
 47  r0 = r0
 48  if r0 s< 0 goto 51            not an XDP action: stops
 49  if r0 s> 4 goto 51
 50  exit
     line 8: end)
 51  r0 = 2                        XDP_PASS, the default verdict
 52  exit
```

This is Lua's `luaV_shiftl`. `BPF_LSH` alone masks the count to its low six bits, so `1 << 64`
would give 1, and `3 << -1`, a shift by 63, `math.mininteger`. Bytes 14 and 15 at `03 ff`, so `a`
is 3 and `n` is -1:

| Instructions | What they compute | Value |
|--------------|-------------------|-------|
| 36 | -1 is negative | jump to 40 |
| 40 | -1 is above -64 | no jump |
| 41 | the count negated | `r2` is 1 |
| 42 | 3 >> 1 | `r1` is 1 |
| 45 to 50 | `r0` is 1, `XDP_DROP` | the program returns 1 |

Lua computes `3 << -1` as 1. With 1 and 64, instruction 37 jumps to 44, and the program returns 0.
`a >> n` is `a << -n`, as in Lua: the count is negated first, and the same tests follow.

## Comparisons and truth

```Lua
local xdp    = require("bpf.xdp")
local action = require("linux.xdp").action

return xdp.program(function(ctx)
	local p = ctx:packet()
	local a = p:getint8(14)
	local small = a < 1
	local n = p:getbyte(15)
	if n and small then
		return action.DROP
	end
	return action.PASS
end)
```

`a < 1` is signed, as every comparison of Lua integers is. `n` is a number, and a number is true in
Lua, `0` included, so `n and small` is `small`: the compiler knows it from the type of `n`, and
tests `small` alone. Instructions 0 to 17 read `a` into `r8`.

```
     line 7: local small = a < 1
 18  r1 = r8                       a
 19  r2 = 1
 20  if r1 s< r2 goto 23           BPF_JSLT, the signed jump
 21  r9 = 0                        small is false
 22  goto 24
 23  r9 = 1                        small is true
     line 8: local n = p:getbyte(15)
 24  to 36: the read of byte 15, unsigned, so with no shift pair
 37  *(u64 *)(r10 -40) = r1        n, in Lua register 4
     line 9: if n and small then
                                   nothing for n: a number is true
 38  r1 = r9                       small
 39  r2 = 0
 40  if r1 == r2 goto 46           false: to the PASS
     line 10: return action.DROP
 41  r1 = 1                        XDP_DROP, read from linux.xdp
 42  to 45: r0 is 1, and the exit
     line 12: return action.PASS
 46  r1 = 2                        XDP_PASS
 47  to 50: r0 is 2, and the exit
     line 13: end)
 51  r0 = 2                        XDP_PASS, the default verdict
 52  exit
```

Bytes 14 and 15 at `ff 00`, so `a` is -1 and `n` is 0:

| Instructions | What they compute | Value |
|--------------|-------------------|-------|
| 20 | -1 s< 1 | jump to 23 |
| 23 | | `small` is true |
| 37 | the byte `00` | `n` is 0 |
| line 9 | `n` is a number, so true, 0 included | no instruction |
| 40 | `small` is not 0 | no jump |
| 41 to 45 | `r0` is 1 | the program returns `XDP_DROP` |

Lua takes both branches the same way. An unsigned `BPF_JLT` would read -1 as the largest value and
leave `small` false, and a test of `n` as C makes it would read 0 as false: either one would pass
the packet. A variable that holds a number on one path and nil on another has no such reading,
since the kernel holds `nil`, `false` and `0` as the same word, and a test or an `==` of it is
refused.

## Values of the body

```Lua
local xdp    = require("bpf.xdp")
local action = require("linux.xdp").action

local protocols = {tcp = 6, udp = 17}

return xdp.program(function(ctx)
	local p = ctx:packet()
	local protocol = p:getbyte(23)
	if protocol == protocols.udp then
		return action.DROP
	end
	return action.PASS
end)
```

`protocols` is a table the body built. The function reads `protocols.udp` when it is compiled, and
the program holds 17, the value the body left there. Instructions 0 to 15 read byte 23 into `r8`.

```
     line 9: if protocol == protocols.udp then
 16  r9 = 17                       protocols.udp, read at compile time
 17  r1 = r8                       protocol
 18  if r1 != r9 goto 22
     line 10: return action.DROP
 19  r9 = 1                        XDP_DROP
 20  r0 = r9
 21  exit
     line 12: return action.PASS
 22  r9 = 2                        XDP_PASS
 23  r0 = r9
 24  exit
     line 13: end)
 25  r0 = 2                        XDP_PASS, the default verdict
 26  exit
```

An IPv4 frame whose byte 23 is 17, UDP, returns 1, `XDP_DROP`; one whose byte 23 is 6, TCP, returns
2, and a 14-byte frame stops at the read and returns 2 too. An index the program computes,
`protocols[name]` with `name` read from the packet, has no value the compiler can read, and is
refused; so are `#protocols` and a write to the table.

## The verdict

```Lua
local xdp = require("bpf.xdp")

return xdp.program(function(ctx)
	local p = ctx:packet()
	local verdict = p:getbyte(14)
	return verdict
end)
```

Instructions 0 to 15 read byte 14 into `r8`, as [The packet](#the-packet) reads two bytes, their
bounds tests jumping to 20.

```
     line 6: return verdict
 16  r0 = r8
 17  if r0 s< 0 goto 20            below XDP_ABORTED: stops
 18  if r0 s> 4 goto 20            past XDP_REDIRECT: stops
 19  exit
     line 7: end)
 20  r0 = 2                        XDP_PASS, the default verdict
 21  exit
```

A verdict is one of the actions of its program type: `linux.xdp.action`, from 0, `XDP_ABORTED`, to
4, `XDP_REDIRECT`, and `linux.tc.action`, from -1, `TC_ACT_UNSPEC`, to 8, `TC_ACT_TRAP`, which a TC
program's two jumps test instead. The kernel's Lua holds a kernel script's callback to the same
range, in `luakfunc_action`, and answers any other value with the hook's fallback. The eBPF
instruction alone would hand the kernel the low 32 bits of `r0`, which it reads as an action
whatever they are, so the -4 of [Floor division and modulo](#floor-division-and-modulo) would reach
it as 4294967292, and an XDP value that is no action drops the packet.

| Byte 14 | Instructions | The program returns |
|---------|--------------|---------------------|
| `01` | 17, 18: 1 is within 0 to 4 | 1, `XDP_DROP` |
| `09` | 18: 9 is past 4 | 2, `XDP_PASS` |

A verdict the compiler knows takes no test, and one outside the actions is refused: `return 11`
gives "the verdict 11 is not an XDP action". So is a verdict that may be a boolean, which no
action is: `return p:getbyte(14) == 1` gives "the verdict may be a boolean here; return an action",
and is written `if p:getbyte(14) == 1 then return action.DROP end`, then `return action.PASS`.

## The context

```Lua
local tc     = require("bpf.tc")
local action = require("linux.tc").action

return tc.program(function(skb)
	local p = skb:data()
	local class = p:getint8(15)
	skb:priority(class)
	return action.OK
end)
```

The context of a TC program is the kernel's `__sk_buff`, read at the offsets its BTF gives: `len`
at 0, `priority` at 32, `data` at 76 and `data_end` at 80.

```
     line 4: return tc.program(function(skb)
  0  r6 = r1                       skb
     line 5: local p = skb:data()
  1  r8 = r6
  2  r1 = *(u32 *)(r8 +76)         __sk_buff.data
  3  r2 = *(u32 *)(r8 +80)         __sk_buff.data_end
  4  r2 -= r1                      the linear head
  5  r1 = *(u32 *)(r8 +0)          __sk_buff.len, the whole packet
  6  if r1 != r2 goto 37           not linear: stops
  7  r7 = r8                       p
     line 6: local class = p:getint8(15)
  8  to 21: the read of byte 15, its sign extended
 22  r8 = r1                       class
     line 7: skb:priority(class)
 23  *(u64 *)(r10 -40) = r6
 24  *(u64 *)(r10 -48) = r8
 25  r2 = *(u64 *)(r10 -48)        class
 26  r5 = r2
 27  r5 >>= 32
 28  if r5 != 0 goto 37            outside 0 to 4294967295: stops
 29  r1 = *(u64 *)(r10 -40)
 30  *(u32 *)(r1 +32) = r2         __sk_buff.priority
 31  r1 = *(u64 *)(r10 -40)
 32  r2 = *(u32 *)(r1 +32)         what skb:priority returns
 33  r9 = r2
     line 8: return action.OK
 34  r9 = 0                        TC_ACT_OK
 35  r0 = r9
 36  exit
     line 9: end)
 37  r0 = 0                        TC_ACT_OK, the default verdict
 38  exit
```

A frame whose byte 15 is 3 leaves its priority at 3 and returns 0. One whose byte 15 is `ff`
gives -1, which instruction 28 finds outside the range: the program stops before the store, and
the priority stays where it was. The default verdict here is `TC_ACT_OK` too, so only the priority
tells the two apart.

## Maps

```Lua
local map    = require("bpf.map")
local xdp    = require("bpf.xdp")
local action = require("linux.xdp").action

local seen = map.hash("seen", {key = "I4", value = "I8", entries = 256})

return xdp.program(function(ctx)
	local p = ctx:packet()
	local proto = p:getbyte(23)
	local n = seen[proto]
	if n then
		seen[proto] = n + 1
	else
		seen[proto] = 1
	end
	return action.PASS
end)
```

`seen[proto]` is a lookup, whose value is a number or nil until `if n then` tests it. The helpers
are called by number: 1 is `bpf_map_lookup_elem`, 2 `bpf_map_update_elem`. `llvm-objdump -r`
prints the map as a relocation, which libbpf fills in when it loads the object. Instructions 0 to
15 read byte 23 into `r8`.

```
     line 10: local n = seen[proto]
 16  r5 = r8                       proto
 17  r5 >>= 32
 18  if r5 != 0 goto 76            wider than I4: stops
 19  *(u64 *)(r10 -24) = 0
 20  *(u32 *)(r10 -24) = r8        the key, four bytes
 21  r1 = map seen                 two slots, relocated by libbpf
 23  r2 = r10
 24  r2 += -24                     the key, by address
 25  call 1                        bpf_map_lookup_elem
 26  r9 = r0                       a pointer to the value, or NULL
     line 11: if n then
 27  if r9 == 0 goto 31            NULL: n is nil
 28  r1 = *(u64 *)(r9 +0)          found: the value, eight bytes
 29  r9 = r1                       n
 30  goto 32
 31  goto 54                       the else branch
     line 12: seen[proto] = n + 1
 32  to 35: n + 1, kept in Lua register 5
 36  to 38: the key held to I4 again
 39  to 43: the key at r10 -24, the value at r10 -32
 44  to 49: r1 the map, r2 and r3 the key and the value, by address
 50  r4 = 0                        BPF_ANY: insert or replace
 51  call 2                        bpf_map_update_elem
 52  if r0 != 0 goto 76            the map refuses: stops
 53  goto 71
     line 14: seen[proto] = 1
 54  to 70: the same update, with the value 1
     line 16: return action.PASS
 71  to 75: r0 is 2, and the exit
     line 17: end)
 76  r0 = 2                        XDP_PASS, the default verdict
 77  exit
```

Instruction 28 reads the value only past instruction 27: the verifier refuses a read through a
pointer that may be NULL, and the compiler refuses to use `n` before `if n then` tests it. Four
frames, one after the other, over a map that starts empty:

| Frame | Byte 23 | Path | `seen` after |
|-------|---------|------|--------------|
| IPv4, TCP | 6 | 27 jumps: nil, so 54 to 70 store 1 | `{[6] = 1}` |
| the same again | 6 | 27 goes on: 1, so 32 to 52 store 2 | `{[6] = 2}` |
| ARP, 42 bytes | 0 | nil, so 1 is stored | `{[6] = 2, [0] = 1}` |
| 14 bytes | none | the read of 23 jumps to 76 before the lookup | unchanged |

Each run returns 2. A kernel script reads the same map with the kernel's `bpf.map`, as
`map.hash("/sys/fs/bpf/lunatik/<script>/seen", "I4", "I8")`. A `struct` value is read a field at
a time, by a load at the field's offset and width.

## Loops

```Lua
local xdp = require("bpf.xdp")

return xdp.program(function(ctx)
	local p = ctx:packet()
	local s = 0
	for i = 14, 17 do
		s = s + p:getbyte(i)
	end
	return s
end)
```

The compiler holds the three values, 14, 17 and 1, so it counts the passes when it compiles, as
Lua's `forprep` counts them when it runs: (17 - 14) // 1 is 3 more after the first. The loop is a
back edge, which the verifier walks pass by pass. In Lua 5.5 a loop takes three registers, the
count, the step and `i`: here `r9`, `r10 - 40` and `r10 - 48`. Instructions 0 to 2 take `ctx` and
`p`.

```
     line 5: local s = 0
  3  r8 = 0                        s
     line 6: for i = 14, 17 do
  4  to 8: the three values, as the bytecode loads them
  9  r9 = 3                        the count, known when compiled
 10  to 11: r10 -40 is 1           the step
 12  to 13: r10 -48 is 14          i
     line 7: s = s + p:getbyte(i)
 14  to 26: the read of byte i, held to the bounds of the packet
 27  to 29: s in r1, the byte in r2
 30  r1 += r2                      s + the byte
 31  r8 = r1                       s
     line 6: for i = 14, 17 do
 32  r1 = r9
 33  if r1 == 0 goto 41            no pass left
 34  r1 += -1
 35  r9 = r1
 36  to 39: i + the step
 40  goto 14                       the back edge
     line 9: return s
 41  r0 = r8
 42  if r0 s< 0 goto 45            not an XDP action: stops
 43  if r0 s> 4 goto 45
 44  exit
     line 10: end)
 45  r0 = 2                        XDP_PASS, the default verdict
 46  exit
```

Bytes 14 to 17 at `01 02 03 04` make four passes, i at 14, 15, 16 and 17, and `s` is 10, which is
no XDP action, so the program returns 2, `XDP_PASS`; at `00 01 01 02`, `s` is 4, and the program
returns 4, `XDP_REDIRECT`. A 16-byte frame stops at the third pass, whose read of byte 16 is past
the packet, and returns 2.

With a bound the program computes, `for i = 1, n do`, the count is computed when the loop starts,
with an unsigned division as `forprep` does, and the back edge passes through `may_goto`, which
the kernel takes from Linux 6.9: the kernel leaves the loop there once the budget it gives the
loop runs out (#1944). Compiled for an earlier kernel, the loop is refused: "a 'for' the compiler
cannot bound needs may_goto, which this kernel lacks".

## Calls

```Lua
local xdp = require("bpf.xdp")

local function half(n, d)
	return n // d
end

return xdp.program(function(ctx)
	local p = ctx:packet()
	local a = p:getint8(14)
	local b = p:getint8(15)
	local v = half(a, b)
	return v
end)
```

`half` is compiled once, as a BPF-to-BPF function in the section `.text`. Its arguments go in `r1`
and `r2`, and the address of the caller's flag in the register after them, `r3`. Instructions 0 to
33 of the program read `a` and `b`.

```
  the program, in the section xdp
     line 11: local v = half(a, b)
 34  to 37: r1 is a, r2 is b
 38  *(u64 *)(r10 -8) = 0          the flag, lowered
 39  r3 = r10
 40  r3 += -8                      its address, the third argument
 41  call half                     relocated by libbpf
 42  r1 = *(u64 *)(r10 -8)
 43  if r1 != 0 goto 50            raised: stops
 44  *(u64 *)(r10 -40) = r0        v
     line 12: return v
 45  to 49: r0 is v, tested against the actions, and the exit
     line 13: end)
 50  r0 = 2                        XDP_PASS, the default verdict
 51  exit

  half, in the section .text
     line 3: local function half(n, d)
  0  *(u64 *)(r10 -16) = r3        the address of the flag
  1  r6 = r1                       n
  2  r7 = r2                       d
     line 4: return n // d
  3  to 18: the floor division above, its zero test jumping to 22
 19  to 21: r0 is n // d, and the exit
     line 5: end
 22  r1 = *(u64 *)(r10 -16)
 23  *(u64 *)(r1 +0) = 1           the flag, raised
 24  r0 = 0                        the verifier reads r0 on every exit
 25  exit
```

Bytes 14 and 15 at `07 00`: `a` is 7 and `b` is 0. In `half` the zero test jumps to 22, which
raises the flag and returns; at 43 the program reads the flag and jumps to 50, so it returns 2,
`XDP_PASS`, as if the division had been in the program's own function. With -7 and 2, `half`
returns -4, which `half` may, since only the program's own `return` is a verdict; -4 is no XDP
action, so the program returns 2.

The call returns to the program, which reads the flag before it goes on. `return half(a, b)` would
be a tail call, which Lua runs without coming back, and is refused: "a tail call cannot be
compiled".

