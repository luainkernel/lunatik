# Per-CPU scripts

`lunatik run [--context=softirq | hardirq] --percpu <script>` creates one runtime per CPU id and
dispatches a callback to the runtime of the CPU it fires on. The runtimes share the
registrations a script makes once for all of them, a netfilter hook and a kprobe, and each reads
its own id with `lunatik.cpu()`.

A runtime is a CPU, not a connection. A netfilter hook runs in the packet's own processing path
(`NF_HOOK` from `ip_rcv`, `ip_output` and their peers), so the runtime is whichever CPU that path
is on, and the packets of one connection reach several. Over loopback and veth the transmit side
queues the packet to its own CPU's backlog (`__netif_rx` from `loopback_xmit` and
`veth_forward_skb`), which the receive softirq drains on that CPU. On a NIC it is the CPU the
queue's interrupt is bound to; with RPS, the one the queue's map picks from the flow hash, stable
while the map is; with RFS, the one where the flow's last `recvmsg` ran, which follows a reader
that migrates. An outbound hook reached from a `sendmsg` runs on the sending process's CPU, but
the same hook number also fires from the receive softirq, forwarding a packet or sending a RST for
one, and from the timer softirq on a retransmission, where it is that softirq's CPU. A kprobe
reaches the runtime of the CPU the probed call ran on.

State that must see a whole flow therefore belongs in something the runtimes share, a table
published in `lunatik._ENV` or the conntrack mark; the runtime holds what is per-CPU, a counter or
a cache. An `rcu.table()` the script body creates is not shared: the body runs once per runtime, so
each gets its own.

`lunatik run` creates one runtime per possible CPU and runs their bodies one after another, so a
body publishes the shared table when it finds none, and the bodies after it take that one:

```Lua
local lunatik = require("lunatik")
local rcu     = require("rcu")

local env = lunatik._ENV
env.flows = env.flows or rcu.table()
local flows = env.flows
```

The table stays in `lunatik._ENV` after the runtimes stop, until a script sets `env.flows` to nil.

A binding whose global registration the runtimes cannot share refuses a percpu runtime with
`not allowed in a percpu runtime`, which its `@raise` says.

