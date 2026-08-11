# Kernel notes: LSM through eBPF

Reference sheet for `lualsm`. Everything below was checked against Linux 6.8
(`/home/ubuntu/linux-hwe-6.8-6.8.0` sources, `/usr/src/linux-headers-6.8.0-124-generic`, its
`Module.symvers`, and the running `/sys/kernel/security/lsm`), and compared against upstream v6.12
and v6.15 where the mechanism changed. Re-check on the kernel you target.

## Why eBPF: the LSM framework is closed to modules

This is the fact that decides the whole design. Three independent parts of the kernel close the door:

**1. The registration function is `__init` and unexported.**

    /* security/security.c:609, Linux 6.8 */
    void __init security_add_hooks(struct security_hook_list *hooks, int count,
                                   const struct lsm_id *lsmid)

No `EXPORT_SYMBOL` of any kind. `grep EXPORT_SYMBOL security/security.c` returns the `security_*`
call sites (`security_inode_create`, `security_file_ioctl`, ...) that other subsystems invoke — never
the registration path.

**2. LSMs are discovered from a link-time section walked at boot.**

    /* include/linux/lsm_hooks.h:150 */
    #define DEFINE_LSM(lsm) \
            static struct lsm_info __lsm_##lsm \
                    __used __section(".lsm_info.init") \
                    __aligned(sizeof(unsigned long))

`ordered_lsm_init()` walks `__start_lsm_info .. __end_lsm_info` once, during boot, filtered by the
`lsm=` list. A module loaded later is not in that section and there is no runtime equivalent.

**3. Since v6.12 the hook calls are static calls with a fixed slot count.** The indirect
`hlist_for_each_entry` dispatch of 6.8 became `DEFINE_STATIC_CALL_NULL` slots unrolled `MAX_LSM_COUNT`
times, where `MAX_LSM_COUNT` is computed at build time from `CONFIG_LSM`
(`security/security.c`, `LSM_DEFINE_UNROLL`, and `WARN(last_lsm == MAX_LSM_COUNT, "out of LSM static
calls!?")`). There is no free slot for a module even in principle.

The supported runtime extension of the security surface on Linux is BPF LSM (KRSI), and that is what
this project targets.

It is worth knowing what the alternative would look like, because a comparable project exists on
another system and took the other road. NetBSD's authorization framework, kauth(9), lets a kernel
module register a listener on an authorization scope **at runtime**:

    /* NetBSD; there is no Linux equivalent of this call */
    kauth_listen_scope(KAUTH_SCOPE_NETWORK, callback, cookie);
    kauth_unlisten_scope(listener);

