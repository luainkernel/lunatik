# Plan: conntrack and NAT support for Lunatik

Execution plan for conntrack and NAT support in Lunatik (an idea that originated in the
[LabLua GSoC list](https://github.com/labluapucrio/gsoc/blob/main/2026/ideas.md#conntrack-and-nat-support-for-lunatik),
now tracked here as a regular project).

## Where we are today

Lunatik's netfilter story is complete for stateless filtering and empty for stateful work:

* `netfilter.register{hook, pf, hooknum, priority, mark}` registers a hook in `init_net` and calls a
  Lua function with an `skb`, expecting `(verdict[, mark])` back (`lib/luanetfilter.c`);
* the `skb` object exposes length, ifindex, VLAN, payload as a `data` object, resize, checksum,
  forward and copy (`lib/luaskb.c`);
* `linux.nf` carries the netfilter constants generated from the uapi headers: `proto`, `inet`,
  `netdev`, `arp`, `ip.pri`, `br`, `br.pri`, `action`.

The only conntrack touchpoint that exists is `skb:connmark([value])`, which calls `nf_ct_get` and
reads or writes `ct->mark` under `CONFIG_NF_CONNTRACK_MARK`. That is one 32 bit field of one
connection, reachable only from inside a hook.

So "we already did basic conntrack support" means: we can read and write the connection mark. Missing
is everything the idea actually asks for.

## What is missing

| Idea outcome | Gap |
|--------------|-----|
| Retrieve conntrack entries and connection information | No conntrack object at all. No tuples, status, state, timeouts, counters, labels, zone, helper, master. No way to look up an entry by tuple, iterate the table, or observe events. |
| Add conntrack entries from Lua for NAT operations | No allocation, insertion or expectation API. |
| Implement NAT for inet protocols | Nothing. No NAT hook registration, no SNAT/DNAT, no masquerade, no redirect. |

Supporting gaps that block the above:

* no conntrack or NAT constants in `linux.nf` (`IP_CT_*`, `IPS_*`, `IPCT_*`, `TCP_CONNTRACK_*`,
  `NF_NAT_RANGE_*`);
* no IPv6 address representation in Lua (`net.lua` has `aton`/`ntoa` for IPv4 only), which the idea's
  "inet protocols" wording requires;
* no cross module accessor for the `skb` pointer, so a second module cannot validate an `skb` argument;
* no netns aware test harness; the existing netfilter test drives loopback traffic in `init_net`,
  which is not enough to prove a translation happened.

## Shape of the work

Two new kernel modules, `conntrack` and `nat`, mirroring the kernel's own `nf_conntrack` /`nf_nat`
split. The full API proposal is in `api.md`; the kernel constraints that drive it are in
`kernel-notes.md`. The single most important of those constraints, because it shapes the whole NAT
design:

> `nf_nat_*_register_fn` does not install your hook. It installs the NAT core's hook and chains yours
> into a lookup list that runs only for the first packet of a connection in each direction. Lua
> decides the mapping once; `nf_nat_packet` translates every packet after that.

This is what makes a Lua NAT layer viable rather than a benchmark disaster, and it is worth stating in
the proposal, the docs and the example comments.

## Phases

Each phase is one or more self contained pull requests. Lunatik's patch discipline is small auditable
commits, so nothing here lands as a single drop.

### Phase 0: warm up

Land the conntrack constants the object phase will consume: `nf.ct.info`, `nf.ct.status`, `nf.ct.dir`
and `nf.ct.tcp`. It is a small change that forces a full pass through the build, the generated
`linux.*` modules and the docs pipeline, so the contributor learns the machinery before touching
netfilter.

`nf.nat.range` waits for the NAT phase and `nf.ct.event` for the events phase. `linux.nf` is published
API: a table whose consumer does not exist yet freezes a shape before the API that uses it has been
designed, and every one of the curation mistakes worth catching (sentinels that are not states, flags
`nf_nat_setup_info` ignores, bit positions dressed as masks) is only visible once you know who reads
the table.

Deliverables: `autogen/specs.lua` entries for the four conntrack tables, plus whatever small
`autogen.lua` change the `IPS_*` prefix collision needs.

### Phase 1: read the connection

The `conntrack` module and object: `conntrack.get(skb)`, tuples, status, state, timeout, id, TCP
state, counters, labels, zone, master, helper, mark.

Deliverables: `lib/luaconntrack.c`, `lib/luaconntrack.h`, `Kconfig`/`Kbuild` entries, a
`luaskb_checkskb` accessor in `lib/luaskb.h`, `tests/conntrack/`, README and `config.ld` entries.

### Phase 2: the table

`conntrack.count`, `conntrack.max`, `conntrack.lookup(tuple)`, `conntrack.each(fn)`, `ct:delete`,
`ct:refresh`. Includes the design decision on how to walk the table, which should be settled with a
prototype rather than an argument.

### Phase 3: NAT

`nat.register`, `nat.snat`, `nat.dnat`, `nat.masquerade`, `nat.redirect`, plus the `nf.nat.range`
constants. The hook signature is `(skb)`, like `netfilter.register`; the binding captures the
`nf_hook_state` internally (see `api.md`). This is the first point at which the project does something
a user can see.

Deliverables: `lib/luanat.c`, `tests/nat/` with veth and namespace based SNAT and DNAT tests, an
`examples/` script.

### Phase 4: events

`conntrack.watch(fn)`, `conntrack.unwatch()`, `nf.ct.event` constants, plus the "one notifier per
netns" guard. Yields a `conntrack -E` equivalent written in Lua.

### Phase 5: create entries and expectations

`conntrack.new{}` and `ct:expect{}`. This is the half of "add conntrack entries from Lua" that the
L7 load balancing scenario actually needs, since a Lua ALG pre-authorizes its data connection with an
expectation rather than by inserting a raw entry.

### Phase 6: the demo and the docs

An L7 load balancer example that ties it together (classify on the HTTP `Host` header, record the
choice, let the NAT core do the work), plus a documentation pass and any API cleanup the demo exposes.
Write the demo early enough that its findings can still change the API: it already changed the shape
of the example once, when it turned out that a payload based decision cannot steer the connection that
carried it.

Each phase is sized by what fits in one reviewable pull request, and the order is chosen so that the
project is complete at every cut: reaching the end of phase 3 with tests and docs is already a
mergeable contribution, and every later phase is additive.

## Non goals

Stated explicitly so they do not creep in:

* **Network namespaces.** Everything registers in `init_net`, matching the existing netfilter binding.
  Adding a `net` selector is a separate change that should be made once for all hook types, not
  invented here. Tracked as a follow up.
* **Conntrack helpers written in Lua.** `nf_conntrack_helper_register` would let a script implement a
  full ALG. It is the natural sequel and it is out of scope; expectations cover the load balancing
  case without it.
* **ctnetlink in Lua.** Now that Lunatik has a netlink module and rtnetlink decoders, a `conntrack -L`
  equivalent could be written in pure Lua over `NETLINK_NETFILTER`. That is a legitimate project, but
  it does not help the packet path (a hook cannot do a netlink round trip) and it duplicates
  ctnetlink's wire format. The C binding is needed regardless.
* **Replacing `skb:connmark`.** It stays. `ct:mark` reaches the same field through the new object.

## Risks

| Risk | Mitigation |
|------|-----------|
| Conntrack object lifetime (`nf_ct_get` returns a borrowed pointer) | Take a reference in the object. Measure the cost in phase 1; only optimize if it shows. |
| NAT hook semantics misunderstood, leading to a design that tries to translate packets in Lua | Settled up front in `kernel-notes.md`. Reviewers should check any NAT patch against it. |
| Kernel version drift (`nf_ct_iterate_cleanup_net` changed signature in 6.x, `nf_conntrack_register_notifier` changed return type) | Verify signatures against the target kernel before writing code, not after. |
| Testing NAT needs real topology | Build the netns harness in phase 3 before the NAT code, not after. See `testing.md`. |
| Config matrix (`CONFIG_NF_CONNTRACK_ACCT`, `_LABELS`, `_EVENTS`, `NF_NAT_MASQUERADE`) | Guard per feature, skip cleanly in tests, mirroring `tests/skb/connmark.sh`. |

## Definition of done, per phase

A phase is done when all of the following are true. This list is the review checklist, not a
suggestion.

1. builds clean on the target kernel, no new warnings;
2. LDoc comments on every new function and object type, and the module listed in `config.ld` in
   alphabetical order;
3. a row in the README module table;
4. a test in the right suite, wired into that suite's `run.sh`, and described in `tests/README.md`;
5. the test skips (not fails) when the kernel lacks the config it needs;
6. the full suite still passes: `sudo lunatik test`;
7. error paths audited: for every raise, whatever was already acquired is released;
8. commits are small and each one stands alone.

