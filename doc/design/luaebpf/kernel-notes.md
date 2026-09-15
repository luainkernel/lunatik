# Kernel notes: Lua to eBPF

Reference sheet for `luaebpf`. Everything below is read from source at a pinned revision and cited
so it can be checked without trusting this document. Nothing here is built or run. Re-check on the
kernel you target; line numbers move.

| Tree | Revision |
|------|----------|
| linux | tag `v7.2` (`8d3ae59288f1e7d58d76558a6ee96d533bc5019f`); older tags only to date a facility |
| lunatik | `origin/master` at `22c5afe26049b3adf4da7b05a512411ef262e29c` |
| lua (submodule `luainkernel/lua`) | `d7ca49b3a9c44278078b4e12a7cb26bf4c9e30fd`, Lua 5.5.0 with the `_KERNEL` patch |
| lunatikc | pull request #742, head `210deebd28060d60a6ddb0e81fda7db1f35a2f23` |
| llvm-project | tag `llvmorg-23.1.1` (`6dfe1677ab8dffbc6ec13d53a1e0215d75147689`) |
| iovisor/bcc | `8a46070fe08d646e2781fba69586d755da766aa2` |
| oracle/dtrace | `61fea621160ea4b6302874c62a723da105b44883` |

URLs are `https://github.com/<owner>/<repo>/blob/<tag-or-sha>/<path>#L<a>-L<b>`. Kernel paths
below are relative to `https://github.com/torvalds/linux/blob/v7.2/`.

## Who loads a program: the CLI, through `bpf(2)`

This is the fact that decides the shape of the tool. A verified program enters the kernel through
`BPF_PROG_LOAD` and is attached through `BPF_LINK_CREATE`. Both are reachable from userspace with
`bpf(2)`, and reachable from a kernel module only through one exported entry point that lacks four
things the compiler needs.

### The module path exists

