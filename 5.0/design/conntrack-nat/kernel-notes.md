# Kernel notes: conntrack and NAT

Reference sheet for the conntrack/NAT binding. Every symbol and signature below was checked against
Linux 6.8 (`/usr/src/linux-headers-$(uname -r)/include`, `Module.symvers`) and the upstream sources
listed at the end. Re-check on the kernel you target before relying on any of it: netfilter internals
change between releases, and a few of these signatures changed as recently as 6.x.

## Header map

| Header | What you need from it |
|--------|----------------------|
| `net/netfilter/nf_conntrack.h` | `struct nf_conn`, `nf_ct_get`, `nf_ct_set`, tuple accessors, alloc/insert, iteration |
| `net/netfilter/nf_conntrack_core.h` | `nf_conntrack_find_get`, confirm helpers |
| `net/netfilter/nf_conntrack_tuple.h` | `struct nf_conntrack_tuple` |
| `net/netfilter/nf_conntrack_acct.h` | `nf_conn_acct_find`, `struct nf_conn_counter` |
| `net/netfilter/nf_conntrack_labels.h` | `nf_ct_labels_find`, `nf_connlabel_set` |
| `net/netfilter/nf_conntrack_ecache.h` | `struct nf_ct_event_notifier`, register/unregister |
| `net/netfilter/nf_conntrack_expect.h` | `nf_ct_expect_alloc/init/related/put` |
| `net/netfilter/nf_conntrack_zones.h` | `nf_ct_zone`, `nf_ct_zone_dflt` |
| `net/netfilter/nf_nat.h` | `nf_nat_setup_info`, `nf_nat_packet`, the `*_register_fn` family |
| `net/netfilter/nf_nat_masquerade.h` | `nf_nat_masquerade_ipv4/ipv6` and their notifiers |
| `net/netfilter/nf_nat_redirect.h` | `nf_nat_redirect_ipv4/ipv6` |
| `uapi/linux/netfilter/nf_conntrack_common.h` | `enum ip_conntrack_info`, `enum ip_conntrack_status` (`IPS_*`), `enum ip_conntrack_events` (`IPCT_*`) |
| `uapi/linux/netfilter/nf_conntrack_tuple_common.h` | `enum ip_conntrack_dir` (`IP_CT_DIR_*`), `CTINFO2DIR` |
| `uapi/linux/netfilter/nf_conntrack_tcp.h` | `TCP_CONNTRACK_*` |
| `uapi/linux/netfilter/nf_nat.h` | `NF_NAT_RANGE_*`, `struct nf_nat_range2` |

All of these ship in `linux-headers-$(uname -r)`, so an out-of-tree module can use them without a
kernel source tree.

## Exported symbols we rely on

Checked in `Module.symvers`. `EXPORT_SYMBOL_GPL` is fine for Lunatik: its modules declare
`MODULE_LICENSE("Dual MIT/GPL")`, which the module loader treats as GPL compatible.

Read path:

    nf_conntrack_find_get        GPL   lookup by tuple, takes a reference
    nf_conntrack_count           GPL   number of entries in a netns
    nf_conntrack_max             GPL   table limit (data symbol)
    nf_conntrack_hash            GPL   hash table (data symbol, use nf_conntrack_get_ht)
    nf_conntrack_htable_size     GPL   bucket count (data symbol)
    nf_ct_iterate_cleanup_net    GPL   sanctioned iteration, may sleep
    nf_ct_get_id                 GPL   stable per-entry id
    nf_ct_delete                 GPL   remove an entry
    nf_ct_kill_acct              GPL   remove and account
    __nf_ct_refresh_acct         GPL   backing of nf_ct_refresh()
    nf_ct_zone_dflt              GPL   default zone (data symbol)

Write / create path:

    nf_conntrack_alloc              GPL   allocate an unconfirmed entry
    nf_conntrack_free               GPL   undo nf_conntrack_alloc
    nf_conntrack_hash_check_insert  GPL   insert a prepared entry (what ctnetlink NEW uses)
    nf_conntrack_confirm            (inline over __nf_conntrack_confirm, GPL)
    nf_ct_expect_alloc/init/put     GPL   expectations
    nf_ct_expect_related_report     GPL   backing of nf_ct_expect_related()
    nf_conntrack_helper_register    GPL   register a helper (ALG)
    nf_ct_netns_get / nf_ct_netns_put  GPL   pin conntrack for a family in a netns

