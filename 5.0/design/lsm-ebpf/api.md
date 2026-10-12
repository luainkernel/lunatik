# Proposed Lua API: `lsm` and `cgroup`

This is a design proposal, not a specification. Names and shapes are open for review; the constraints
behind them (in `kernel-notes.md`) are not. Anything here that turns out to conflict with a kernel
constraint loses.

Two new kernel modules, both consumers of the kfunc bridge that `lib/luaxdp.c` established and
`lunatik_ebpf.h` generalizes:

* `cgroup` (`lib/luacgroup.c`) — reachable from cgroup socket programs, no boot change required;
* `lsm` (`lib/lualsm.c`) — reachable from `BPF_PROG_TYPE_LSM` programs, requires `lsm=...,bpf`.

Both follow `xdp.attach`, which is on `master`: an eBPF program calls a kfunc naming a runtime, the
kfunc runs the callback that runtime registered, and the callback's verdict becomes the program's
return value. `lib/luatc.c` on `sneaky-potato/gsoc26` is the second consumer of the same pattern, but
it is not merged, so nothing here depends on its shape.

## Conventions

* `attach` is called from a **non-sleepable** runtime (`lunatik run <script> softirq`), like
  `xdp.attach`, because the kfunc is called from an eBPF program that cannot sleep. Enforce it the
  same way: `lunatik_checkruntime(L, LUNATIK_OPT_SOFTIRQ)` as the first line of `attach`.
* Neither module needs an object class for the attachment itself. `xdp.attach` registers the callback
  as a closure in the registry (`lunatik_register(L, -1, luaxdp_callback)`) and `xdp.detach`
  unregisters it; there is no handle to collect. Follow that. The `cgroup.ctx` class is
  `LUNATIK_OPT_SOFTIRQ | LUNATIK_OPT_SINGLE` with `.pointer = true`, reset per call and cleared on
  return, since it wraps a kernel pointer that outlives nothing.
* Verdicts are integers: `0` allows, a negative errno refuses. `linux.errno` supplies the names.
* Hook-specific data reaches Lua as a `data` object the stub filled in, unpacked with `struct` — the
  same way `luaxdp` passes its `arg`. The C side stays generic; the per-hook knowledge lives in the
  eBPF stub.
* The runtime key is the script name, as in `xdp`, so a stub addresses a script by the name it was
  loaded with.

## `cgroup`

### `cgroup.attach(callback)`

    local cgroup = require("cgroup")
    local errno  = require("linux.errno")

    local BLOCKED <const> = 0xC0A80001    -- 192.168.0.1

    local function guard(ctx, argument)
        if ctx:address() == BLOCKED then
            return -errno.EPERM
        end
        return 0
    end

    cgroup.attach(guard)

The eBPF side, attached with `bpftool cgroup attach /sys/fs/cgroup/<path> cgroup_inet4_connect`:

    char rt_key[] = "examples/netguard/guard";

    SEC("cgroup/connect4")
    int connect4(struct bpf_sock_addr *ctx)
    {
            return bpf_luacgroup_run(rt_key, sizeof(rt_key), ctx, NULL, 0) == 0;
    }

Note the shape of the last line: a cgroup socket program returns **1 to allow and 0 to deny**, the
opposite convention from LSM. Lua speaks one language (`0` allow, negative errno deny) and the stub
translates. Putting the translation in the stub rather than in Lua keeps every callback in this
project readable the same way.

### The `cgroup.ctx` object

| Method | Returns | Notes |
|--------|---------|-------|
| `ctx:family()` | integer | `linux.socket.af` |
| `ctx:protocol()` | integer | `linux.socket.ipproto` |
| `ctx:address([value])` | integer or string | IPv4 as an integer, IPv6 as a 16 byte string; setting rewrites the destination |
| `ctx:port([value])` | integer | host order |

Whatever the stub packed arrives as a second argument, a `data` object, not as a method on the ctx:
`callback(ctx, argument)`. That keeps the argument in the same position it has in `lsm.attach`.

`address` and `port` are settable because that is what a cgroup socket program is for: `connect4` can
redirect as well as refuse, and refusing to expose it would make the binding weaker than the stub it
wraps. The setter is the one method here that is not yet proven; see `kernel-notes.md`.

These accessors do not read the fields the eBPF program uses. A kfunc receives
`struct bpf_sock_addr_kern`, which carries `sk` and a `struct sockaddr *uaddr`, not the synthesized
`user_ip4`/`user_port` of the UAPI view. `kernel-notes.md` has the struct and the reason. This is why
`cgroup` keeps a `ctx` object while `lsm` does not: there is real decoding to do, and doing it once in
C beats doing it in every stub.

## `lsm`

