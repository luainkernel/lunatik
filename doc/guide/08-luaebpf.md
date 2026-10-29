# Compiling Lua to eBPF

**Experimental.** The compiler and what a program file reaches through it, `lunatik bpf`,
`lunatik run --dev`, the modules a program file's body requires and the part of Lua it compiles,
may change in a minor release.

A program file is a Lua file whose functions become eBPF programs, which the kernel runs natively
on each packet a device receives or sends. `lunatik bpf` compiles it on the host,
`lunatik run --dev` attaches it, and a map it declares is shared with the kernel scripts. This page
is for the author of a program file, who knows Lua: what a program computes, when it stops and when
it is refused. [Lua to eBPF by example](09-luaebpf-by-example.md) lists what each construct
compiles to, and how the compiler is built is in its [design notes](../design/luaebpf/compiler.md).

## A first program

This program counts the IPv4 packets that reach a device, by protocol, in a map a kernel script
reads.

`protocols.bpf.lua`:

```Lua
local map    = require("bpf.map")
local xdp    = require("bpf.xdp")
local action = require("linux.xdp").action

local ETHERTYPE <const> = 12 -- 0x0800 for IPv4, in network order
local PROTOCOL  <const> = 23 -- the protocol byte of the IPv4 header

local counts = map.array("counts", {key = "I4", value = "I8", entries = 256})

return xdp.program(function(ctx)
	local p = ctx:packet()
	if p:getbyte(ETHERTYPE) == 0x08 and p:getbyte(ETHERTYPE + 1) == 0x00 then
		local protocol = p:getbyte(PROTOCOL)
		local n = counts[protocol]
		if n then
			counts[protocol] = n + 1
		end
	end
	return action.PASS
end)
```

The file has two parts. Its body, every line outside the function, runs once, on the host, when
the file is compiled: it declares the map `counts` and the program. The function is the program:
it is compiled to eBPF and runs in the kernel on each packet. It returns `XDP_PASS`, so every
packet goes on to the network stack.

Compile it into place and attach it to a device:

```Shell
sudo lunatik bpf -o /lib/modules/lua/protocols.bpf.o protocols.bpf.lua
sudo lunatik run --dev=eth0 protocols
```

`lunatik run` creates the map and pins it at `/sys/fs/bpf/lunatik/protocols/counts`, where a
kernel script opens it with the kernel's `bpf.map`. `lunatik -e` runs one such chunk, which prints
the TCP and the UDP packets counted so far:

```Shell
sudo lunatik -e 'local map = require("bpf.map")
local counts <close> = map.array("/sys/fs/bpf/lunatik/protocols/counts", "I4", "I8")
return counts[6], counts[17]'
```

A frame that says IPv4 but is shorter than 24 bytes has no byte 23: its read stops the program,
which returns its default verdict, `XDP_PASS`, and counts nothing. The lookup and the update are
two steps, so two CPUs that count the same protocol at once can lose one of the increments.

```Shell
sudo lunatik stop protocols
```

## What a program returns

```
                       a packet on eth0
                              |
                              v
  +------------------------------------+     +----------------------------+
  | the program, eBPF, in the kernel   |     | a kernel script, Lua       |
  |   p = ctx:packet()   the bytes     |     |                            |
  |   n = counts[k]      a lookup      | map |   counts[k] reads what     |
  |   counts[k] = n + 1  an update ----+-----+-> the program wrote        |
  |   return action.PASS               |     |                            |
  +-----------------+------------------+     +----------------------------+
                    |
                    | the low 32 bits of the value it returns
                    v
  XDP  PASS DROP TX REDIRECT ABORTED act as named; any other value
       drops the packet, and the kernel warns once in its log
  TC   OK SHOT REDIRECT act as named; any other value decides nothing,
       and the packet goes on

  where Lua would raise, at a read past the packet or x // 0, the
  program stops and returns its default verdict
```