Events:

    nf_conntrack_register_notifier    GPL   void, one notifier per netns
    nf_conntrack_unregister_notifier  GPL

NAT:

    nf_nat_setup_info             plain EXPORT_SYMBOL
    nf_nat_alloc_null_binding     GPL
    nf_nat_packet                 GPL
    nf_nat_ipv4_register_fn       GPL   plus the ipv6 and inet variants and their unregister twins
    nf_nat_masquerade_ipv4        GPL   also ipv6
    nf_nat_masquerade_inet_register_notifiers    GPL
    nf_nat_redirect_ipv4          GPL   also ipv6

Reference counting is inline in `uapi/linux/netfilter/nf_conntrack_common.h`
(`nf_conntrack_get`/`nf_conntrack_put`), backed by the exported `nf_conntrack_destroy`.

## Semantics that shape the API

### `nf_ct_get` does not take a reference

    static inline struct nf_conn *
    nf_ct_get(const struct sk_buff *skb, enum ip_conntrack_info *ctinfo)

The returned `struct nf_conn *` is only guaranteed to live as long as the skb reference held by the
caller, that is, for the duration of the hook. A Lua object wrapping it must either be cleared when
the hook returns (the `luaskb` pattern) or take a reference of its own. See `api.md` for the choice
made and why.

`nf_conntrack_find_get`, by contrast, returns a tuple hash with a reference already taken, so the
caller owns it and must `nf_ct_put`.

### The NAT core calls your hook only once per connection per direction