### `lsm.attach(callback)`

    local lsm   = require("lsm")
    local errno = require("linux.errno")
    local set   = require("set")

    local allowed = set.new{"/usr/bin/hello", "/bin/true"}

    local function guard(hook, argument)
        local path = argument:getstring(0)
        if not allowed:has(path) then
            return -errno.EPERM
        end
        return 0
    end

    lsm.attach(guard)

The eBPF side:

    char rt_key[] = "examples/execguard/guard";

    SEC("lsm/bprm_check_security")
    int BPF_PROG(exec_guard, struct linux_binprm *bprm, int ret)
    {
            struct lualsm_arg arg = {};

            if (ret)
                    return ret;                    /* an earlier LSM already refused */
            bpf_probe_read_kernel_str(arg.path, sizeof(arg.path), bprm->filename);
            return bpf_lualsm_run(rt_key, sizeof(rt_key), LUALSM_BPRM_CHECK, &arg, sizeof(arg));
    }

Three things in that stub are load bearing, and all three are the stub's job rather than Lua's:

* **`if (ret) return ret;`** — LSM programs run after the other modules in the chain, and a hook that
  has already been refused must stay refused. An LSM can restrict; it cannot grant. A callback that
  returns 0 unconditionally must not turn another module's denial into an allow.
* **the hook id** (`LUALSM_BPRM_CHECK`) — so one runtime can serve several hooks and the callback can
  tell them apart.
* **the argument packing** — every hook has a different signature; the stub reads what it needs and
  hands over bytes.

### There is no `lsm.ctx`

The callback is `callback(hook, argument)`: an integer the stub chose, and a `data` object holding the
bytes it packed. That is `xdp.attach`'s shape (`luaxdp_callback` pushes two `data` objects and nothing
else) and `notifier`'s shape (`callback(event, ...)`, integer first) at the same time.

An `lsm.ctx` was considered and dropped. It would have carried four methods: `hook()` and `argument()`
are the two arguments above; `pid()` is reachable without the hook's help; and `action(verdict)`
duplicates the return value. A class that exists to hold two values it could pass directly is a class
that will be asked to justify itself in review.

The verdict is the return value, only. `lib/luatc.c` sets it on a ctx instead, but `luatc` is not on
`master`, so there is no established second spelling to be symmetric with.

`cgroup` keeps its `ctx` because there the object decodes a kernel struct rather than forwarding
arguments.

## The policy fast path

The point of the design is that most decisions never reach Lua. Lua owns the ruleset; eBPF reads it.

    local map = require("bpf.map")

    local rules <close> = map.hash("/sys/fs/bpf/execguard", "c64", "I4")
    rules["/usr/bin/hello"] = 1     -- 1 = allow, 2 = deny, absent = ask Lua

and in the stub:

    __u32 *decision = bpf_map_lookup_elem(&rules, &key);

    if (decision)
            return *decision == LUALSM_ALLOW ? 0 : -EPERM;
    return bpf_lualsm_run(rt_key, sizeof(rt_key), LUALSM_BPRM_CHECK, &arg, sizeof(arg));

Lua writes the map from a process runtime; the stub reads it on every exec. The kfunc is the escape
hatch for what a map cannot express — a rule that needs string matching, state, or a decision that
depends on something the map does not carry.

This is the same two-layer split that made
[`secmodel_sandbox`](https://www.cs.wm.edu/~smherwig/pub/17-bsdcan-secmodel_sandbox-slides.pdf)
usable on NetBSD — boolean rules resolved from its C-side ruleset cost roughly 70 ns, while a rule
that ran the interpreter cost roughly 4.5 µs (prior art section of `plan.md`). The map is the
ruleset; the kfunc is its `sandbox.on()`.

## Detecting what the kernel can do

    local lsm = require("lsm")

    if not lsm.available() then
        print("BPF LSM not active; boot with lsm=...,bpf")
        return
    end

`lsm.available()` reports whether `bpf` is in the active LSM list. It exists because the failure mode
without it is silent: the stub loads, the attach fails with a message nobody reads, and the policy
appears to be installed while nothing is enforced.

## Open questions for review

1. Whether `cgroup` is its own module or a submodule of `socket`. The kfunc is separate either way;
   the question is only how a script names it. A program type is not a socket, so the proposal keeps
   it separate.
2. Whether the `argument` should stay a raw `data` or gain a per-hook decoder generated from BTF.
   The raw form ships first; a decoder is a project of its own.
3. Whether hook ids should be a Lunatik enum passed by the stub, or the BTF id of the attach point,
   which the stub gets for free but which is not stable across kernels.
4. Whether `lsm.attach` should accept a table of `hook = callback` rather than one callback that
   switches on the hook argument. The table reads better; it also puts a dispatch in C that Lua can
   do.
5. Whether verdicts should be `linux.errno` negatives or named constants (`lsm.action.DENY`). The
   errno form composes with the rest of the base; the named form is harder to get wrong.

