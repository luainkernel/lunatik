# Proposed Lua API: `conntrack` and `nat`

This is a design proposal, not a specification. Names and shapes are open for review; the constraints
behind them (in `kernel-notes.md`) are not. Anything here that turns out to conflict with a kernel
constraint loses.

Two new kernel modules:

* `conntrack` (`lib/luaconntrack.c`, plus `lib/luaconntrack.h` for the cross-module checker), which
  owns the `conntrack` object class and everything that reads or writes conntrack state;
* `nat` (`lib/luanat.c`), which owns NAT hook registration and the translation setup calls.

The split follows the kernel's own split (`nf_conntrack.ko` and `nf_nat.ko`), keeps `CONFIG_NF_NAT`
out of the conntrack module, and lets a script that only reads connection state avoid pulling in NAT.
`nat` depends on `conntrack` and `skb`.

## Conventions

* IPv4 addresses are host order integers, matching `net.aton`/`net.ntoa` and the existing socket API.
* IPv6 addresses are 16 byte binary strings. `lib/net.lua` gains `aton6`/`ntoa6` for them.
* Ports are host order integers. The C side does the `ntohs`.
* Constants come from `linux.nf` via autogen: `nf.ct.info`, `nf.ct.status`, `nf.ct.dir`, `nf.ct.tcp`,
  `nf.ct.event`, `nf.nat.range`.
* Missing optional kernel features mean a missing method, not a runtime error. A script can probe with
  `if ct.mark then ... end`, the same way `skb:connmark` behaves today.

## `conntrack`

### `conntrack.get(skb)` -> `ct`, `info`

Wraps `nf_ct_get`. Returns `nil` for `ct` when the packet carries no conntrack. `info` is one of
`nf.ct.info.*` (`NEW`, `ESTABLISHED`, `RELATED`, and their `_REPLY` forms).

Return `info` even when `ct` is `nil`, because the two nil cases are not the same. A packet the ruleset
sent through `notrack` carries `ct == NULL` with `ctinfo == IP_CT_UNTRACKED`
(`nft_ct.c` and `xt_CT.c` both do `nf_ct_set(skb, NULL, IP_CT_UNTRACKED)`), while a packet conntrack
never saw carries neither. A script that wants to distinguish "deliberately untracked" from "not
tracked yet" needs the second value.

    local conntrack = require("conntrack")
    local nf        = require("linux.nf")

    local function hook(skb)
        local ct, info = conntrack.get(skb)
        if ct and info == nf.ct.info.NEW then
            print("new flow", ct:tuple().dport)
        end
        return nf.action.ACCEPT
    end

**Why a module function and not `skb:conntrack()`.** The framework precedent is a method on the object
(`skb:data()` returns a `data`), but the module dependency decides against it here. `skb:connmark`
lives inside `luaskb` only because `nf_ct_get` is inline and `ct->mark` is direct struct access, so
`luaskb.ko` imports no conntrack symbol. A `skb:conntrack()` returning an object of the conntrack
class would need a constructor exported by `luaconntrack.ko`, chaining
`luaskb.ko → luaconntrack.ko → nf_conntrack.ko`, and since `require` pins modules, every skb user
(any L2 filter, any XDP script) would load and pin conntrack forever. `conntrack.get(skb)` keeps the
arrow pointing the right way: only scripts that want conntrack pay for it.

**Lifetime.** `nf_ct_get` returns a borrowed pointer. The object takes its own reference
(`nf_conntrack_get`) at creation and drops it on collection (`nf_ct_put` in `release`; the destroy
path is atomic safe, the kernel runs it from softirq routinely), so a script that stashes a `ct` in a
global cannot dangle. The cost is one atomic plus one object allocation per call on the packet path,
which is the right trade for a scripting layer: a use-after-free here is a kernel oops, and Lunatik's
whole premise is that a bad script must not take the machine down.