A program returns its verdict, which tells the kernel what to do with the packet: a value of
`linux.xdp.action` in an XDP program, of `linux.tc.action` in a TC one. The kernel reads the low
32 bits of the value the function returns.

* In an XDP program, `PASS`, `DROP`, `TX`, `REDIRECT` and `ABORTED` act as the kernel defines
  them. Any other value drops the packet, and the kernel warns once, in its log, of an illegal XDP
  return value.
* In a TC program, `OK` lets the packet go on, `SHOT` drops it and `REDIRECT` redirects it. Any
  other value decides nothing: `UNSPEC` hands the packet to the next TC program on the device, and
  every other value, the rest of `linux.tc.action` included, skips those programs; either way the
  packet then goes on, through the device's tc filters if it has any.
* A boolean is returned as 1 or 0: `return p:getbyte(23) == 6` returns `XDP_DROP` for TCP and
  `XDP_ABORTED` for any other protocol (#1945).

A `return` with no value, or with `nil`, returns the default verdict, and so does a program that
stops. A verdict that may be nil is refused: "the verdict may be nil here; test it first". The
default verdict is `XDP_PASS` or `TC_ACT_OK`, unless the constructor names another:

```Lua
return xdp.program(filter, {default = action.DROP})
```

With the default, a packet the program cannot read goes through; a filter that must drop what it
cannot check names `DROP`. A value the program computes reaches a kernel script through a map,
not through the verdict.

## When a program cannot be compiled or computed

```
  filter.bpf.lua           filter.bpf.o             a packet
        |                        |                        |
        | lunatik bpf            | lunatik run --dev      | on the device
        v                        v                        v
  REFUSED                  REFUSED AT LOAD          STOPS
  lunatik: file:line:      the verifier log,        the default verdict
  reason; exit 1, no       which quotes the Lua     for that packet;
  object written           line; exit 1, nothing    nothing logged
                           attached

  what the subset does     a program past the       where Lua would raise:
  not compile, and a       limits of the verifier,  x // 0, a read past
  value the compiler       most often a loop of     the packet, an update
  sees is wrong            many passes              the map refuses
```

Where Lua would raise an error, and where the part of Lua the compiler takes ends, a program file
fails in one of three places.

* **Refused.** `lunatik bpf` prints `lunatik: <file>:<line>: <reason>`, exits 1 and writes no
  object. What the subset does not compile is refused, and so is an operation the compiler can see
  is wrong because it knows the value: a `for` step of 0, a map key or value its spec cannot pack,
  a `skb:priority` outside 0 to 4294967295.
* **Refused at load.** The kernel's verifier checks the object again when `lunatik run` loads it.
  A program past the verifier's limits, most often a loop of many passes, is refused there:
  `lunatik run` prints the verifier's log, which quotes the Lua lines, exits 1 and leaves nothing
  attached.
* **Stops.** In the kernel, on a packet, the program returns its default verdict at once, and
  nothing is logged (#2098). A program stops at a read past the packet, a division or a modulo by
  0, a `for` step of 0 it computed, a map key or value its spec cannot pack, a map update or delete
  the map refuses, a `skb:data()` of an skb that is not linear, a `skb:priority` it computed outside
  0 to 4294967295, and in a function it called that stops. A division by a 0 the compiler knows is
  not refused: the program stops on every packet that reaches it.

## The Lua a program may use

A compiled function computes what the kernel's Lua computes, or stops, or is refused. "Stops"
means the program returns its default verdict; "refused" means `lunatik bpf` refuses the file at
that line. Each construct links to its listing.

| You write | The program gives | It stops when | It is refused when |
|-----------|-------------------|---------------|--------------------|
| [`a // b`, `a / b`](09-luaebpf-by-example.md#floor-division-and-modulo) | the quotient, rounded towards minus infinity: `-7 // 2` is `-4` | `b` is 0 | an operand is not a number |
| [`a % b`](09-luaebpf-by-example.md#floor-division-and-modulo) | the remainder, with the sign of `b`: `-7 % 2` is `1` | `b` is 0 | an operand is not a number |
| [`a + b`, `a - b`, `a * b`, `-a`](09-luaebpf-by-example.md#arithmetic) | the result, wrapped around 64 bits: `math.maxinteger + 1` is `math.mininteger` | never | an operand is not a number |
| [`a & b`, `a \| b`, `a ~ b`, `~a`](09-luaebpf-by-example.md#arithmetic) | the bits, over 64 bits | never | an operand is not a number |
| [`a << n`, `a >> n`](09-luaebpf-by-example.md#shifts) | a logical shift; `n` of 64 or more gives 0, a negative `n` shifts the other way: `3 << -1` is `1` | never | an operand is not a number |
| [`a < b`, `a <= b`, `a > b`, `a >= b`](09-luaebpf-by-example.md#comparisons-and-truth) | a signed comparison: `-1 < 1` is `true` | never | an operand is not a number |
| [`a == b`, `a ~= b`](09-luaebpf-by-example.md#comparisons-and-truth) | `false` between values of two types | never | an operand may hold two types, a number on one path and nil on another |
| [`if v then`, `and`, `or`, `not`](09-luaebpf-by-example.md#comparisons-and-truth) | `0` is true; only `nil` and `false` are false | never | `v` may be a number on one path and nil or a boolean on another |
| [`t.x`, `t[1]`, `t` a table of the body](09-luaebpf-by-example.md#values-of-the-body) | the value the body left there | never | the index is computed; `#t`; a write to `t` |
| [`for i = a, b, s do`](09-luaebpf-by-example.md#loops) | the passes Lua makes | `s` is 0 | `s` is a known 0; a bound or a step is computed, before Linux 6.9 ([Loops](#loops)) |
| [`local v = f(x)`](09-luaebpf-by-example.md#calls) | the value `f` returns | `f` stops | [Calls](#calls) says |
| [`return f(x)`](09-luaebpf-by-example.md#calls) | | | always: a tail call |
| [`p:getuint16(n)` and the other reads](09-luaebpf-by-example.md#the-packet) | the bytes at `n`, in the kernel's byte order | the read passes the end of the packet | [The packet](#the-packet) says |
| [`#p`](09-luaebpf-by-example.md#the-packet) | the length of the packet | never | never |
| [`skb:data()`](09-luaebpf-by-example.md#the-context) | the packet | the skb is not linear | a layer is given |
| [`skb:priority(v)`](09-luaebpf-by-example.md#the-context) | `v`, stored as the packet's priority | `v` is outside 0 to 4294967295 | a known `v` is outside it |
| [`m[k]`](09-luaebpf-by-example.md#maps) | the value, or nil | `k` does not fit the key's spec | a known `k` does not fit it; the value is used before `if v then` tests it |
| [`m[k] = v`, `m[k] = nil`](09-luaebpf-by-example.md#maps) | the entry inserted or replaced, or deleted | the map refuses; `k` or `v` does not fit its spec | a known `k` or `v` does not fit it |
| [`v.field`, `v` a struct value](09-luaebpf-by-example.md#maps) | the field | never | the field does not exist; a write |
| [`return v`, the verdict](09-luaebpf-by-example.md#the-verdict) | its low 32 bits; `true` as 1, `false` as 0 | never | `v` may be nil |

Besides what the table refuses, these are refused: a table constructor, `..`, a closure, an
assignment to an upvalue or a global, a generic `for`, `while`, `repeat`, a `goto` backwards, a
vararg function and a to-be-closed variable. [Messages](#messages) lists what each refusal says.

## The packet

A program's argument is its context, which offers the methods of the kernel's own object for the
hook, and opens the packet:

| Program | The context offers |
|---------|--------------------|
| XDP | `ctx:packet()`, the packet; `ctx:ingress()`, the index of the device it arrived on; `ctx:queue()`, the receive queue it arrived in |
| TC | `skb:data()`, the packet; `#skb`, its length; `skb:ifindex()`, the index of its device; `skb:hash()`, its flow hash; `skb:priority()`, its priority, which `skb:priority(v)` sets and returns |

Any other method is refused: `skb:mark()` gives "the context has no method 'mark'". The packet
is a read-only view of its bytes, with the reads of the kernel's `data` object. An offset counts
from 0, the first byte of the Ethernet header.

| Method | Reads |
|--------|-------|
| `p:getbyte(n)`, `p:getuint8(n)` | 1 byte, unsigned |
| `p:getint8(n)` | 1 byte, signed |
| `p:getuint16(n)`, `p:getint16(n)` | 2 bytes, unsigned or signed |
| `p:getuint32(n)`, `p:getint32(n)` | 4 bytes, unsigned or signed |
| `p:getint64(n)` | 8 bytes, signed |
| `#p` | the length of the packet |

A read wider than a byte is in the byte order of the kernel, as the kernel's `data` object reads
it: little-endian on x86 and arm64, where `p:getuint16(16)` of an IPv4 header whose total length
is 28 gives 7168. A field in network order is read a byte at a time:

```Lua
local length = p:getbyte(16) << 8 | p:getbyte(17) --> 28
```

A read that passes the end of the packet, or starts past byte 65535 less its width, stops the
program. There is no `getuint64`, since a Lua integer is signed, and no write: "the packet has no
method 'setbyte'". The bounds of the packet are not numbers: `ctx.data_end - ctx.data` is refused,
"'data_end' is a packet bound, not a number; '#' on the packet is its length". On a kernel without
efficient unaligned access, a read wider than a byte is refused (#2047): "'getuint16' reads more
than a byte, and this kernel lacks efficient unaligned access". `skb:data(layer)` is refused:
"'data' with a layer is not compiled yet".

## Maps

The body declares a map with `bpf.map`: `map.hash(name, spec)`, `map.array(name, spec)` or
`map.lru_hash(name, spec)`. The spec is `{key = ..., value = ..., entries = ...}`: the key is a
`string.pack` format of one integer, four bytes wide in an array, the value one of those or a
`struct` codec, both in the kernel's byte order, and `entries` the map's capacity. `lunatik run`
creates the map and pins it at `/sys/fs/bpf/lunatik/<script>/<name>`, where a kernel script opens
it with the constructor of the same name of the kernel's `bpf.map`, which takes the path and the
two specs: `map.hash(path, "I4", "I8")`.

In a compiled function a map reads as a table.

* `m[k]` is the value, or nil. The value is used only after `if v then`, or `if not v then`,
  tests it; any other use is refused: "'flows' may be nil here; test it first". A lookup in an
  array within its entries always finds a value, 0 where nothing was written.
* `m[k] = v` inserts or replaces the entry, and `m[k] = nil` deletes it; deleting a key the map
  does not hold is not an error.
* A key or a value its spec cannot pack stops the program, and so does an update or a delete the
  map refuses: an update of a full hash map, an index past an array's entries, a delete from an
  array. One the compiler knows is refused: "the map key -1 does not fit 'I4'".
* A `struct` value is read-only and read by field name, `v.ttl`; a field wider than a byte is
  refused on a kernel without efficient unaligned access, as a packet read is.

## Calls

A compiled function calls a Lua function the program file declares, or one a kernel script it
requires declares, installed as source. The callee is compiled once for each program that calls
it.

* It takes at most four arguments, each a number or the packet, and returns one value; Lua's nil
  fills every other result the caller asks for.
* Its first call fixes the types of its arguments: a later call with other types is refused,
  "'f' is called with a packet and compiled with a number".
* A callee that stops stops the program.
* A function written in C is refused, `print`, `pcall`, `ipairs` and `math.floor` among them:
  "'print' is not a Lua function this program file declares". So is recursion, "recursion through
  'walk'", and a call whose arguments include a call, `f(g(x))`, which is written
  `local y = g(x)` and then `f(y)`.
* `return f(x)` is a tail call, which is refused: write `local v = f(x)`, then `return v`.

## Loops

A numeric `for` is the only loop compiled. It makes the passes Lua makes.

* With bounds and a step the compiler knows, `for i = 14, 17 do`, it compiles for every kernel.
  The verifier walks it pass by pass when `lunatik run` loads it, so a loop of many passes is
  refused there: `for i = 1, 100000 do` gives "BPF program is too large", and one that reads the
  packet on each pass "The sequence of 8193 jumps is too complex", at fewer passes.
* With a bound or a step the program computes, `for i = 1, n do`, it compiles for Linux 6.9 and
  later, through the kernel's `may_goto`, and is refused before 6.9: "a 'for' the compiler cannot
  bound needs may_goto, which this kernel lacks". Once the budget the kernel gives a loop runs out,
  the kernel leaves the loop and the program goes on with what the loop held (#1944).
* A step of 0 is refused when the compiler knows it, "'for' step is zero", and stops the program
  when the program computes it.

`while`, `repeat`, a `goto` backwards and a generic `for` are refused.

## Where a compiled function and Lua differ

Lua decides some things only when the line runs, from the type a value has then. A compiled
function cannot, and is refused where its answer could differ from Lua's. A variable that holds a
number on one path and nil or a boolean on another is refused where `==` compares it or `if` tests
it, since the kernel holds `nil`, `false` and `0` as the same word:

```Lua
local v
if p:getbyte(14) > 0 then v = 7 end
if v == 7 then return action.DROP end -- "a value cannot be compared with a number here"
```

Give the variable one type on every path: `local v = 0`. These are refused too:

* The value of a map lookup used before `if v then`: "'flows' may be nil here; test it first".
  The kernel lets the program read the value only past that test.
* A variable that holds a lookup in one map on one path and in another map on the other: "a map
  value here comes from more than one map". Which map it came from decides how its value is read.
* A verdict that may be nil: "the verdict may be nil here; test it first". The kernel would read
  nil as 0, which is an action.
* Arithmetic on nil or a boolean, and an ordered comparison of a value that is not a number:
  "attempt to perform arithmetic on a nil value", "attempt to compare a context with a number".

## Messages

Each refusal reads `lunatik: <file>:<line>: <message>`.

| Message | You wrote | Write instead |
|---------|-----------|---------------|
| a tail call cannot be compiled | `return f(x)`, `return p:getuint16(12)` | `local v = f(x)`, then `return v` |
| a call with a variable number of values cannot be compiled | `f(g(x))`, `f(p:getbyte(1))` | `local b = g(x)`, then `f(b)` |
| 'ports' is indexed by a value the compiler cannot resolve | `ports[i]`, `i` read from the packet or a loop | a map, or one comparison per value |
| '#' cannot be applied in a compiled function | `#ports`, a table of the body | `local N <const> = #ports` in the body |
| a table constructor cannot run in the kernel; build it in the file body | `{}` in the function | the table in the body |
| '..' cannot be applied in a compiled function | `a .. b` | the string in the body |
| 'print' is not a Lua function this program file declares | `print`, `pcall`, `math.floor`, `ipairs` in a generic `for` | a Lua function of the file |
| global 'limit' is not a compile-time value | a global the body never set | set it in the body |
| a global cannot be assigned in a compiled function | `counter = 1`, `t.x = 1` | a map |
| an upvalue cannot be assigned in a compiled function | `n = n + 1`, `n` a local of the body | a map |
| a closure cannot be created in a compiled function | `function () ... end` in the function | a function of the body |
| a compiled function takes at most 4 arguments, not 5 | five arguments | four (#2094) |
| a compiled function returns at most one value | `return a, b` in a callee | one value |
| recursion through 'walk' | a function that calls itself | a `for` |
| the packet has no method 'getuint64' | `getuint64`, `setbyte` | the reads of [The packet](#the-packet) |
| the context has no method 'mark' | `skb:mark()`, `ctx:argument()` | the methods of [The packet](#the-packet) |
| 'data_end' is a packet bound, not a number; '#' on the packet is its length | `ctx.data_end - ctx.data` | `#p` |
| 'flows' may be nil here; test it first | a lookup used untested | `if v then` |
| a value cannot be compared with a number here | `==` on a variable nil on one path | `local v = 0` |
| a value has no truth value in a compiled function | `if v then`, `v` a number or nil | `local v = 0`, then `if v ~= 0 then` |
| the verdict may be nil here; test it first | `return v`, `v` nil on one path | a verdict on every path |
| 'half' is a float, which a compiled function cannot hold | `local half = math.sqrt(4)` in the body | an integer |
| malformed number near '.5', which `lunatic` prints before `lunatic could not compile it` | `2.5` | an integer: the kernel's Lua has no float |
| 'while', 'repeat' and a 'goto' backwards are not compiled yet | `while`, `repeat`, a `goto` backwards | a numeric `for` |
| a 'for' the compiler cannot bound needs may_goto, which this kernel lacks | `for i = 1, n`, before Linux 6.9 | known bounds |
| 'for' step is zero | `for i = 1, 10, 0` | a step that is not 0 |
| the map key -1 does not fit 'I4' | a key or a value outside its spec | a value its spec packs |
| module 'byteorder' not found | `require` of a C module | a Lua module under `/lib/modules/lua/` |

## How a program file becomes a program

```
  lunatik bpf -o filter.bpf.o filter.bpf.lua               on the host

  filter.bpf.lua
  +----------------------------------------------------+
  | the body       runs once, now, on the host         |
  |   map.array(counts, {...})       --> a map         |
  |   xdp.program(function ... end)  --> a program     |
  | the function   compiled now, run later, per packet |
  +----------------------------------------------------+
         |
         | 1. lunatic, the Lua compiler of the kernel, compiles the file:
         |    the bytecode the kernel would run, integers only
         v
  the chunk of the program file
         |
         | 2. the Lua of the CLI (lua5.5) runs the body from that chunk;
         |    require finds bpf.xdp, bpf.tc and bpf.map, then the kernel
         |    scripts under /lib/modules/lua/
         v
  the programs and the maps the body declared
         |
         | 3. the translator turns each program function, and each Lua
         |    function it calls, into eBPF instructions; outside the
         |    subset, lunatik: file:line: reason, exit 1, no object
         v
  eBPF instructions, each one tagged with its Lua line
         |
         | 4. the object is written for the kernel lunatik.config names,
         |    with the offsets of the context fields read from its BTF
         v
  filter.bpf.o          installed as /lib/modules/lua/filter.bpf.o
```

A program file, `<name>.bpf.lua`, may declare several programs. Each is named by the `name` its
constructor takes, or after the file, and `lunatik run --dev` attaches every one of them, as
[Compiled programs](02-running-scripts.md#compiled-programs) describes.

`lunatik bpf` compiles for the kernel `lunatik.config` names, which `make` writes from the kernel
tree Lunatik is built against. Three facts of that kernel change what compiles:

* Linux 6.9 or later compiles a `for` whose bounds the program computes; an earlier kernel
  refuses it.
* A kernel without efficient unaligned access refuses a read wider than a byte, from the packet or
  from a map value (#2047).
* The object takes the kernel's byte order.

The offsets of the context fields come from the kernel's BTF, `/sys/kernel/btf/vmlinux` unless
`--btf` names another file, so a program that reads its context, or the packet, compiles only
where that BTF is. Compiling for another kernel is in
[Program files](02-running-scripts.md#program-files). A TC program needs libbpf 1.3.0 or later on
the machine that loads it.