A NetBSD *secmodel* is just a set of such listeners, which is why
[`secmodel_sandbox`](https://github.com/smherwig/netbsd-sandbox) — Lua policies evaluated in the
kernel, [BSDCan 2017](https://www.cs.wm.edu/~smherwig/pub/17-bsdcan-secmodel_sandbox-slides.pdf) —
could be a loadable module there and cannot be one here. See the prior art section of `plan.md` for
what that project did and what carries over. Reference:
[kauth(9)](https://man.netbsd.org/kauth.9).

Also worth stating because it shapes the API: **the LSM chain can only restrict.** In 6.8,
`call_int_hook()` stops at the first non-zero return; a hook that a previous module refused stays
refused. There is no "allow" that grants anything. `secmodel_sandbox` had to convert its own `ALLOW`
into `DEFER` to get the same property; on Linux you get it for free, and an API that suggests
otherwise would be lying.

## BPF LSM: what it needs to exist

    CONFIG_BPF_LSM=y

Present on Ubuntu's 6.8 kernel. **Not sufficient.** `security/bpf/hooks.c` registers through the
ordinary `DEFINE_LSM(bpf)` with no `LSM_ORDER_LAST`, so `bpf` must appear in the kernel's LSM list:

    $ cat /boot/config-$(uname -r) | grep CONFIG_LSM=
    CONFIG_LSM="landlock,lockdown,yama,integrity,apparmor"
    $ cat /sys/kernel/security/lsm
    lockdown,capability,landlock,yama,apparmor

No `bpf` — on this machine LSM programs cannot attach. Enabling it means a boot parameter and a
reboot:

    GRUB_CMDLINE_LINUX="lsm=lockdown,capability,landlock,yama,apparmor,bpf"

Fedora ships `bpf` in `CONFIG_LSM`; Ubuntu does not; Oracle's UEK added it. Verified unchanged in
v6.15: `security/bpf/hooks.c` still has a plain `DEFINE_LSM(bpf)`.

**This is why the phase order starts with cgroup programs.** `CONFIG_CGROUP_BPF` needs no boot
parameter, and a cgroup socket program enforces per-cgroup network policy on a stock kernel.

## The kfunc bridge

A module can publish a kfunc and eBPF programs can call it. This is exported and supported:

    /* kernel/bpf/btf.c:8002 */
    EXPORT_SYMBOL_GPL(register_btf_kfunc_id_set);

Program type to kfunc hook mapping, 6.8 (`kernel/bpf/btf.c:7894`):

| Program type | Hook set |
|--------------|----------|
| `BPF_PROG_TYPE_LSM` | `BTF_KFUNC_HOOK_TRACING` |
| `BPF_PROG_TYPE_TRACING` | `BTF_KFUNC_HOOK_TRACING` |
| `BPF_PROG_TYPE_CGROUP_SKB`, `BPF_PROG_TYPE_CGROUP_SOCK_ADDR` | `BTF_KFUNC_HOOK_CGROUP_SKB` |
| `BPF_PROG_TYPE_XDP` | `BTF_KFUNC_HOOK_XDP` |
| `BPF_PROG_TYPE_SCHED_CLS` | `BTF_KFUNC_HOOK_TC` |

Register with the program type; the core maps it. A set registered for `BPF_PROG_TYPE_UNSPEC` lands
in `BTF_KFUNC_HOOK_COMMON`, which `btf_kfunc_id_set_contains` consults **before** the per-type set
(`btf.c:7946`), so a kfunc meant for several program types can be registered once — at the cost of
being callable from all of them, which for a kfunc that runs a Lua interpreter is a decision to make
deliberately, not by default.

The existing Lunatik pattern to follow, on `master` in `lib/luaxdp.c`:

    __bpf_kfunc int bpf_luaxdp_run(char *key, size_t key__sz, struct xdp_md *xdp_ctx,
                                   void *arg, size_t arg__sz);

    BTF_KFUNCS_START(bpf_luaxdp_set)
    BTF_ID_FLAGS(func, bpf_luaxdp_run)
    BTF_KFUNCS_END(bpf_luaxdp_set)

    static const struct btf_kfunc_id_set bpf_luaxdp_kfunc_set = {
            .owner = THIS_MODULE,
            .set   = &bpf_luaxdp_set,
    };

    register_btf_kfunc_id_set(BPF_PROG_TYPE_XDP, &bpf_luaxdp_kfunc_set);

`lunatik_ebpf.h` on `sneaky-potato/gsoc26` wraps exactly this in
`LUNATIK_EBPF_KFUNC_DEFINE_SET(subsys, kfunc)` and `LUNATIK_EBPF_KFUNC_INIT(subsys, prog_type)`,
plus the version guards for the `BTF_SET8_START` to `BTF_KFUNCS_START` rename in 6.9 and the
`__bpf_kfunc_start_defs` rename in 6.7. Use it; do not re-derive it.

The eBPF side needs the module's BTF to resolve the kfunc, which is what `sudo make btf_install` is
for. A program that cannot see it fails to load with "kernel function ... not found".

## Attaching an LSM program

Verification rules, `bpf_lsm_verify_prog` (`kernel/bpf/bpf_lsm.c:96`):

* the program must be GPL licensed — `char _license[] SEC("license") = "GPL";`
* its `attach_btf_id` must be in the `bpf_lsm_hooks` BTF set, which is generated from
  `linux/lsm_hook_defs.h`: one `bpf_lsm_<hook>` stub per LSM hook.

Return values: the LSM program is an `fmod_ret` style attachment on the `bpf_lsm_<hook>` stub. Hooks
whose return type is `void` cannot refuse anything, and the verifier knows
(`kernel/bpf/verifier.c:15308`, "LSM and struct_ops func-ptr's return type could be void"). For the
`int` hooks, `0` allows and a negative errno refuses.

Sleepable hooks are an explicit allowlist, `sleepable_lsm_hooks` in `kernel/bpf/bpf_lsm.c:259`;
`SEC("lsm.s/...")` only works for those. A kfunc that a sleepable program calls must be declared
`KF_SLEEPABLE`. The plan targets the non-sleepable path first, which matches how `luaxdp` already
runs Lua from a non-sleepable runtime.

`BPF_LSM_CGROUP` (`expected_attach_type`) scopes an LSM program to a cgroup subtree instead of the
whole system. Its return convention differs — see the verifier note at `verifier.c:15309` — and it is
phase 5 material, not phase 2.

### Tooling: bpftool cannot attach an LSM program

Verified with `bpftool v7.4.0 / libbpf v1.4` on this machine:

    $ bpftool prog help
    ATTACH_TYPE := { sk_msg_verdict | sk_skb_verdict | sk_skb_stream_verdict |
                     sk_skb_stream_parser | flow_dissector }
    $ bpftool link help
    Usage: bpftool link { show | list } ... pin ... detach

`bpftool link` can pin and detach an existing link but cannot create one, and `prog attach` does not
cover LSM. Attaching an LSM program means `bpf_program__attach_lsm()` from libbpf, in a small loader
that then pins the link so the attachment outlives the process. That loader is a deliverable, not an
assumption.

Cgroup programs are the opposite, and this is the second reason the cgroup phase comes first:

    $ bpftool cgroup help
    bpftool cgroup attach CGROUP ATTACH_TYPE PROG [ATTACH_FLAGS]
    ATTACH_TYPE := { cgroup_inet_ingress | ... | cgroup_inet4_connect | cgroup_inet6_connect |
                     cgroup_udp4_sendmsg | ... | cgroup_device | ... }

No custom loader needed for phase 1.

## Cgroup socket programs

Attach types relevant here: `cgroup_inet4_connect`, `cgroup_inet6_connect`, `cgroup_inet4_bind`,
`cgroup_udp4_sendmsg` and their v6 twins; also `cgroup_device` for device access and
`cgroup_sock_ops`.

Return convention is inverted relative to LSM: **1 allows, 0 refuses**, and refusing surfaces as
`EPERM` on the syscall. The stub translates between that and the errno convention Lua uses; see
`api.md`.

**A kfunc does not receive the context the program sees.** The eBPF program manipulates
`struct bpf_sock_addr` (`user_ip4`, `user_ip6[4]`, `user_port`, `family`, `protocol`, `msg_src_ip4`),
and those writable fields are what make `connect4` able to redirect rather than only refuse — but that
struct is a UAPI view the verifier synthesizes. Reads and writes of `ctx->user_ip4` in the program are
rewritten by `convert_ctx_access` into accesses on the kernel-internal struct, which is what a kfunc
is handed:

    /* include/linux/filter.h:1328, Linux 6.8 */
    struct bpf_sock_addr_kern {
            struct sock *sk;
            struct sockaddr *uaddr;
            u64 tmp_reg;
            void *t_ctx;
            u32 uaddrlen;
    };

No `user_ip4`, no `user_port`, no `family`. The binding reads the address and port out of `uaddr`, and
the socket out of `sk`. `lib/luaxdp.c` already demonstrates the pattern for its own context: the kfunc
declares `struct xdp_md *xdp_ctx` for the program's benefit and its first line is
`struct xdp_buff *ctx = (struct xdp_buff *)xdp_ctx;`.

**Verify before promising a rewrite.** Reading `uaddr` is straightforward. Writing it from a kfunc, so
that `connect4` redirects, is the same mutation the program's `ctx->user_ip4 = x` performs after
rewriting, but "the same mutation after rewriting" is a claim about `convert_ctx_access`, not a fact
established here. Prototype the write before the API promises `ctx:address(value)`.

`cgroup_device` has no kfunc hook mapping of its own in 6.8, so a kfunc reachable from it would have
to be registered in the `COMMON` set. Confirm before promising device policy in Lua.

## Config and boot dependencies

| Requirement | Needed for | Ubuntu 6.8 stock |
|-------------|-----------|------------------|
| `CONFIG_BPF_SYSCALL`, `CONFIG_DEBUG_INFO_BTF` | anything here | `y` |
| `CONFIG_CGROUP_BPF` | phase 1 | `y` |
| `CONFIG_BPF_LSM` | phases 2+ | `y` |
| `bpf` in `/sys/kernel/security/lsm` | phases 2+ | **absent** — needs `lsm=...,bpf` and a reboot |
| `sudo make btf_install` | the eBPF program resolving our kfunc | n/a |
| `clang` with `-target bpf`, `bpftool` | building and attaching stubs | present |

Check the LSM list at runtime, not the config: `lsm=` on the command line overrides `CONFIG_LSM`, so
the config can say one thing and the running kernel another.

## Sources

* `security/security.c`, `security/bpf/hooks.c`, `include/linux/lsm_hooks.h`, `kernel/bpf/bpf_lsm.c`,
  `kernel/bpf/btf.c`, `kernel/bpf/verifier.c` (Linux 6.8; `security/security.c` and
  `security/bpf/hooks.c` also checked at v6.12 and v6.15)
* `/sys/kernel/security/lsm` and `/boot/config-6.8.0-124-generic` on the development machine
* `bpftool v7.4.0` help output on the same machine
* `lib/luaxdp.c` on `master`; `lunatik_ebpf.h` and `lib/luatc.c` on `sneaky-potato/gsoc26`
* [LSM BPF programs](https://docs.kernel.org/bpf/prog_lsm.html), kernel documentation
* S. Herwig, *secmodel_sandbox: An application sandbox for NetBSD*, BSDCan 2017
  ([slides](https://www.cs.wm.edu/~smherwig/pub/17-bsdcan-secmodel_sandbox-slides.pdf),
  [source](https://github.com/smherwig/netbsd-sandbox)); [kauth(9)](https://man.netbsd.org/kauth.9)
* L. V. Neto, R. Ierusalimschy, A. L. de Moura, M. Balmer,
  [*Scriptable Operating Systems with Lua*](https://netbsd.org/~lneto/dls14.pdf), DLS 2014

