# workload

**workload** is a scheduler composed by
[sched_ext/scx](https://github.com/sched-ext/scx) framework and eBPF. It
includes an eBPF program which uses an eBPF map to assign queues and slices to
tasks and a Lua kernel script to set dispatch queue and slice to the tasks seen
for the first time according to a Lua [policy table](workload.lua#L13).

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

Load and attach the struct_ops scheduler:

```sh
sudo bpftool struct_ops register examples/workload/scheduler.o
```

Verify and test:

```sh
sudo bpftool struct_ops show
sudo bpftool map dump name task_classes   # each classified task by pid, with its queue and slice
```

Tear it down with:

```sh
sudo bpftool struct_ops unregister name workload_ops
sudo lunatik stop examples/workload/workload
```

