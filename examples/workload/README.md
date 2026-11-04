# workload

**workload** is a scheduler composed of the
[sched_ext/scx](https://github.com/sched-ext/scx) framework and eBPF. It
includes an eBPF program which keeps the dispatch queue and slice of each task in
eBPF task storage, and a Lua kernel script which sets the dispatch queue and slice
of the tasks seen for the first time according to a Lua [policy table](workload.lua#L13).

Needs a kernel 6.12 or later with `CONFIG_SCHED_CLASS_EXT`, clang, the libbpf headers 1.2 or later and
`bpftool`.

Install and load the scheduler, from the root of the Lunatik checkout:

```sh
sudo make btf_install         # needed to export the 'bpf_luascx_run' kfunc, before the build
make clean && make            # builds the modules again, now with their BTF
sudo make install             # installs Lunatik and the examples
make ebpf                     # builds the sched_ext/eBPF program, which bpftool loads from the checkout
sudo lunatik run --context=hardirq --percpu examples/workload/workload
```

`make ebpf` skips `workload` when the running kernel has no `/sys/kernel/sched_ext`.

Load and attach the struct_ops scheduler:

```sh
sudo bpftool struct_ops register examples/workload/scheduler.o
```

Verify:

```sh
sudo bpftool struct_ops show
```

Task storage cannot be dumped with `bpftool map dump`, so to see a task's class, change the
policy and watch where the task lands, for example with `perf sched` or `schedtop`.

Tear it down with:

```sh
sudo bpftool struct_ops unregister name workload_ops
sudo lunatik stop examples/workload/workload
```