Phase 1 benchmarks that cost. If it shows, the optimization is a per-runtime freelist that reuses dead
`ct` userdata, which changes neither the semantics nor the Lua API. The skb-style registry cache
(reset per hook, cleared afterwards) is not the fallback here: clearing on return is exactly the
lifetime problem the refcount closes.

**Class shape.** `LUNATIK_OPT_SOFTIRQ`, and neither `SINGLE` (several `ct` objects can be alive at
once: `master()`, `lookup()`) nor `MONITOR` (methods are short reads). `.pointer = true`: the
`struct nf_conn *` is not owned by Lunatik, `release` only drops the reference. Errors follow the base
convention, negative errno raised via `lunatik_throw`/`pusherrname`.

### The `conntrack` object

| Method | Returns | Notes |
|--------|---------|-------|
| `ct:tuple([dir])` | table | `dir` defaults to `nf.ct.dir.ORIGINAL` |
| `ct:status()` | integer | test against `nf.ct.status.*` (`SEEN_REPLY`, `ASSURED`, `SRC_NAT`, ...) |
| `ct:id()` | integer | `nf_ct_get_id`, stable while the entry lives |
| `ct:timeout()` | integer | milliseconds until expiry |
| `ct:refresh(ms)` | | extend the timeout |
| `ct:mark([value])` | integer | `CONFIG_NF_CONNTRACK_MARK`; same storage as `skb:connmark` |
| `ct:labels()` | 16 byte string | `CONFIG_NF_CONNTRACK_LABELS`; the label bitmap is 128 bits (`XT_CONNLABEL_MAXBIT` is 127), it does not fit a Lua integer |
| `ct:zone()` | integer | the zone id; the kernel zone also carries `flags` and `dir`, not exposed |
| `ct:counters([dir])` | packets, bytes | `CONFIG_NF_CONNTRACK_ACCT` |
| `ct:tcpstate()` | integer | `nf.ct.tcp.*`; `nil` for non TCP |
| `ct:master()` | `conntrack` | the connection this one is `RELATED` to; the new object takes its own reference |
| `ct:helper()` | string | helper name, or `nil`; `nfct_help(ct)->helper` is `__rcu`, dereference accordingly |
| `ct:delete()` | | `nf_ct_delete` |
| `ct:expect(spec)` | | see below |

The tuple table:

    {
      family   = nf.proto.IPV4,   -- or IPV6
      protocol = ipproto.TCP,
      src = 3232235777, sport = 51234,   -- integer for IPv4, 16 byte string for IPv6
      dst = 3232235778, dport = 80,
    }

For ICMP, `sport`/`dport` are absent and `type`/`code`/`id` take their place.

A fresh table per call is fine here: per packet code reads fields straight from `skb:data()`, as
scripts already do today, so `ct:tuple()` is not hot path material. Its value is the view only
conntrack has, the reply tuple after NAT and the original tuple seen from a reply. Say so in the LDoc.

`skb:connmark` stays exactly as it is. `ct:mark` is the same 32 bits reached through the conntrack
object; `skb:connmark` remains the convenient form when a hook only wants the mark and nothing else.

### Table access

    conntrack.count()             -- entries in the table
    conntrack.max()               -- table limit
    conntrack.lookup(tuple)       -- ct or nil; takes a reference
    conntrack.each(function(ct)   -- iterate; return false to stop
        ...
    end)

`conntrack.lookup` builds a `struct nf_conntrack_tuple` from the same table shape `ct:tuple()`
returns, so a tuple can round trip.

`conntrack.each` is the `conntrack -L` equivalent. See `kernel-notes.md` for the walk choice and its
context restrictions.

### Events

    conntrack.watch(function(events, ct)
        if events & (1 << nf.ct.event.DESTROY) ~= 0 then
            ...
        end
    end)
    conntrack.unwatch()

`nf.ct.event.*` are **bit positions**, not masks: `enum ip_conntrack_events` numbers its members 0, 1,
2, ..., and the kernel builds the mask itself (`nf_conntrack_event` calls
`nf_conntrack_eventmask_report(1 << event, ...)`). The `events` argument is that mask, so testing a bit
means shifting first. Writing `events & nf.ct.event.DESTROY` reads naturally and is wrong: with
`DESTROY = 2` it tests bit 1, which is `RELATED`.

