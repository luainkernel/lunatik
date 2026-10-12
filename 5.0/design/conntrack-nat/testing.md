# Testing conntrack and NAT

Lunatik's tests are shell scripts emitting KTAP, driving a kernel Lua script and asserting on what it
prints to `dmesg` or on what userspace observes. `tests/skb/connmark.sh` is the closest existing model
for this project: it engages conntrack with an `nft` rule, runs a hook, and cross checks the result
with `conntrack -L`. Read it before writing anything new.

Run everything with `sudo lunatik test`, one suite with `sudo lunatik test conntrack`.

## What is missing from the harness

Stateless netfilter tests get away with loopback traffic in `init_net`. NAT does not: a translation
that is not observed from the other end of a real path is not proven. The suite needs a small
namespace helper, added once, in `tests/netns.sh`:

* create a namespace with a veth pair, one end inside, one end in `init_net`;
* address both ends, bring them up, and enable forwarding when the test needs it;
* run a command inside the namespace;
* tear it all down on exit, including on failure.

Build this before the NAT code, not after. A NAT feature that cannot be observed is a NAT feature that
cannot be reviewed.

Requirements, all of which existing tests already assume or skip on: `iproute2`, `nftables`,
`conntrack-tools`, plus `socat` or `nc` for the traffic in the NAT tests.

## Test matrix

Fill this in as the phases land. Each row is one `.sh` plus one `.lua`, following the convention that
the description of the test lives in the shell script and the Lua file carries a single line pointing
back at it.

### `tests/conntrack/`

| Test | Proves |
|------|--------|
| `get.sh` | `conntrack.get` returns an object plus the right `nf.ct.info` state for a new flow and a reply; a `notrack`'d flow yields `nil` plus `nf.ct.info.UNTRACKED` |
| `tuple.sh` | original and reply tuples match what `conntrack -L` reports for the same flow, both IPv4 and IPv6 |
| `status.sh` | `SEEN_REPLY` and `ASSURED` appear as the flow progresses; `ct:tcpstate()` walks SYN_SENT to ESTABLISHED |
| `timeout.sh` | `ct:timeout()` decreases; `ct:refresh(ms)` raises it |
| `counters.sh` | packet and byte counts match the traffic sent (skip without `CONFIG_NF_CONNTRACK_ACCT`) |
| `mark.sh` | `ct:mark` and `skb:connmark` read and write the same field |
| `labels.sh` | `ct:labels()` returns the 16 byte bitmap `conntrack -L` shows after an `nft ct label set` rule (skip without `CONFIG_NF_CONNTRACK_LABELS`) |
| `meta.sh` | `ct:zone()`, `ct:id()` and `ct:helper()` return what `conntrack -L` reports for a flow with an nft-assigned helper |
| `lifetime.sh` | a `ct` stashed in a Lua global and used after the hook returned does not oops. This is the one that justifies the refcount |
| `table.sh` | `conntrack.count` tracks entries; `lookup` finds a flow by tuple and misses on a bogus one; `each` sees a known flow and can stop early |
| `events.sh` | NEW and DESTROY arrive for a short flow; registering twice raises instead of stealing the slot (skip without `CONFIG_NF_CONNTRACK_EVENTS`) |
| `new.sh` | `conntrack.new` inserts an entry visible in `conntrack -L`; a duplicate tuple raises |
| `expect.sh` | an expectation appears in `conntrack -L expect` and the matching flow arrives as `RELATED` |

### `tests/nat/`

| Test | Proves |
|------|--------|
| `dnat.sh` | a connection to one port lands on a listener on another; the server sees the original source |
| `snat.sh` | a connection from the namespace arrives with the rewritten source address |
| `masquerade.sh` | same, with the interface address chosen automatically |
| `redirect.sh` | traffic aimed elsewhere is redirected to a local listener |
| `once.sh` | the Lua hook runs once per connection per direction, not per packet (count invocations against packets sent) |
| `manip.sh` | asking for SNAT at `PRE_ROUTING` raises rather than silently doing nothing |
| `unregister.sh` | collecting the hook handle unregisters it and traffic flows untranslated afterwards |
| `ipv6.sh` | DNAT over IPv6 (skip without `CONFIG_IPV6`) |

`once.sh` is the one that proves the design claim from `kernel-notes.md`. Write it before building on
the API: if the Lua hook turns out to run per packet, the API is wrong, and that is much cheaper to
learn before anything depends on it.

Where a test needs to count hook invocations, use one shape across the suite: the hook increments a
counter in an `rcu.table` and the shell asserts on the delta across the run, never on the absolute
value, so a previous run cannot make a test pass.

    local shared = rcu.table()
    shared.calls = (shared.calls or 0) + 1

## Conventions to follow

* skip, do not fail, when the kernel lacks a config. Copy the `skip_all` shape from
  `tests/skb/connmark.sh`, including the `ktap_skip` per planned test so the plan count stays honest;
* mark `dmesg` before the run and read only what came after (`mark_dmesg` / `dmesg_since`);
* `check_dmesg` at the end so a kernel warning fails the test even when the assertions passed;
* `lunatik run` exits 0 even when the script fails to load, so assert on output, never on exit status;
* clean up in a `trap`, and call the cleanup once up front too, so a previous crashed run does not
  poison this one;
* every new test gets a bullet in `tests/README.md` and a line in the suite's `run.sh`, in the same
  commit. A new suite also gets added to the list in the top level `README.md`.

## Manual smoke test

Useful while developing, before the automated test exists:

    sudo make install && sudo lunatik reload
    sudo lunatik run examples/l7lb softirq
    sudo conntrack -L
    sudo conntrack -E

Watch `dmesg -w` in another terminal. If the machine hangs, the usual cause is a sleeping call reached
from softirq context; check `kernel-notes.md` for which entry points are allowed where.