`nf_nat_ipv4_register_fn(net, ops)` does not install `ops->hook` as a netfilter hook. It installs the
NAT core's own hook (`nf_nat_inet_fn`) at the family's four NAT hook points, and chains `ops->hook`
into a private lookup list. From `net/netfilter/nf_nat_core.c`:

    case IP_CT_NEW:
        if (!nf_nat_initialized(ct, maniptype)) {
            ...
            for (i = 0; i < e->num_hook_entries; i++) {
                ret = e->hooks[i].hook(e->hooks[i].priv, skb, state);
                if (ret != NF_ACCEPT)
                    return ret;
                if (nf_nat_initialized(ct, maniptype))
                    goto do_nat;
            }
    null_bind:
            ret = nf_nat_alloc_null_binding(ct, state->hook);
            ...
    do_nat:
        return nf_nat_packet(ct, ctinfo, state->hook, skb);

Consequences for the Lua binding:

* the Lua hook runs for `IP_CT_NEW`, `IP_CT_RELATED` and `IP_CT_RELATED_REPLY` packets only, and only
  while no binding exists for that manip type. Established packets never reach Lua;
* the hook's job is to call `nf_nat_setup_info` (via `nat.snat`/`nat.dnat`) and return `NF_ACCEPT`.
  Returning `NF_ACCEPT` without setting anything up means "no NAT for this connection", and the core
  installs a null binding;
* the actual header rewriting is done by `nf_nat_packet` for every packet, not by Lua. This is what
  makes a Lua L7 load balancer cheap: Lua decides once, the kernel translates forever;
* `ops->priority` is ignored. The NAT core owns the priorities (`NF_IP_PRI_NAT_DST`, `NF_IP_PRI_NAT_SRC`).
  `ops->pf` and `ops->hooknum` are used, and `hooknum` must be one of the family's four NAT hooks;
* `nf_nat_register_fn` takes a mutex and allocates with `GFP_KERNEL`. It must be called from process
  context (see below).

`HOOK2MANIP(hooknum)` decides SRC versus DST: `POST_ROUTING` and `LOCAL_IN` are SRC, the rest are DST.
Asking for a SNAT range at `PRE_ROUTING` is a user error the binding should reject up front.

### Registration happens in process context, hooks fire in softirq

Lunatik runs a runtime's script once at creation time, before `lunatik_setready`, with
`runtime->gfp = GFP_KERNEL` and no runtime lock held (`lunatik_core.c:lunatik_newruntime`). So a
top-level `nat.register{...}` or `netfilter.register{...}` in the script is process context and may
sleep, even for a `softirq` runtime.

Everything that runs later from a hook is different: a `softirq` runtime holds `spin_lock_bh` around
`lua_pcall` and allocates with `GFP_ATOMIC`. Anything reachable from a hook must be atomic safe.

Practical rule for this project:

| Operation | Context |
|-----------|---------|
| `nat.register`, `conntrack.watch`, helper registration | process only, at script load |
| `conntrack.get`, tuple/status/mark/counter reads, `nat.snat`, `nat.dnat` | atomic safe, usable from hooks |
| `conntrack.each` over the whole table | process only, see below |
| `conntrack.new` | depends on the gfp used; keep it process only in the first cut |

Use `lunatik_cannotsleep(L, true)` to reject the sleeping entry points when called from an
IRQ-context runtime rather than letting them crash the machine.

### Iterating the table: two options

`nf_ct_iterate_cleanup_net` changed shape in 6.x. On 6.8 it is:

    struct nf_ct_iter_data { struct net *net; void *data; u32 portid; int report; };
    void nf_ct_iterate_cleanup_net(int (*iter)(struct nf_conn *i, void *data),
                                   const struct nf_ct_iter_data *iter_data);

An iterator that always returns 0 never deletes anything, so it can be used read only. It is simple
and correct, but it is a cleanup shaped API (it takes per bucket locks and reschedules), so it is
process context only.

The alternative is the RCU hash walk that `ctnetlink_dump_table` performs, using the inline
`nf_conntrack_get_ht(&hash, &hsize)` from `nf_conntrack.h`, which resolves the seqcount race against a
hash resize for you. It works from atomic context and is what a `conntrack -L` equivalent should use.
The nulls list requires the usual restart-on-nulls-mismatch dance.

Recommendation: implement the RCU walk, mirroring `ctnetlink_dump_table`, and document that the Lua
callback must be short. Prototype both if the walk turns out to be subtle on the target kernel.

### Events

    struct nf_ct_event_notifier {
        int (*ct_event)(unsigned int events, const struct nf_ct_event *item);
        int (*exp_event)(unsigned int events, const struct nf_exp_event *item);
    };
    void nf_conntrack_register_notifier(struct net *net, const struct nf_ct_event_notifier *nb);
    void nf_conntrack_unregister_notifier(struct net *net);

Caveats worth putting in the docs:

* there is exactly one notifier slot per netns. Registering while `ctnetlink` has one installed
  (anything running `conntrack -E`, or conntrackd) triggers a `WARN_ON_ONCE` and steals the slot.
  The binding should refuse to register twice from Lua and should say so in the error message;
* events only fire when the ecache extension is present, which requires
  `CONFIG_NF_CONNTRACK_EVENTS` and `sysctl net.netfilter.nf_conntrack_events=1`;
* callbacks fire in softirq **and** in process context: the ecache retry path redelivers missed
  `DESTROY` events from a workqueue (`ecache_work_evict_list` calls `nf_conntrack_event`,
  `nf_conntrack_ecache.c`). A `softirq` runtime handles both, `spin_lock_bh` is callable from process
  context, but do not write code that assumes softirq only;
* not verified yet: whether `nf_conntrack_unregister_notifier` sleeps (a `synchronize_rcu` would be
  typical). If it does, unregistering cannot run from the softirq runtime itself and teardown follows
  the soft-stop shape: cleanup in `release`, on a pinned object, as `netlink.channel` does. Settle
  this before implementing `unwatch`.

### Creating entries

`ctnetlink_create_conntrack` in `net/netfilter/nf_conntrack_netlink.c` is the reference
implementation. The shape is:

1. `nf_conntrack_alloc(net, zone, &orig_tuple, &repl_tuple, gfp)`;
2. set `ct->timeout`, status bits, and add the extensions you want (acct, mark, labels, ecache)
   *before* insertion;
3. for a NAT'ed entry, call `nf_nat_setup_info` while the entry is still unconfirmed;
4. `nf_conntrack_hash_check_insert(ct)`, which fails with `-EEXIST` if the tuple is taken.

Getting the reply tuple wrong is the classic way to end up with an entry that never matches traffic.
`nf_ct_invert_tuple` (exported) builds it from the original.

### Expectations

    struct nf_conntrack_expect *nf_ct_expect_alloc(struct nf_conn *me);
    void nf_ct_expect_init(struct nf_conntrack_expect *, unsigned int class, u_int8_t family,
                           const union nf_inet_addr *saddr, const union nf_inet_addr *daddr,
                           u_int8_t proto, const __be16 *src, const __be16 *dst);
    int nf_ct_expect_related(struct nf_conntrack_expect *expect, unsigned int flags);
    void nf_ct_expect_put(struct nf_conntrack_expect *exp);

`nf_ct_expect_related` consumes nothing: the caller still owns its reference and must put it. Set
`exp->timeout` before relating. `NF_CT_EXPECT_CLASS_DEFAULT` is 0. This is the mechanism behind every
ALG (FTP, SIP, TFTP) and is what lets a Lua helper pre-authorize a data connection.

### Labels are 128 bits

`struct nf_conn_labels` is `unsigned long bits[]` sized by `XT_CONNLABEL_MAXBIT` (127), 16 bytes. A
label set does not fit a Lua integer; `ct:labels()` returns a 16 byte binary string.

### Kconfig dependencies

`LUNATIK_CONNTRACK` needs `depends on NF_CONNTRACK` and `LUNATIK_NAT` needs `depends on NF_NAT` in
`Kconfig`, on top of the per feature guards below.

| Feature | Requires |
|---------|----------|
| everything here | `CONFIG_NF_CONNTRACK` |
| `ct:mark` | `CONFIG_NF_CONNTRACK_MARK` |
| `ct:labels` | `CONFIG_NF_CONNTRACK_LABELS` |
| `ct:counters` | `CONFIG_NF_CONNTRACK_ACCT` plus `sysctl net.netfilter.nf_conntrack_acct=1` |
| `conntrack.watch` | `CONFIG_NF_CONNTRACK_EVENTS` plus `nf_conntrack_events=1` |
| NAT | `CONFIG_NF_NAT` |
| masquerade | `CONFIG_NF_NAT_MASQUERADE` |
| IPv6 NAT | `CONFIG_IPV6` and `CONFIG_NF_NAT` |

Follow the existing `luaskb.c` precedent: guard optional methods with `#if defined(CONFIG_...)` so the
method is simply absent from the metatable, and let tests skip cleanly when it is missing.

Note that `nf_ct_netns_get(net, pf)` is what makes conntrack actually engage for a family. `iptable_nat`
and `nft_chain_nat` call it when a chain is registered. Without it, a Lua NAT hook can register
successfully and then never see a tracked packet on an otherwise idle box.

## Namespaces

Both `luanetfilter.c` and everything proposed here use `init_net`. That is a deliberate scope limit for
this project, not an oversight, but it constrains testing: NAT tests need two ends, so they use veth
pairs with the far end in a namespace and the NAT hook in `init_net`. Adding a `net` selector to hook
registration is tracked as a follow-up, not part of this epic.

## Sources

* `net/netfilter/nf_nat_core.c`, `nf_nat_inet_fn` and `nf_nat_register_fn`
* `net/netfilter/nf_nat_proto.c`, the `nf_nat_ipv4_ops` / `nf_nat_ipv6_ops` arrays and the
  `*_register_fn` wrappers
* `net/netfilter/nf_conntrack_netlink.c`, `ctnetlink_dump_table` and `ctnetlink_create_conntrack`
* `net/netfilter/nf_conntrack_core.c`, allocation, confirmation and iteration
* `net/ipv4/netfilter/iptable_nat.c` and `net/netfilter/nft_chain_nat.c`, minimal NAT chain registration
* in-tree Lunatik: `lib/luaskb.c`, `lib/luanetfilter.c`, `lunatik_core.c`