One watcher per netns, enforced by the kernel. The runtime must be `softirq`, but the callback does
**not** fire only from softirq: the ecache retry path redelivers missed `DESTROY` events from a
workqueue, in process context (`ecache_work_evict_list` calls `nf_conntrack_event`,
`nf_conntrack_ecache.c`). A `softirq` runtime handles both, `spin_lock_bh` is callable from process
context, but the implementation must not assume softirq-only. `conntrack.watch` raises if a notifier
is already installed rather than stealing ctnetlink's slot.

**Verify before implementing:** whether `nf_conntrack_unregister_notifier` sleeps (a `synchronize_rcu`
would be typical). If it does, `unwatch` cannot run from the softirq runtime itself, and teardown
follows the soft-stop convention: cleanup in `release`, on a pinned object, as `netlink.channel` does.

### Creating entries

    local ct = conntrack.new{
        original = { family = nf.proto.IPV4, protocol = ipproto.UDP,
                     src = net.aton("10.0.0.1"), sport = 1000,
                     dst = net.aton("10.0.0.2"), dport = 2000 },
        reply    = { ... },        -- optional, inverted from original when omitted
        timeout  = 30000,          -- ms
        status   = nf.ct.status.CONFIRMED,
        mark     = 0x10,
    }

Wraps allocate, populate, insert. Raises on `-EEXIST` when the tuple is already taken. Process context
only in the first cut.

### Expectations

    ct:expect{
        family   = nf.proto.IPV4,
        protocol = ipproto.TCP,
        src = nil,                 -- nil means "any", as the expectation mask allows
        dst = net.aton("10.0.0.2"), dport = 5001,
        timeout = 30000,
    }

This is how a Lua ALG pre-authorizes a data connection: the expected flow arrives as `RELATED` and,
under NAT, follows the master's translation.

## `nat`

### `nat.register(opts)` -> `nat_hook`

    local nat = require("nat")

    local function dnat_hook(skb)
        local ct = conntrack.get(skb)
        nat.dnat(ct, { addr = net.aton("10.0.0.5"), port = 8080 })
        return nf.action.ACCEPT
    end

    nat.register{
        hook    = dnat_hook,
        pf      = nf.proto.IPV4,          -- IPV4, IPV6 or INET
        hooknum = nf.inet.PRE_ROUTING,    -- one of the four NAT hooks
    }

There is no `priority`: the NAT core owns it. Collecting the returned handle unregisters the hook, the
same contract `netfilter.register` has today.

The hook is called at most once per connection per direction, and only while no binding exists. Every
subsequent packet is translated by the kernel with no Lua involvement. Established packets never reach
the hook, so a script cannot use a NAT hook as a general packet filter; that is what `netfilter.register`
is for.

The hook signature is `(skb)`, the same as `netfilter.register`. There is no `state` object: everything
`struct nf_hook_state` carries is either something the script already knows because it registered the
hook (`hooknum`, `pf`) or reachable through the skb (`skb:ifindex()` is the ingress device at
`PRE_ROUTING` and the egress device at `POST_ROUTING`). What the C side needs from the state
(masquerade wants the hooknum and the out device) the binding captures internally: the hook stores the
`nf_hook_state` pointer in its private struct before the `pcall` and clears it afterwards, under the
runtime lock, the same reset/clear pattern `luanetfilter` uses for the skb.

### Translation setup

    nat.snat(ct, range)     -- NF_NAT_MANIP_SRC
    nat.dnat(ct, range)     -- NF_NAT_MANIP_DST

`range`:

    {
      addr = ..., addr_max = ...,   -- optional; sets NF_NAT_RANGE_MAP_IPS
      port = ..., port_max = ...,   -- optional; sets NF_NAT_RANGE_PROTO_SPECIFIED
      flags = nf.nat.range.PROTO_RANDOM_FULLY,   -- optional extras, OR'ed in
    }

