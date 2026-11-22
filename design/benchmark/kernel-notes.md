# Kernel notes

What the method rests on, read in the 6.8.12 source this host's kernel is built from, with the line
each fact was read at. The benchmark runs on this host only, so these are facts about it; a run on
another kernel reads them again there.

## Clock

`linux.time` is `ktime_get_real_ns()` on every ref measured, `lib/lualinux.c:143` at v4.4.1 and
`lib/lualinux.c:145` at v5.1, the only clock a script reaches on v4.4.1. It is `CLOCK_REALTIME`,
which `settimeofday` or NTP can step: a step inside a timed loop shows as one outlier of a batch,
which the median absorbs. The clocksource is `arch_sys_counter`
(`/sys/devices/system/clocksource/clocksource0/current_clocksource`). A loop of 10 ms or more keeps
the clock's resolution out of the number.

## What the host does not give

The host is a virtual machine on Apple silicon, six CPUs, one NUMA node, no `cpufreq` directory.
`perf stat -e cycles,instructions` reports both `<not supported>`, so every number is a time, not a
count of cycles. The steal column of `/proc/stat` reads 0, so the hypervisor's share is not visible
either: it shows only as spread, which the repetition across rounds measures.

## setjmp on arm64

The kernel has `CONFIG_SHADOW_CALL_STACK=y`, which keeps the shadow stack pointer in x18. The klibc
of v4.4.1 (`24e0fc1b`) carries `3dfe5b3e`, which saves x18 across `setjmp`/`longjmp`, and v5.0 and
v5.1 carry the same patch as `10627f3e`, so a Lua error on any of the three refs restores it.

## pktgen

`xmit_mode netif_receive` (`net/core/pktgen.c:3517`) hands each packet to `netif_receive_skb()` in a
loop under `local_bh_disable()` (`pktgen.c:3522`), in the `kpktgend_<cpu>` thread bound to that CPU.
The receive path runs there, bottom halves off, as a softirq runtime is made for:

- generic XDP runs in `__netif_receive_skb_core` (`net/core/dev.c:5432`);
- IPv4 then reaches `ip_rcv`, whose `NF_HOOK(NFPROTO_IPV4, NF_INET_PRE_ROUTING, ...)` is
  `net/ipv4/ip_input.c:569`; before it, `ip_rcv_core` drops a packet whose type is
  `PACKET_OTHERHOST` (`ip_input.c:465`), so the packets carry the interface's own MAC as their
  destination, or no hook sees them.

pktgen reports packets per second in its result line (`pktgen.c:3328`). No veth pair is needed for
either hook: one interface takes the injection.

A transmit through a veth reaches the peer by `__netif_rx()`, or by the peer's NAPI ring when an XDP
program or GRO gives it one (`drivers/net/veth.c:316-321`, `veth_xmit` at `veth.c:343`).
`netif_rx_internal` (`net/core/dev.c:5114`) queues to the backlog of the CPU it runs on
(`dev.c:5140`) unless RPS steers it, and every `rps_cpus` on this host reads `00`. The set does not need this
path; it is here for a native XDP number, should one be wanted.

## kprobe

`perf bench syscall basic` (perf 6.8.12) times `getppid(2)` calls, 0.12 µs each on this host
unprobed. The syscall's entry is `__arm64_sys_getppid` in `/proc/kallsyms` on aarch64, and
`__x64_sys_getppid` on x86_64. A probe there fires once per call, in the task that calls it.

## Slab

`CONFIG_RANDOM_KMALLOC_CACHES=y`: a `kmalloc` of one size lands in one of the `kmalloc-rnd-NN-<size>`
caches, 195 lines of `/proc/slabinfo` here, so the memory of a runtime is read as the sum over every
cache of a size, before and after creating the runtimes.

