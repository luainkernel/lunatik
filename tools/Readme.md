# Additional tools

## bench/xdp.sh

Measures what a call into the kernel Lua VM costs on the tree's own XDP path: a native
`XDP_PASS` program against the same program calling `bpf_luaxdp_run`, with a callback that only
sets the verdict and one that reads a packet byte first, each in a plain and in a percpu runtime.
`pktgen` floods a veth pair whose peer sits in a network namespace, every program counts the
packets it ran on in a per-CPU array, and the table carries the packets per second, the
nanoseconds per packet and what each row costs over the native one, with a per-CPU block below it.

```sh
sudo bash tools/bench/xdp.sh
sudo LUNATIK_BENCH_SECONDS=30 LUNATIK_BENCH_RUNS=5 bash tools/bench/xdp.sh
sudo LUNATIK_BENCH_CPUS="0 1 2" bash tools/bench/xdp.sh    # the contended case
```

`LUNATIK_BENCH_MISSED` is the percentage of generated-but-unprocessed packets above which no
delta is quoted, default 1. The script loads `pktgen` and leaves it loaded; everything else it
creates, it removes in a trap and again up front.

A veth pair is not a NIC, and the generator and the hook share the receiving CPU, so the absolute
rate is the pair's. What the trampoline costs is the row-to-row difference, and the script quotes
none unless every row ran on the same CPUs: under a flood the receive softirq can spill onto a
second CPU, and the row then goes faster for a reason that is not the code.

## debian_kernel_postinst_lunatik.sh

Under Debian, copy this script into /etc/kernel/postinst.d/
to have Lunatik installed on kernel upgrade:

```sh
sudo cp debian_kernel_postinst_lunatik.sh /etc/kernel/postinst.d/zz-update-lunatik
sudo chmod +x /etc/kernel/postinst.d/zz-update-lunatik
```

To check it works:

```sh
sudo dpkg-reconfigure linux-image-`uname -r`
```

## oops.sh

Captures the last kernel oops before a reboot takes it away: the `dmesg` block, the instructions
around the faulting one in the installed module, and the processes left in D state.

```sh
tools/oops.sh > scratch/oops-$(date +%F).txt
```

A saved dump, `journalctl -k -b -1 -o cat` after the reboot where the journal is persistent,
is read the same way: `tools/oops.sh <dump>`.

## pr-status.sh

Reports the open pull requests as GitHub has them: base and mergeability, commits and unsquashed
fixups, size, CI conclusion and labels. `--ready` keeps the ones reviewed by a workflow, green on
CI, with no fixup pending and mergeable.

```sh
GH_TOKEN=... bash tools/pr-status.sh            # every open pull request
GH_TOKEN=... bash tools/pr-status.sh --ready    # what a maintainer can pick up
GH_TOKEN=... bash tools/pr-status.sh 814 822    # these ones
```

## watchdog.sh

Runs a Lunatik script and stops it if the host loses the connectivity it had before the run,
the loopback or the default route's gateway; a script that cuts the machine off cannot be
stopped by hand afterwards.

```sh
sudo bash tools/watchdog.sh examples/ifquarantine/control
sudo LUNATIK_WATCHDOG_GRACE=10 bash tools/watchdog.sh examples/filter/sni softirq percpu
```