`addr_max`/`port_max` default to their `_min` counterparts. `NF_NAT_RANGE_MAP_IPS` and
`NF_NAT_RANGE_PROTO_SPECIFIED` are derived from the presence of `addr` and `port`, so the common case
stays two keys and neither flag belongs in `nf.nat.range`: a script that passed one would either
duplicate the derivation or contradict it. Both calls raise if the manip type contradicts the hook the
call is made from (SNAT outside `POST_ROUTING`/`LOCAL_IN`), which is a mistake the kernel would
otherwise absorb silently.

The flags a script can meaningfully choose are `PROTO_RANDOM`, `PROTO_RANDOM_FULLY` and `PERSISTENT`.
Two more exist and are not usable as specified, so they stay out until the API grows to fit them:

* `PROTO_OFFSET` reads `range->base_proto` (`nf_nat_core.c:552`), which this range table has no key
  for. Adding it means adding a `base_port`.
* `NETMAP` is not implemented by `nf_nat_setup_info` at all. The caller does the arithmetic:
  `nft_nat_setup_netmap()` computes the mapped address and only passes the flag along. Supporting it
  means doing that arithmetic in the binding, not forwarding a flag.

### Shorthands

    nat.masquerade(skb[, range])   -- source address of the outgoing interface
    nat.redirect(skb, range)       -- to a local address on the incoming interface

These wrap `nf_nat_masquerade_ipv4/ipv6` and `nf_nat_redirect_ipv4/ipv6`, which need the hooknum and
the output device; both come from the internally captured hook state, so the Lua side never sees them.
The masquerade notifiers are registered once at module init.

## Worked example: L7 load balancer

The project's motivating scenario, end to end. The classifier reads the HTTP `Host` header,
which is one `string.match` away, rather than parsing a TLS ClientHello for the SNI. Same design, far
less code in the part that is not the point of the example.

### The constraint that decides the shape

A payload based decision cannot steer the connection that carried it.

For a TCP connection the NAT hook runs on the SYN, because that is the `IP_CT_NEW` packet. The `Host`
header arrives after the handshake, by which time a binding (possibly the null binding the core
installs when Lua declines) already exists and the hook is never called again. The same is true of the
TLS SNI: both live in the first *data* packet, not the first packet.

So the example is sticky by client: the first connection from a client goes to the default backend and
teaches the map; every later connection from that client is steered on its SYN. That is a real load
balancing strategy, it exercises `conntrack`, `nat` and `rcu` together, and it is honest about what
the primitives can do.

A version that steers on the very first connection is possible over UDP, where the first packet
carries the payload; DNS is the obvious candidate and is worth a second, smaller example.

    local netfilter = require("netfilter")
    local conntrack = require("conntrack")
    local nat       = require("nat")
    local rcu       = require("rcu")
    local nf        = require("linux.nf")
    local net       = require("net")

    local BACKENDS <const> = {
        ["a.example.com"] = net.aton("10.0.0.11"),
        ["b.example.com"] = net.aton("10.0.0.12"),
    }
    local affinity = rcu.table()

    -- On the first data packet of a connection, learn where this client belongs.
    local function classify(skb)
        local ct = conntrack.get(skb)
        if not ct then return nf.action.ACCEPT end
        local host = string.match(payload(skb), "\r\nHost: ([^\r\n]+)")
        local backend = host and BACKENDS[host]
        if backend then affinity[client(ct)] = backend end
        return nf.action.ACCEPT
    end

    -- On the SYN of a later connection from the same client, apply what we learned.
    local function balance(skb)
        local ct = conntrack.get(skb)
        local backend = ct and affinity[client(ct)]
        if backend then
            nat.dnat(ct, { addr = backend, port = 80 })
        end
        return nf.action.ACCEPT
    end

    netfilter.register{ hook = classify, pf = nf.proto.IPV4,
                        hooknum = nf.inet.PRE_ROUTING, priority = nf.ip.pri.CONNTRACK + 1 }
    nat.register{ hook = balance, pf = nf.proto.IPV4, hooknum = nf.inet.PRE_ROUTING }