`kern_sys_bpf(int cmd, union bpf_attr *attr, unsigned int size)` is defined at
[kernel/bpf/syscall.c#L6578](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/syscall.c#L6578)
and exported as `EXPORT_SYMBOL_NS(kern_sys_bpf, "BPF_INTERNAL")` at
[#L6618](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/syscall.c#L6618). Every command but
`BPF_PROG_TEST_RUN` goes to `____bpf_sys_bpf`, whose allowlist is `BPF_MAP_CREATE`,
`BPF_MAP_DELETE_ELEM`, `BPF_MAP_UPDATE_ELEM`, `BPF_MAP_FREEZE`, `BPF_MAP_GET_FD_BY_ID`,
`BPF_PROG_LOAD`, `BPF_BTF_LOAD`, `BPF_LINK_CREATE` and `BPF_RAW_TRACEPOINT_OPEN`
([#L6551-L6566](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/syscall.c#L6551-L6566)).
Inputs are read through `bpfptr_t`, which is a user or a kernel pointer
([include/linux/bpfptr.h#L49-L57](https://github.com/torvalds/linux/blob/v7.2/include/linux/bpfptr.h#L49-L57)).
The in-tree caller is `kernel/bpf/preload/bpf_preload_kern.c`, a module that loads a light
skeleton, takes its links with `bpf_link_get_from_fd` and declares `MODULE_IMPORT_NS("BPF_INTERNAL")`
([bpf_preload_kern.c](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/preload/bpf_preload_kern.c)).
So a module can load, verify, JIT and attach. The design does not use it, for the four reasons
below.

### 1. A kernel log buffer fails the load

The verifier log is written to a user pointer. `struct bpf_verifier_log.ubuf` is `char __user *`
([include/linux/bpf_verifier.h#L744](https://github.com/torvalds/linux/blob/v7.2/include/linux/bpf_verifier.h#L744),
and `struct bpf_log_attr.ubuf` at
[#L767](https://github.com/torvalds/linux/blob/v7.2/include/linux/bpf_verifier.h#L767)).
`bpf_log_attr_init` converts the attribute with `u64_to_user_ptr`
([kernel/bpf/log.c#L831-L832](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/log.c#L831-L832));
`bpf_verifier_vlog` writes with `copy_to_user`
([#L90](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/log.c#L90),
[#L127-L140](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/log.c#L127-L140)) and clears
`ubuf` on a fault ([#L146](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/log.c#L146));
`bpf_vlog_finalize` returns `-EFAULT` when `ubuf` and `len_total` disagree
([#L290-L291](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/log.c#L290-L291)), and
`bpf_check` adopts that error even after a successful verification
([kernel/bpf/verifier.c#L19983-L19990](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/verifier.c#L19983-L19990)).
The in-tree kernel-mode skeleton sets `log_level` and `log_buf` only under `#ifndef __KERNEL__`
([tools/lib/bpf/skel_internal.h#L400-L412](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/skel_internal.h#L400-L412)).
A module-side load therefore gets an errno and no text. A compiler whose error message is the
verifier's rejection cannot live there.

### 2. The symbol is namespaced against this use

The commit that split the helper says the kernel function "can only be used by the kernel light
skeleton directly"
([86f44fcec22c](https://github.com/torvalds/linux/commit/86f44fcec22ce2979507742bc53db8400e454f46),
2022-08-09); the commit that added the namespace says it is there "to prevent abuse"
([f88886de0927](https://github.com/torvalds/linux/commit/f88886de0927a2adf4c1b4c5c1f1d31d2023ef74),
2025-04-25); the comment above the function says the same
([syscall.c#L6572-L6577](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/syscall.c#L6572-L6577)).
The export exists and its stated contract excludes a caller that is not a light skeleton.

### 3. The tree's own kfuncs need a module BTF fd

A kfunc call names its BTF through `insn->off`: offset 0 is vmlinux, any other offset indexes
`attr.fd_array`, which must hold a module BTF fd
([verifier.c#L2493](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/verifier.c#L2493),
"kfunc offset > 0 without fd_array is invalid" at
[#L2513](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/verifier.c#L2513), "BTF fd for
kfunc is not a module BTF" at
[#L2529](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/verifier.c#L2529)).
`BPF_BTF_GET_FD_BY_ID` is not in the allowlist above, so a module-loaded program cannot call
`bpf_luaxdp_run` or any other Lunatik kfunc. Userspace can: libbpf walks module BTFs with
`bpf_btf_get_next_id`
([tools/lib/bpf/libbpf.c#L5810-L5833](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/libbpf.c#L5810-L5833)),
appends the fd to `fd_array`
([#L8805-L8816](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/libbpf.c#L8805-L8816)),
patches the call's `imm` and `off`
([#L6484-L6485](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/libbpf.c#L6484-L6485))
and passes the array at load
([#L7977](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/libbpf.c#L7977)). That is how
every `.bpf.c` in the tree loads today.

### 4. No pinned object by path

`BPF_OBJ_GET` and `BPF_OBJ_PIN` are absent from the allowlist. The tree's map API is by path
(`bpf.hash("/sys/fs/bpf/...")`, `luabpf_map_get` through `kern_path`,
[lib/luabpf.c](https://github.com/luainkernel/lunatik/blob/22c5afe26049b3adf4da7b05a512411ef262e29c/lib/luabpf.c)),
and a program loaded by a module could reach a pinned map only by id
(`BPF_MAP_GET_FD_BY_ID`, `CAP_SYS_ADMIN`).

### What the CLI has

`bin/lunatik` runs as root on the machine whose kernel runs the program
([bin/lunatik#L1](https://github.com/luainkernel/lunatik/blob/22c5afe26049b3adf4da7b05a512411ef262e29c/bin/lunatik#L1),
Lua 5.4, talking to `/dev/lunatik` at
[#L17-L24](https://github.com/luainkernel/lunatik/blob/22c5afe26049b3adf4da7b05a512411ef262e29c/bin/lunatik#L17-L24)).
From there `bpf(2)` gives the log, `BPF_BTF_GET_FD_BY_ID`, `BPF_OBJ_PIN`/`BPF_OBJ_GET` and
`BPF_LINK_CREATE` with no namespaced symbol. `link_create` is `static`
([syscall.c#L5844](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/syscall.c#L5844)) and
dispatches to the per-type attach functions: XDP
([#L5912-L5913](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/syscall.c#L5912-L5913)),
tcx ([#L5918](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/syscall.c#L5918)), netfilter
([#L5923](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/syscall.c#L5923)), cgroup
([#L5872](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/syscall.c#L5872)), tracing and LSM
([#L5875](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/syscall.c#L5875)), struct_ops
([#L5853](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/syscall.c#L5853)). None of those
is exported, so attaching from a module is `kern_sys_bpf(BPF_LINK_CREATE)` or nothing; the CLI
attaches with the syscall, as `bpftool net attach` and `tc filter add` do in the suites today
([tests/xdp/test_xdp.sh#L83-L85](https://github.com/luainkernel/lunatik/blob/22c5afe26049b3adf4da7b05a512411ef262e29c/tests/xdp/test_xdp.sh#L83-L85),
[tests/tc/test_tc.sh#L29-L31](https://github.com/luainkernel/lunatik/blob/22c5afe26049b3adf4da7b05a512411ef262e29c/tests/tc/test_tc.sh#L29-L31)).

Capabilities are `current`'s: `bpf_prog_load` checks `CAP_BPF` at
[syscall.c#L3015](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/syscall.c#L3015) and
`CAP_NET_ADMIN` for network types at
[#L3043](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/syscall.c#L3043). The CLI runs
under `sudo`.

## The verifier the emitter designs against

### Limits

| Limit | Value | Where |
|-------|-------|-------|
| verifier work budget, instructions simulated across all paths | 1,000,000 | [include/linux/bpf.h#L2386](https://github.com/torvalds/linux/blob/v7.2/include/linux/bpf.h#L2386); rejection "BPF program is too large" at [verifier.c#L17369](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/verifier.c#L17369); the summary line at [#L18611](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/verifier.c#L18611) |
| program size, privileged | 1,000,000 instructions; unprivileged 4096 | [syscall.c#L3034](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/syscall.c#L3034); `BPF_MAXINSNS` at [include/uapi/linux/bpf_common.h#L54](https://github.com/torvalds/linux/blob/v7.2/include/uapi/linux/bpf_common.h#L54) |
| stack per frame | 512 bytes | [include/linux/filter.h#L100](https://github.com/torvalds/linux/blob/v7.2/include/linux/filter.h#L100); per-subprogram check at [verifier.c#L5138](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/verifier.c#L5138), combined check at [#L5151](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/verifier.c#L5151) |
| call depth | 16 frames | [include/linux/bpf_verifier.h#L407](https://github.com/torvalds/linux/blob/v7.2/include/linux/bpf_verifier.h#L407), raised from 8 by [2148794eeaf2](https://github.com/torvalds/linux/commit/2148794eeaf2a898adc791e9472eb80ea55984da) (2026-06-13, v7.2); rejection at [verifier.c#L5221](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/verifier.c#L5221) |
| subprograms | 256 | [bpf_verifier.h#L782](https://github.com/torvalds/linux/blob/v7.2/include/linux/bpf_verifier.h#L782); "too many subprograms" at [verifier.c#L2364](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/verifier.c#L2364) |
| register arguments per call | 5 | [bpf.h#L1209](https://github.com/torvalds/linux/blob/v7.2/include/linux/bpf.h#L1209) |
| tail calls | 33 | [bpf.h#L2387](https://github.com/torvalds/linux/blob/v7.2/include/linux/bpf.h#L2387) |
| `may_goto` and iterator bound per invocation | 8,388,608 | `BPF_MAX_LOOPS`, [bpf.h#L2393](https://github.com/torvalds/linux/blob/v7.2/include/linux/bpf.h#L2393) |

### Rules that shape the subset

* **No recursion.** "recursive call from %s() to %s()" at
  [verifier.c#L2954](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/verifier.c#L2954).
* **No call through a register.** Calls are `BPF_PSEUDO_CALL` to a subprogram
  ([include/uapi/linux/bpf.h#L1390](https://github.com/torvalds/linux/blob/v7.2/include/uapi/linux/bpf.h#L1390)),
  `BPF_PSEUDO_KFUNC_CALL` to a BTF id
  ([#L1394](https://github.com/torvalds/linux/blob/v7.2/include/uapi/linux/bpf.h#L1394)) or a
  helper by number. A Lua value that holds a function is a compile-time constant or a compile
  error. Indirect *jumps* exist since v6.19 (`gotox`, `BPF_MAP_TYPE_INSN_ARRAY`,
  [#L1049](https://github.com/torvalds/linux/blob/v7.2/include/uapi/linux/bpf.h#L1049);
  `check_indirect_jump` at
  [verifier.c#L17176](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/verifier.c#L17176));
  the emitter does not need them.
* **Loops.** Three accepted forms: a bounded loop the verifier simulates (every simulated
  instruction counts against the budget); `bpf_loop` and the open-coded iterators
  (`bpf_iter_num_new` registered `KF_ITER_NEW` at
  [kernel/bpf/helpers.c#L4887](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/helpers.c#L4887));
  and `may_goto` (`BPF_JCOND` at
  [uapi/linux/bpf.h#L45](https://github.com/torvalds/linux/blob/v7.2/include/uapi/linux/bpf.h#L45),
  `BPF_MAY_GOTO` at [#L58](https://github.com/torvalds/linux/blob/v7.2/include/uapi/linux/bpf.h#L58)),
  a conditional jump the kernel takes after `BPF_MAX_LOOPS` iterations, so a loop whose header
  carries one is accepted whatever its condition. Lua's numeric `for` computes its iteration count
  up front (`forprep`,
  [lvm.c#L223-L259](https://github.com/luainkernel/lua/blob/d7ca49b3a9c44278078b4e12a7cb26bf4c9e30fd/lvm.c#L223-L259))
  and `OP_FORLOOP` counts it down
  ([lopcodes.h#L333-L334](https://github.com/luainkernel/lua/blob/d7ca49b3a9c44278078b4e12a7cb26bf4c9e30fd/lopcodes.h#L333-L334)):
  a counted loop by construction. Constant bounds become a bounded loop; anything else gets a
  `may_goto` header.
* **Exceptions are one way.** `bpf_throw`
  ([helpers.c#L3388](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/helpers.c#L3388))
  unwinds to the program's exception callback and never returns. `pcall` cannot be compiled; the
  design does not emit `bpf_throw` either, a failed check returns the program's default verdict.
* **A callee answers through R0 and through the caller's stack, and nothing else.**
  `set_callee_state` copies R1-R5 into the callee, types and ranges included, so `PTR_TO_CTX`,
  `PTR_TO_PACKET` and `PTR_TO_STACK` all propagate
  ([verifier.c#L9478-L9490](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/verifier.c#L9478-L9490));
  R0 and R6-R9 arrive uninitialised, and the callee may write into its caller's stack
  ([#L9106-L9109](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/verifier.c#L9106-L9109)).
  `prepare_func_exit` hands the caller whatever R0 held at the callee's exit
  ([#L9762-L9763](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/verifier.c#L9762-L9763)),
  and the verifier explores every exit against every path after the call, so an exit that leaves
  R0 uninitialised is rejected at the caller's first use of it, "R%d !read_ok"
  ([#L3110](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/verifier.c#L3110)). This is
  why a failed check in a subprogram raises a flag in the caller's frame and still sets R0.
  Passing a stack pointer to a *static* subprogram is safe against the BTF argument check:
  `btf_check_subprog_call` only marks a static subprogram unreliable on a mismatch, where a
  global one fails the load
  ([#L9248-L9274](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/verifier.c#L9248-L9274)),
  so the emitter keeps declaring every parameter `long` in `.BTF`.
* **Division and modulo by zero do not trap.** `ALU64` division by zero sets the destination to
  zero and modulo by zero leaves the dividend
  ([Documentation/bpf/standardization/instruction-set.rst#L351-L357](https://github.com/torvalds/linux/blob/v7.2/Documentation/bpf/standardization/instruction-set.rst#L351-L357)).
  Lua raises. The emitter tests the divisor and takes the failure path, so compiled and
  interpreted code agree on every input the interpreted code accepts.
* **No heap, no GC.** `BPF_MAP_TYPE_ARENA`
  ([uapi/linux/bpf.h#L1048](https://github.com/torvalds/linux/blob/v7.2/include/uapi/linux/bpf.h#L1048))
  is a typed address range, not a Lua heap. Runtime tables and strings are refused; a table
  literal of constants folds at compile time or is the proxy of a map.
* **GPL.** A kfunc call from a non-GPL program is refused at
  [verifier.c#L2708](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/verifier.c#L2708);
  an LSM program must be GPL compatible
  ([kernel/bpf/bpf_lsm.c#L125](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/bpf_lsm.c#L125)).
  The emitter writes `"Dual MIT/GPL"`, as the tree's stubs do.
* **Sleeping.** `can_be_sleepable`
  ([verifier.c#L19303](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/verifier.c#L19303),
  rejection at [#L19349](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/verifier.c#L19349))
  lists the program types that accept `BPF_F_SLEEPABLE`: tracing, LSM (with the per-hook
  `sleepable_lsm_hooks`), uprobes, struct_ops, syscall. A sleepable kfunc from a non-sleepable
  program is refused at
  [#L12981](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/verifier.c#L12981). The
  trampoline's Lua callback can never run there: `lunatik_ebpf_lookupruntime` refuses a
  process-context runtime
  ([lunatik_ebpf.h#L35-L40](https://github.com/luainkernel/lunatik/blob/22c5afe26049b3adf4da7b05a512411ef262e29c/lunatik_ebpf.h#L35-L40)),
  and an IRQ-context runtime may not sleep. A compiled program loaded sleepable may.

## The context a network program reads

* **Every XDP context access is exactly four bytes, and none is a write.**
  `__is_valid_xdp_access` rejects a size other than `sizeof(__u32)` and any offset the size does
  not divide
  ([net/core/filter.c#L9341-L9351](https://github.com/torvalds/linux/blob/v7.2/net/core/filter.c#L9341-L9351));
  `xdp_is_valid_access` refuses `egress_ifindex` outside a devmap program, refuses every write
  unless the program is offloaded, and refuses an `LDSX` load of `data`, `data_meta` or
  `data_end`
  ([#L9353-L9395](https://github.com/torvalds/linux/blob/v7.2/net/core/filter.c#L9353-L9395)).
  Those three yield `PTR_TO_PACKET`, `PTR_TO_PACKET_META` and `PTR_TO_PACKET_END`, so the
  four-byte load `convert_ctx_access` rewrites gives the program a full pointer.
* **What `BPF_PROG_TEST_RUN` gives an XDP program.** `xdp_convert_md_to_buff` refuses a non-zero
  `egress_ifindex`, refuses an `rx_queue_index` without an `ingress_ifindex`, and for a non-zero
  `ingress_ifindex` requires the device to exist in the caller's netns, the queue index to be
  below `real_num_rx_queues`, and that queue's `xdp_rxq` to be registered
  ([net/bpf/test_run.c#L1274-L1317](https://github.com/torvalds/linux/blob/v7.2/net/bpf/test_run.c#L1274-L1317)).
  Every device registers its generic rx queues' `xdp_rxq` in `netif_alloc_rx_queues`
  ([net/core/dev.c#L11177-L11184](https://github.com/torvalds/linux/blob/v7.2/net/core/dev.c#L11177-L11184)),
  so loopback with queue 0 is a context every machine can supply, with no veth and no attach.

* **A `__sk_buff` write is four bytes, and only some fields take one.**
  `tc_cls_act_is_valid_access` allows a write to `mark`, `tc_index`, `priority`, `tc_classid`,
  `cb[0..4]`, `tstamp` and `queue_mapping` and to nothing else
  ([net/core/filter.c#L9273-L9292](https://github.com/torvalds/linux/blob/v7.2/net/core/filter.c#L9273-L9292));
  `bpf_skb_is_valid_access`'s default arm takes a write only at `size_default`, four bytes
  ([#L8952-L8962](https://github.com/torvalds/linux/blob/v7.2/net/core/filter.c#L8952-L8962)),
  and `data`, `data_meta` and `data_end` are four-byte reads that yield packet pointers
  ([#L8920-L8929](https://github.com/torvalds/linux/blob/v7.2/net/core/filter.c#L8920-L8929)).
  That set is kernel policy rather than layout, so BTF cannot supply it and the program type's
  module carries it.
* **What `BPF_PROG_TEST_RUN` gives a TC program.** `convert___skb_to_skb` refuses a `ctx_in`
  with anything non-zero outside `mark`, `priority`, `ingress_ifindex`, `ifindex`, `cb`,
  `data_end`, `tstamp`, `wire_len`, `gso_segs`, `gso_size` and `hwtstamp`, and copies `mark`,
  `priority`, `ingress_ifindex`, `tstamp` and `cb` into the skb
  ([net/bpf/test_run.c#L925-L1003](https://github.com/torvalds/linux/blob/v7.2/net/bpf/test_run.c#L925-L1003));
  `convert_skb_to___skb` writes them back into `ctx_out`
  ([#L1011](https://github.com/torvalds/linux/blob/v7.2/net/bpf/test_run.c#L1011)), so a
  `priority` write is observable. `skb->len` is the bytes handed in, and `ctx_in.len` must be
  zero. **A hash cannot be supplied**: it sits in a range `ctx_in` must leave zero and the skb
  the test run builds has none, so `skb.hash` answers 0.
* **Section names.** libbpf maps `tcx/ingress` and `tcx/egress` to `SCHED_CLS` with the matching
  `expected_attach_type`, `tc` to `SCHED_CLS` with none, and `xdp` to `XDP`
  ([tools/lib/bpf/libbpf.c#L10101-L10146](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/libbpf.c#L10101-L10146)),
  so an object whose entry sits in the right section needs no type argument on the way in.

## The packet a network program reads

* **The reads a kernel script already has.** `LUADATA_NEWINT_GETTER` is
  `*(T##_t *)luadata_checkbounds(...)` ([lib/luadata.c#L43-L51](https://github.com/luainkernel/lunatik/blob/22c5afe26049b3adf4da7b05a512411ef262e29c/lib/luadata.c#L43-L51)):
  a host-byte-order load of the exact width, zero-extended for the unsigned names and
  sign-extended for the signed ones. The method table
  ([#L201-L336](https://github.com/luainkernel/lunatik/blob/22c5afe26049b3adf4da7b05a512411ef262e29c/lib/luadata.c#L201-L336)) publishes `getbyte` (an alias of `getuint8`),
  `getint8`, `getuint8`, `getint16`, `getuint16`, `getint32`, `getuint32`, `getint64`,
  `getnumber` (an alias of `getint64`) and `getstring`, plus `__len`. `LUADATA_NEWINT` is
  instantiated for `int64` and not for `uint64` ([#L68-L74](https://github.com/luainkernel/lunatik/blob/22c5afe26049b3adf4da7b05a512411ef262e29c/lib/luadata.c#L68-L74)), so
  there is no `getuint64`: a Lua integer is 64-bit signed, and an unsigned 64-bit value has no
  distinct representation. A compiled function the interpreter cannot run has no oracle, so the
  packet proxy publishes those names and no others.
* **A signed read extends by hand.** eBPF's sign-extending load, `BPF_MEMSX` 0x80
  ([include/uapi/linux/bpf.h#L22](https://github.com/torvalds/linux/blob/v7.2/include/uapi/linux/bpf.h#L22)),
  landed in v6.6, and AGENTS.md's supported range starts at 5.15. A shift left followed by an
  arithmetic shift right is two instructions and one shape on every supported kernel.
* **An offset is bounded before the arithmetic.** The verifier refuses arithmetic between a
  packet pointer and a register whose range it does not know, and `find_good_pkt_pointers`
  gives the pointer no range at all once the offset the comparison carries runs past
  `MAX_PACKET_OFF`
  ([kernel/bpf/verifier.c#L15106-L15126](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/verifier.c#L15106-L15126)),
  which is 0xffff
  ([include/linux/bpf_verifier.h#L1556](https://github.com/torvalds/linux/blob/v7.2/include/linux/bpf_verifier.h#L1556)).
  The register the check compares is the access's own end, the pointer plus its width, so the
  offset is tested unsigned against the last one that width can start at and only then added.
  An offset above it is out of bounds on every packet a NIC or `BPF_PROG_TEST_RUN` can build,
  and the interpreter raises there too, so the pairing the differential test asserts is
  unchanged.

## A map the object declares

* **What libbpf requires of a BTF-defined map.** A `.maps` ELF section; a `DATASEC` of that name
  in `.BTF`, without which the load fails naming it
  ([tools/lib/bpf/libbpf.c#L3023](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/libbpf.c#L3023)); per map a `VAR` whose linkage is
  `BTF_VAR_GLOBAL_ALLOCATED`, whose name is the map's, whose type resolves to a `STRUCT`, and
  whose `var_secinfo` satisfies `offset + size <= d_size` and `def->size <= vi->size`
  ([#L2894-L2960](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/libbpf.c#L2894-L2960)). Each attribute is a member named `type`, `max_entries`,
  `map_flags`, `key_size`, `value_size` or `numa_node` whose type is a `PTR` to an `ARRAY` whose
  element count is the value ([#L2473](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/libbpf.c#L2473), [#L2578](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/libbpf.c#L2578)); `key_size` and
  `value_size` are enough, and the `key`/`value` pointer-to-type members are an alternative the
  emitter does not need. The section's bytes are read only for their length, so zeros of the
  right size are enough.
* **What libbpf requires of a map reference.** It never reads `ELF64_R_TYPE`: a relocation is
  matched by its symbol and its instruction ([#L4832](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/libbpf.c#L4832)), the map by
  `map->sec_idx == sym->st_shndx && map->sec_offset == sym->st_value`
  ([#L4746-L4751](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/libbpf.c#L4746-L4751)), and the instruction must be an `ld_imm64`, whose source
  register and immediate libbpf then sets to `BPF_PSEUDO_MAP_FD` and the map's file descriptor
  ([#L6425-L6432](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/libbpf.c#L6425-L6432)). So the emitter writes a plain `ld_imm64 rX, 0` and a
  relocation against the map's symbol, typed `R_BPF_64_64` for the tools that do read the type.
* **BTF encoding.** `BTF_KIND_PTR` 2, `ARRAY` 3, `STRUCT` 4, `VAR` 14, `DATASEC` 15
  ([include/uapi/linux/btf.h#L62-L75](https://github.com/torvalds/linux/blob/v7.2/include/uapi/linux/btf.h#L62-L75)); `struct btf_array {type, index_type,
  nelems}`, `struct btf_member {name_off, type, offset}`, `struct btf_var {linkage}` and
  `struct btf_var_secinfo {type, offset, size}` ([#L110-L177](https://github.com/torvalds/linux/blob/v7.2/include/uapi/linux/btf.h#L110-L177)).
* **What a map may be called, and how an array is keyed.** The `VAR` and the `STRUCT` that carry
  a map's attributes are named after it, and `btf_name_valid_identifier` takes a leading letter
  or `_` and then letters, digits, `_` or `.`
  ([kernel/bpf/btf.c#L880-L888](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/btf.c#L880-L888),
  [#L3305-L3312](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/btf.c#L3305-L3312));
  anything else costs the whole `.BTF` section, and with it the lines the verifier log quotes.
  libbpf refuses an empty name before that
  ([tools/lib/bpf/libbpf.c#L2914](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/libbpf.c#L2914)),
  and a `.` survives the BTF but not the pin, which `sanitize_pin_path` rewrites because bpffs
  disallows periods
  ([#L9366-L9374](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/libbpf.c#L9366-L9374)).
  `array_map_alloc_check` refuses a `key_size` other than four
  ([kernel/bpf/arraymap.c#L53-L64](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/arraymap.c#L53-L64)),
  on 5.15 as on 7.2.

## BTF: what the object carries and what the log prints

* `func_info` and `line_info` ride on `BPF_PROG_LOAD`; the requirements are that
  `func_info[0].insn_off` is 0, offsets strictly increase, and the first instruction of every
  subprogram has a `line_info` record
  ([Documentation/bpf/btf.rst#L707-L714](https://github.com/torvalds/linux/blob/v7.2/Documentation/bpf/btf.rst#L707-L714);
  the checks in
  [kernel/bpf/check_btf.c#L299-L301](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/check_btf.c#L299-L301)
  only require `line_off` and `file_name_off` to be valid BTF strings, so a `.lua` file name and a
  Lua source line are accepted).
* The log prints the source line beside the instruction: `verbose_linfo` at
  [kernel/bpf/log.c#L340](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/log.c#L340)
  reads `line_off` ([#L377](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/log.c#L377))
  and `file_name_off` ([#L380](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/log.c#L380)).
  This is what turns a verifier rejection into an error that names the Lua line.
* In an ELF object the same records live in `.BTF.ext`
  ([btf.rst#L773-L795](https://github.com/torvalds/linux/blob/v7.2/Documentation/bpf/btf.rst#L773-L795)),
  and libbpf's static linker requires `.BTF` whenever `.BTF.ext` is present
  ([tools/lib/bpf/linker.c#L1121-L1130](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/linker.c#L1121-L1130));
  an input object without BTF is accepted
  ([#L1086-L1092](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/linker.c#L1086-L1092)),
  and the machine must be `EM_BPF`
  ([#L717](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/linker.c#L717)).
* Kernel types come from `/sys/kernel/btf/vmlinux` on the machine that runs the program, which is
  where the compiler runs. No `vmlinux.h`, no CO-RE relocation: the offsets the emitter writes are
  the running kernel's.
* A module's kfuncs are resolvable only if the module has BTF, which is what `make btf_install`
  provides
  ([Makefile#L189-L190](https://github.com/luainkernel/lunatik/blob/22c5afe26049b3adf4da7b05a512411ef262e29c/Makefile#L189-L190)).
  A compiled program that never calls into the kernel Lua runtime does not need it.

## Program types

| Program type | Context the program sees | Attach | `BPF_PROG_TEST_RUN` |
|--------------|--------------------------|--------|---------------------|
| `BPF_PROG_TYPE_XDP` | `struct xdp_md` | `BPF_LINK_CREATE` on an ifindex; libbpf `bpf_program__attach_xdp` ([libbpf.h#L895](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/libbpf.h#L895)) | yes, with a packet: `bpf_prog_test_run_xdp` ([net/bpf/test_run.c#L1332](https://github.com/torvalds/linux/blob/v7.2/net/bpf/test_run.c#L1332), wired at [net/core/filter.c#L11367](https://github.com/torvalds/linux/blob/v7.2/net/core/filter.c#L11367)) |
| `BPF_PROG_TYPE_SCHED_CLS` | `struct __sk_buff` | tcx link; `bpf_program__attach_tcx` ([#L927](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/libbpf.h#L927)) | yes: `bpf_prog_test_run_skb` ([test_run.c#L1035](https://github.com/torvalds/linux/blob/v7.2/net/bpf/test_run.c#L1035)) |
| `BPF_PROG_TYPE_LSM` | the hook's arguments, BTF typed | tracing link; `bpf_program__attach_lsm` ([#L887](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/libbpf.h#L887)) | no: `lsm_prog_ops` is empty ([bpf_lsm.c#L414-L415](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/bpf_lsm.c#L414-L415)) |
| `BPF_PROG_TYPE_CGROUP_SOCK_ADDR` | `struct bpf_sock_addr` | cgroup link; `bpf_program__attach_cgroup` ([#L889](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/libbpf.h#L889)) | no |

The kfunc hook a module registers for follows the program type:
`bpf_prog_type_to_kfunc_hook` maps XDP, `SCHED_CLS`, `STRUCT_OPS`, tracing and LSM, and the cgroup
family to their sets
([kernel/bpf/btf.c#L9035-L9055](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/btf.c#L9035-L9055)).
The tree registers per type: `LUNATIK_EBPF_KFUNC_INIT(xdp, BPF_PROG_TYPE_XDP)`
([lib/luaxdp.c#L258](https://github.com/luainkernel/lunatik/blob/22c5afe26049b3adf4da7b05a512411ef262e29c/lib/luaxdp.c#L258))
and `LUNATIK_EBPF_KFUNC_INIT(tc, BPF_PROG_TYPE_SCHED_CLS)` in `lib/luatc.c`.

Verdict conventions differ per type: XDP returns an `XDP_*` action, TC a `TC_ACT_*` action, LSM 0
to allow and a negative errno to refuse, cgroup socket programs 1 to allow and 0 to refuse
(`doc/design/lsm-ebpf/kernel-notes.md`). The program type module owns the convention; a Lua
program returns the type's constants.

## The kfunc the escape hatch calls

`bpf_luaxdp_run(char *key, size_t key__sz, struct xdp_md *xdp_ctx, void *arg, size_t arg__sz)`
([lib/luaxdp.c#L145-L158](https://github.com/luainkernel/lunatik/blob/22c5afe26049b3adf4da7b05a512411ef262e29c/lib/luaxdp.c#L145-L158))
and its `tc` twin are the whole kernel side of the escape hatch. Facts the emitter relies on:

* `__sz` pairs a pointer argument with its size, and the verifier proves the memory
  ([Documentation/bpf/kfuncs.rst#L124-L137](https://github.com/torvalds/linux/blob/v7.2/Documentation/bpf/kfuncs.rst#L124-L137)).
  `key`/`key__sz` selects the runtime by name, `arg`/`arg__sz` carries whatever the caller packs.
* The runtime is looked up in `_ENV.runtimes` and must be an IRQ-context one
  ([lunatik_ebpf.h#L22-L41](https://github.com/luainkernel/lunatik/blob/22c5afe26049b3adf4da7b05a512411ef262e29c/lunatik_ebpf.h#L22-L41));
  the handler resets two `data` objects over the packet and the argument and `lua_pcall`s the
  callback
  ([lib/luaxdp.c#L125-L143](https://github.com/luainkernel/lunatik/blob/22c5afe26049b3adf4da7b05a512411ef262e29c/lib/luaxdp.c#L125-L143)).
  A missing runtime or a raise returns `-1`.
* The kernel side is gated on 6.4
  ([lib/luaxdp.c#L27](https://github.com/luainkernel/lunatik/blob/22c5afe26049b3adf4da7b05a512411ef262e29c/lib/luaxdp.c#L27)).
  Issue #561 factors the per-module copies into one `lunatik_bpf_run`; the emitter calls whatever
  name the module publishes, resolved through the module's BTF.

## Toolchain

### The compiler host: the kernel's own Lua

`lunatikc` (#742) is a C driver that creates a Lua state from the `lua/` submodule built with
`-D_KERNEL`, parses text and dumps bytecode
([bin/lunatikc.c](https://github.com/luainkernel/lunatik/blob/210deebd28060d60a6ddb0e81fda7db1f35a2f23/bin/lunatikc.c)).
That build is the one the translator runs under. What it gives:

* Integer-only arithmetic and 80 opcodes: `OP_LOADF`, `OP_POWK`, `OP_DIVK`, `OP_POW`, `OP_DIV` are
  fenced out under `_KERNEL`
  ([lopcodes.h#L237-L239](https://github.com/luainkernel/lua/blob/d7ca49b3a9c44278078b4e12a7cb26bf4c9e30fd/lopcodes.h#L237-L239),
  [#L269-L272](https://github.com/luainkernel/lua/blob/d7ca49b3a9c44278078b4e12a7cb26bf4c9e30fd/lopcodes.h#L269-L272),
  [#L286-L289](https://github.com/luainkernel/lua/blob/d7ca49b3a9c44278078b4e12a7cb26bf4c9e30fd/lopcodes.h#L286-L289)),
  and `/` parses as `OP_IDIV` (`doc/design/luac/kernel-notes.md` on the #742 branch). That is
  already eBPF's arithmetic.
* `string.dump` and `string.pack` are unfenced
  ([lstrlib.c#L227](https://github.com/luainkernel/lua/blob/d7ca49b3a9c44278078b4e12a7cb26bf4c9e30fd/lstrlib.c#L227),
  [#L1879](https://github.com/luainkernel/lua/blob/d7ca49b3a9c44278078b4e12a7cb26bf4c9e30fd/lstrlib.c#L1879),
  [#L1891](https://github.com/luainkernel/lua/blob/d7ca49b3a9c44278078b4e12a7cb26bf4c9e30fd/lstrlib.c#L1891)),
  and the `debug` library keeps everything but `debug.debug`
  ([ldblib.c#L455-L457](https://github.com/luainkernel/lua/blob/d7ca49b3a9c44278078b4e12a7cb26bf4c9e30fd/ldblib.c#L455-L457)),
  so `debug.getupvalue` can read a program function's captured environment on the host.
* The 5.5 opcode set the translator reads includes `OP_GETVARG` and `OP_ERRNNIL`
  ([lopcodes.h#L347-L349](https://github.com/luainkernel/lua/blob/d7ca49b3a9c44278078b4e12a7cb26bf4c9e30fd/lopcodes.h#L347-L349)).
* The kernel builds the full library set, `lbaselib`, `lstrlib`, `ltablib`, `ldblib`, `lmathlib`
  among them
  ([Kbuild#L28-L35](https://github.com/luainkernel/lunatik/blob/22c5afe26049b3adf4da7b05a512411ef262e29c/Kbuild#L28-L35));
  #742's driver opens a bare state, `luaL_newstate` with no `luaL_openlibs`
  ([bin/lunatikc.c#L152](https://github.com/luainkernel/lunatik/blob/210deebd28060d60a6ddb0e81fda7db1f35a2f23/bin/lunatikc.c#L152)),
  so hosting the translator adds the libraries to that state.

The CLI is Lua 5.4; it does not run the translator, it runs the loader.

### libbpf

The loader and the linker are libbpf; the README already lists it as a usage requirement
([README.md#L357](https://github.com/luainkernel/lunatik/blob/22c5afe26049b3adf4da7b05a512411ef262e29c/README.md#L357)).
Versions from `libbpf.map` at v7.2
([tools/lib/bpf/libbpf.map](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/libbpf.map)):

| API | Since | Line |
|-----|-------|------|
| `bpf_object__open_mem` | 0.0.6 | [#L115](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/libbpf.map#L115) |
| `bpf_program__attach_lsm`, `bpf_link__pin` | 0.0.8 | [#L148-L157](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/libbpf.map#L148-L157) |
| `bpf_program__attach_xdp` | 0.1.0 | [#L194](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/libbpf.map#L194) |
| `bpf_linker__new` (static linker) | 0.4.0 | [#L258](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/libbpf.map#L258); [faf6ed321cf6](https://github.com/torvalds/linux/commit/faf6ed321cf61fafa17444fe01e7e336b8e89acc) (2021-03-18) |
| `bpf_program__attach_tcx`, `bpf_program__attach_netfilter` | 1.3.0 | [#L398-L400](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/libbpf.map#L398-L400) |

The low-level calls take raw instructions and a `fd_array`: `bpf_prog_load`
([tools/lib/bpf/bpf.h#L135](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/bpf.h#L135),
opts at [#L105-L133](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/bpf.h#L105-L133)),
`bpf_btf_load` ([#L166](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/bpf.h#L166)),
`bpf_obj_pin` ([#L341](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/bpf.h#L341)),
`bpf_link_create` ([#L483](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/bpf.h#L483)),
`bpf_prog_test_run_opts` ([#L717](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/bpf.h#L717)).
Pinning by name under a root: `pin_root_path` in the open options
([libbpf.h#L156](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/libbpf.h#L156)),
`bpf_map__set_pin_path` ([#L1203](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/libbpf.h#L1203)),
`bpf_object__pin_maps` ([#L309](https://github.com/torvalds/linux/blob/v7.2/tools/lib/bpf/libbpf.h#L309)).

### bpftool

`bpftool gen object` links BPF objects with the libbpf linker
([tools/bpf/bpftool/gen.c#L1937](https://github.com/torvalds/linux/blob/v7.2/tools/bpf/bpftool/gen.c#L1937),
[d80b2fcbe0a0](https://github.com/torvalds/linux/commit/d80b2fcbe0a023619e0fc73112f2a02c2662f6ab));
`bpftool prog run` drives `BPF_PROG_TEST_RUN` with a packet file
([prog.c#L1322](https://github.com/torvalds/linux/blob/v7.2/tools/bpf/bpftool/prog.c#L1322));
`bpftool net attach` covers `xdp`, `tcx_ingress` and `tcx_egress`
([net.c#L66-L79](https://github.com/torvalds/linux/blob/v7.2/tools/bpf/bpftool/net.c#L66-L79))
and nothing else, which is why the loader is libbpf and not a shell-out. The tree already requires
`bpftool` (`linux-tools-$(uname -r)`,
[README.md#L43](https://github.com/luainkernel/lunatik/blob/22c5afe26049b3adf4da7b05a512411ef262e29c/README.md#L43)).

### clang, for the runtime library only

The LLVM BPF backend never emits `may_goto` from IR: the instruction has an empty selection
pattern
([llvm/lib/Target/BPF/BPFInstrInfo.td#L310](https://github.com/llvm/llvm-project/blob/llvmorg-23.1.1/llvm/lib/Target/BPF/BPFInstrInfo.td#L310))
and reaches the output only as inline assembly. Its default CPU is v3
([clang/lib/Basic/Targets/BPF.cpp#L51-L52](https://github.com/llvm/llvm-project/blob/llvmorg-23.1.1/clang/lib/Basic/Targets/BPF.cpp#L51-L52)).
The design uses clang for the C runtime library the emitter links against (`plan.md`, "The
runtime library"), built at `make` time the way `examples/filter` and `examples/sniclassify` are
built today
([Makefile#L134-L136](https://github.com/luainkernel/lunatik/blob/22c5afe26049b3adf4da7b05a512411ef262e29c/Makefile#L134-L136)).
Writing a program needs no clang.

DTrace 2.0 for Linux is the precedent for this split: a hand-written BPF code generator for the
user's program (`libdtrace/dt_cg.c`, 269,002 bytes at the pinned revision) plus a library of BPF
functions written in C and assembly under `bpf/` and built with `gcc-bpf`
([bpf/Build](https://github.com/oracle/dtrace/blob/61fea621160ea4b6302874c62a723da105b44883/bpf/Build),
[README.md#L101-L102](https://github.com/oracle/dtrace/blob/61fea621160ea4b6302874c62a723da105b44883/README.md#L101-L102)).

### bcc's LuaJIT frontend, the closest ancestor

`iovisor/bcc` `src/lua/bpf/`: 3,254 lines of Lua, of which `bpf.lua` is 1,630. It reads LuaJIT
bytecode through `jit.util.funcbc`
([ljbytecode.lua#L27](https://github.com/iovisor/bcc/blob/8a46070fe08d646e2781fba69586d755da766aa2/src/lua/bpf/ljbytecode.lua#L27)),
emits `struct bpf_insn` from a table of per-opcode handlers
([bpf.lua#L763](https://github.com/iovisor/bcc/blob/8a46070fe08d646e2781fba69586d755da766aa2/src/lua/bpf/bpf.lua#L763))
with "NYI: opcode" for the rest
([#L1237](https://github.com/iovisor/bcc/blob/8a46070fe08d646e2781fba69586d755da766aa2/src/lua/bpf/bpf.lua#L1237)),
captures the compile-time environment with `debug.getlocal`
([#L1347-L1355](https://github.com/iovisor/bcc/blob/8a46070fe08d646e2781fba69586d755da766aa2/src/lua/bpf/bpf.lua#L1347-L1355)),
and writes an ELF in 260 lines (`elf.lua`). It has no loop handler, no BTF and no kfuncs, and its
bytecode reader and types are LuaJIT's. The design transfers, the code does not.

## When the facilities appeared

| Facility | Release | Commit |
|----------|---------|--------|
| `bpf_loop` | v5.17 | [e6f2dd0f8067](https://github.com/torvalds/linux/commit/e6f2dd0f80674e9d5960337b3e9c2a242441b326) (2021-11-30) |
| kfunc BTF id sets in `struct btf` | v5.17 | [dee872e124e8](https://github.com/torvalds/linux/commit/dee872e124e8d5de22b68c58f6f6c3f5e8889160) (2022-01-14) |
| open-coded iterators | v6.4 | [06accc8779c1](https://github.com/torvalds/linux/commit/06accc8779c1d558a5b5a21f2ac82b0c95827ddd) (2023-03-08) |
| the tree's kfuncs (`lib/luaxdp.c` gate) | v6.4 | [lib/luaxdp.c#L27](https://github.com/luainkernel/lunatik/blob/22c5afe26049b3adf4da7b05a512411ef262e29c/lib/luaxdp.c#L27) |
| `bpf_throw` | v6.7 | [f18b03fabaa9](https://github.com/torvalds/linux/commit/f18b03fabaa9b7c80e80b72a621f481f0d706ae0) (2023-09-12) |
| `may_goto` | v6.9 | [011832b97b31](https://github.com/torvalds/linux/commit/011832b97b311bb9e3c27945bc0d1089a14209c9) (2024-03-06) |
| arena | v6.9 | [317460317a02](https://github.com/torvalds/linux/commit/317460317a02a1af512697e6e964298dedd8a163) (2024-03-08) |
| `register_bpf_struct_ops` for modules | v6.9 by tag presence (absent at v6.7, v6.8 not checked) | [9187210eee7d](https://github.com/torvalds/linux/commit/9187210eee7d87eea37b45ea93454a88681894a4) (merge, 2024-03-13) |
| `kern_sys_bpf` namespaced | v6.15 | [f88886de0927](https://github.com/torvalds/linux/commit/f88886de0927a2adf4c1b4c5c1f1d31d2023ef74) (2025-04-25) |
| signed programs | v6.18 | [349271568303](https://github.com/torvalds/linux/commit/349271568303695f0ac3563af153d2b4542f6986) (2025-09-21) |
| `gotox`, `BPF_MAP_TYPE_INSN_ARRAY` | v6.19 by tag presence | not searched by commit |
| 16 call frames | v7.2 | [2148794eeaf2](https://github.com/torvalds/linux/commit/2148794eeaf2a898adc791e9472eb80ea55984da) (2026-06-13) |

None of these is a floor. The emitter picks the loop form the running kernel accepts: a
non-constant loop bound needs `may_goto` (v6.9) or an iterator (v6.4) and is refused on a kernel
without either; a constant bound compiles anywhere. The escape hatch needs the tree's kfunc (v6.4).
Signing is available to the loader on v6.18 and later and not required.

## What is and is not exported

| Symbol | Status | Where |
|--------|--------|-------|
| `register_btf_kfunc_id_set` | `EXPORT_SYMBOL_GPL` | [btf.c#L9198](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/btf.c#L9198) |
| `btf_type_by_id`, `bpf_find_btf_id` | `EXPORT_SYMBOL_GPL` | [btf.c#L970](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/btf.c#L970), [#L722](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/btf.c#L722) |
| `__register_bpf_struct_ops` | `EXPORT_SYMBOL_GPL` | [btf.c#L9977](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/btf.c#L9977); macro at [bpf.h#L2204-L2211](https://github.com/torvalds/linux/blob/v7.2/include/linux/bpf.h#L2204-L2211) |
| `bpf_prog_get_type_path` | `EXPORT_SYMBOL` | [kernel/bpf/inode.c#L638-L651](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/inode.c#L638-L651): a module can take a pinned program by path, the way `luabpf` takes a map |
| `bpf_prog_get_type_dev`, `bpf_prog_put` | `EXPORT_SYMBOL_GPL` | [syscall.c#L2691](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/syscall.c#L2691), [#L2501](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/syscall.c#L2501) |
| `bpf_link_put` | `EXPORT_SYMBOL` | [syscall.c#L3442](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/syscall.c#L3442) |
| `kern_sys_bpf`, `bpf_link_get_from_fd`, `bpf_map_get` | `EXPORT_SYMBOL_NS(..., "BPF_INTERNAL")` | [#L6618](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/syscall.c#L6618), [#L3623](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/syscall.c#L3623), [#L1715](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/syscall.c#L1715) |
| `bpf_check` | not exported | `grep EXPORT_SYMBOL kernel/bpf/verifier.c` is empty |
| `link_create` and the per-type attach functions | `static` | [syscall.c#L5844](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/syscall.c#L5844) |
| `bpf_map_iops` | `static` | [inode.c#L122](https://github.com/torvalds/linux/blob/v7.2/kernel/bpf/inode.c#L122); the tree resolves it with `lunatik_lookup` ([lunatik_aux.c#L93-L112](https://github.com/luainkernel/lunatik/blob/22c5afe26049b3adf4da7b05a512411ef262e29c/lunatik_aux.c#L93-L112)) |

The design adds no kernel C and imports no symbol; the table is here so that a later phase that
wants a `bpf.prog` object in the kernel knows what it may hold (`bpf_prog_get_type_path`) and what
it may not (`kern_sys_bpf`).

## Unverified

* That the LLVM BTF emitter honours a `#line` directive naming a `.lua` file when it fills
  `line_info` (`BTFDebug.cpp`, `populateFileContent`). The design does not depend on it: the
  emitter writes its own `.BTF.ext`.
* The verification budget a program of a few hundred Lua instructions consumes with `may_goto`
  headers. Measured in phase 1 on the running kernel, not predicted here.
* `register_bpf_struct_ops` at v6.8: present at v6.9 and absent at v6.7 by tag; v6.8 not checked.
  Not ranking-deciding, since struct_ops is a non goal.
* Which distributions ship a libbpf with `bpf_program__attach_tcx` (1.3.0). The loader reports a
  missing symbol as a skip in the suite and an error in the CLI.

## Sources

* `kernel/bpf/syscall.c`, `verifier.c`, `log.c`, `check_btf.c`, `btf.c`, `helpers.c`, `bpf_lsm.c`,
  `inode.c`, `preload/bpf_preload_kern.c`; `include/linux/bpf.h`, `bpf_verifier.h`, `bpfptr.h`,
  `filter.h`; `include/uapi/linux/bpf.h`, `bpf_common.h`; `net/core/filter.c`, `net/bpf/test_run.c`;
  `Documentation/bpf/btf.rst`, `kfuncs.rst`, `standardization/instruction-set.rst`;
  `tools/lib/bpf/libbpf.c`, `libbpf.h`, `bpf.h`, `libbpf.map`, `linker.c`, `skel_internal.h`;
  `tools/bpf/bpftool/gen.c`, `prog.c`, `net.c`, all at Linux `v7.2`
* `lunatik_ebpf.h`, `lib/luaxdp.c`, `lib/luatc.c`, `lib/luabpf.c`, `lib/bpf/map.lua`, `bin/lunatik`,
  `lunatik_aux.c`, `Makefile`, `Kbuild`, `README.md`, `tests/xdp/`, `tests/tc/`, `examples/filter/`,
  `examples/sniclassify/` at `22c5afe2`; `doc/design/lsm-ebpf/` for the LSM and cgroup verdicts
* `lopcodes.h`, `lvm.c`, `lstrlib.c`, `ldblib.c` in `luainkernel/lua` at `d7ca49b3`
* `bin/lunatikc.c`, `doc/design/luac/plan.md`, `doc/design/luac/kernel-notes.md` at #742's head
* `llvm/lib/Target/BPF/BPFInstrInfo.td`, `clang/lib/Basic/Targets/BPF.cpp` at `llvmorg-23.1.1`
* `src/lua/bpf/` in `iovisor/bcc` at `8a46070f`; `bpf/Build`, `README.md`, `libdtrace/dt_cg.c` in
  `oracle/dtrace` at `61fea621`
* L. Vieira Neto, V. Nogueira, A. L. de Moura, R. Ierusalimschy,
  [*Linux Network Scripting with Lua*](https://netdevconf.info/0x14/pub/papers/22/0x14-paper22-talk-paper.pdf),
  Netdev 0x14, 2020: the SNI filter in 200 lines of C against 37 of Lua, and the 1.5 Mpps tie at a
  load the generator could not exceed
* J. Edge, [*Lua in the kernel?*](https://lwn.net/Articles/830154/), LWN, 2020-09-09: "The BPF
  verifier is part of what allows the kernel developers to be comfortable with XDP"