The classifier still has to run after conntrack has attached an entry, hence the priority. `payload`
and `client` are small Lua helpers over `skb:data()` and `ct:tuple()`, the latter returning a string
because `rcu.table` keys are strings; keeping them out of the sketch is the point, since the example is
about the conntrack and NAT plumbing.

## Autogen additions

New entries in `autogen/specs.lua`. **Each table lands with the phase that consumes it**, not all up
front: `linux.nf` is published API, and a table whose consumer does not exist yet freezes a shape
before the API that uses it has been designed.

| Header | Prefix | Module | Lands with |
|--------|--------|--------|-----------|
| `uapi/linux/netfilter/nf_conntrack_common.h` | `IP_CT_` | `nf.ct.info` | the `conntrack` object |
| `uapi/linux/netfilter/nf_conntrack_common.h` | `IPS_` | `nf.ct.status` | the `conntrack` object |
| `uapi/linux/netfilter/nf_conntrack_tuple_common.h` | `IP_CT_DIR_` | `nf.ct.dir` | the `conntrack` object |
| `uapi/linux/netfilter/nf_conntrack_tcp.h` | `TCP_CONNTRACK_` | `nf.ct.tcp` | the `conntrack` object |
| `uapi/linux/netfilter/nf_nat.h` | `NF_NAT_RANGE_` | `nf.nat.range` | the `nat` module |
| `uapi/linux/netfilter/nf_conntrack_common.h` | `IPCT_` | `nf.ct.event` | conntrack events |

There is no `nf.nat.manip`. `nat.snat` and `nat.dnat` encode the manip type in the function name, so
nothing would read it, and `NF_NAT_MANIP_*` lives in `net/netfilter/nf_nat.h`, a non-uapi header and
the most fragile source available. Add it if an API ever needs to name a manip type.

Wrinkles the contributor will hit:

* `IPS_*` defines both `IPS_FOO_BIT` and `IPS_FOO`. `specs.lua` supports `exclude`, but it matches a
  prefix, so it cannot drop the `_BIT` names. Either add suffix exclusion to `autogen.lua` (small,
  self contained, a good warm up task) or enumerate with `include`.
* `IP_CT_` and `IP_CT_DIR_` share a prefix, so the `nf.ct.info` entry needs `exclude = "IP_CT_DIR_"`,
  the same way `nf.br` excludes `NF_BR_PRI_`.
* the enums carry sentinels that are not values a script should ever use: `IP_CT_NUMBER` (the kernel
  asserts this with `BUILD_BUG_ON(IP_CT_UNTRACKED == IP_CT_NUMBER)`), `IP_CT_DIR_MAX`,
  `TCP_CONNTRACK_MAX`. Exclude them. `IP_CT_IS_REPLY` stays, because the kernel itself compares against
  it to derive direction, but it shares its value with `IP_CT_ESTABLISHED_REPLY` and the table
  description has to say so.
* `TCP_CONNTRACK_IGNORE`, `_RETRANS` and `_UNACK` are not states. `ct->proto.tcp.state` only ever holds
  0 to 9, the ten entries of the kernel's own `tcp_conntrack_names[]`: `IGNORE` and `MAX` are handled
  in a switch that returns before the state is assigned, `RETRANS` and `UNACK` are indices into the
  timeout array, and ctnetlink rejects anything `>= TCP_CONNTRACK_MAX`. Enumerate the real states with
  `include` rather than excluding sentinels one at a time.
* `IPS_UNTRACKED` is marked obsolete in the header, and the bit is re-purposed in kernel builds as
  `IPS_NAT_CLASH`. Both names should be present, the way `nf.ct.tcp` carries both `LISTEN` and its live
  replacement `SYN_SENT2`.
* `IPCT_*` are bit positions, not masks. See the events section.

