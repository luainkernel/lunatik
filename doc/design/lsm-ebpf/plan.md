# Plan: LSM binding through eBPF

Execution plan for `lualsm`.

## Expected results

1. A Lua script can attach a callback to **any** LSM hook — file, exec, process, credential,
   capability, socket, IPC, mount, module loading, ptrace — and observe the operation: audit,
   detection, telemetry written in Lua.
2. On the hooks that allow it, the callback **denies** the operation by returning an error, giving
   MAC, sandboxing and system ACLs in Lua.
3. The hot path of a policy lives in eBPF maps written from Lua: the decision is taken in eBPF
   without entering the interpreter, and Lua runs only on a miss or on a rule that asks for it.
4. Per-cgroup network rules (connect, bind, sendmsg) are scriptable in Lua **without** `lsm=bpf` in
   the boot line, so a stock distribution kernel gets something useful.
5. Loader tooling that reports whether the running kernel can attach LSM programs at all; examples in
   both regimes (an exec auditor and an allowlist sandbox); a test suite that skips cleanly when the
   kernel is not configured for it.

## Where we are today

The bridge this project needs mostly exists, in three places at three levels of maturity:

* **On `master`:** `lib/luaxdp.c` carries the complete kfunc pattern — `bpf_luaxdp_run` declared with
  `__bpf_kfunc`, published through a `BTF_KFUNCS` set, registered with
  `register_btf_kfunc_id_set(BPF_PROG_TYPE_XDP, ...)`, plus a runtime lookup by string key in an RCU
  table and a Lua-side `xdp.attach(callback)`. `make btf_install` exports the module BTF that lets an
  eBPF program resolve the kfunc.
* **On `master`:** `lib/luabpf.c`, the map binding (#630, with the typed constructors of #636). Lua
  can open a pinned map and read and write it. #633 proposes `bpf.map`, a higher level view; useful
  here, not required.
* **On `sneaky-potato/gsoc26`, not merged:** `lunatik_ebpf.h`, which factors the pattern into
  `LUNATIK_EBPF_KFUNC_DEFINE_SET` / `LUNATIK_EBPF_KFUNC_INIT` plus a runtime lookup macro, and
  `lib/luatc.c`, its second consumer, with a `ctx` object carrying the verdict setter. Issue #561
  tracks turning this into a generic `lunatik_bpf_run`.

What exists for security specifically: nothing. No branch, issue or pull request in the repository
mentions LSM, and `security_*` appears nowhere in the tree.

## What is missing

| Expected result | Gap |
|-----------------|-----|
| Callback on any LSM hook | No `BPF_PROG_TYPE_LSM` kfunc, no stub programs, no attach path. Nothing today can reach a security hook. |
| Deny an operation | No verdict representation, and no answer to which hooks can refuse and what they must return. |
| Policy hot path in maps | The pieces exist on both sides (`luabpf` in Lua, maps in eBPF) but nothing ties a map lookup in the stub to a fallback into Lua. |
| Per-cgroup network rules without a reboot | No cgroup program type binding, no `ctx` for a socket address operation. |
| Tooling, examples, tests | `bpftool` cannot create an LSM link, so a loader has to exist. No detection of the active LSM list. No suite. |

Supporting gaps:

* no `errno` constants in `linux.*`, which a verdict API needs (`-EPERM`, `-EACCES`);
* `lunatik_ebpf.h` is not on `master`, so either this project waits for it, carries it, or duplicates
  the pattern — the plan below takes a position on that;
* no test harness knows how to load an eBPF program, attach it, and assert on the result.

## Shape of the work

Two new kernel modules, both thin consumers of the same bridge:

* `cgroup` (`lib/luacgroup.c`) — kfunc callable from cgroup socket programs, with a `ctx` exposing
  the address and the verdict. Works on a stock kernel.
* `lsm` (`lib/lualsm.c`) — kfunc callable from `BPF_PROG_TYPE_LSM` programs, with a `ctx` exposing
  the hook identity, its arguments and the verdict. Needs `lsm=...,bpf`.

The full API proposal is in `api.md`; the kernel constraints that drive it are in `kernel-notes.md`.
Two of those constraints shape everything.

The first is why this project exists in this form:

> An out-of-tree module cannot be an LSM. `security_add_hooks()` is `__init` and unexported; LSMs are
> registered from a `.lsm_info` section walked at boot; and since 6.12 the hook calls are static calls
> with a slot count fixed at build time from `CONFIG_LSM`. Linux has no equivalent of NetBSD's
> `kauth_listen_scope()`. eBPF is the only supported runtime extension of the security surface, so
> the binding is a bridge into eBPF rather than a security module of our own.

The second is what makes it fast enough to be real:

> The eBPF program is not just a shim. It is where the policy's hot path belongs: a map lookup, keyed
> by whatever the hook offers, deciding allow or deny without ever entering the interpreter. The kfunc
> into Lua is the escape hatch for the rules that need one. Lua writes the maps; eBPF reads them.

That split is not an invention of this project; it is the lesson of the prior art below, with its
measurements.

## Prior art: the same idea, on NetBSD

This is not the first attempt to write system access control in Lua, and the one that came before is
worth reading before designing anything here.

**`secmodel_sandbox`** — Stephen Herwig, University of Maryland, BSDCan 2017
([slides](https://www.cs.wm.edu/~smherwig/pub/17-bsdcan-secmodel_sandbox-slides.pdf),
[source](https://github.com/smherwig/netbsd-sandbox)) — is a NetBSD kernel module that lets a process
sandbox itself with a policy written in Lua, evaluated by NetBSD's in-kernel interpreter
([`lua(4)`](https://man.netbsd.org/lua.4), from
[Scriptable Operating Systems with Lua](https://netbsd.org/~lneto/dls14.pdf), DLS 2014). A policy
looks like this:

    sandbox.default('deny')
    sandbox.allow('vnode.read_data')

    sandbox.on('vnode.write_data', function(req, cred, f)
        return string.find(f.name, '/tmp/') == 1
    end)

Three things it established, all of which apply here:

1. **Evaluating the script is not the decision.** Running the policy populates a ruleset in C, keyed
   by the authorization request; the hot path reads that ruleset. `sandbox.on()` is the escape hatch
   for the rules a table cannot express, and it may be stateful or rewrite the ruleset as it runs.
2. **The cost of getting that split wrong is measurable.** Its benchmark, 10 million syscalls, timed
   the same operation three ways: no sandbox, a boolean rule from the ruleset, and a rule that ran
   the interpreter. `setpriority` went 1.597 s → 2.281 s → 46.356 s; `socket` went 14.725 s →
   17.439 s → 51.644 s. Roughly 70 ns per decision resolved in C against roughly 4.5 µs when Lua ran.
   That is the whole argument for the map-backed fast path in phase 4.
3. **A policy that can only restrict is the safe shape.** It converts its own `ALLOW` into kauth's
   `DEFER` so that a sandbox cannot grant a privilege the system would otherwise refuse. Linux gives
   us that property for free, since the LSM chain stops at the first refusal and has no "allow".

What does **not** carry over is the mechanism. NetBSD's kauth lets a module register listeners at
runtime ([`kauth_listen_scope(9)`](https://man.netbsd.org/kauth.9)), and a *secmodel* is just a set of
those listeners; that is why `secmodel_sandbox` could be a loadable module at all. Linux has no such
call — see `kernel-notes.md` — which is what turns the Linux version of this idea into a bridge to
eBPF instead of a security module of our own.

The other thing that does not carry over is where the policy comes from. `secmodel_sandbox` is
self-sandboxing: a process installs a policy on itself through an ioctl, and children inherit it.
This project is administrator policy attached to a hook or a cgroup. Landlock is the Linux answer to
the self-sandboxing case, and it is deliberately out of scope.

## Phases

Each phase is one or more self contained pull requests.

### Phase 0: errno constants and the dependency decision

Add `linux.errno` to autogen, which the verdict API needs. Settle, with the maintainer, whether this
project depends on `lunatik_ebpf.h` landing on `master` first (issue #561), waits for it, or ships
`lib/lualsm.c` against the `luaxdp` pattern and is refactored onto the generic API afterwards.

The recommendation is to depend on it and sequence the epic behind #561: a third open-coded copy of
the kfunc pattern is exactly what #561 exists to prevent.

### Phase 1: cgroup socket rules

The `cgroup` module: kfunc for `BPF_PROG_TYPE_CGROUP_SOCK_ADDR`, a `ctx` with address, port, family
and verdict, `cgroup.attach(callback)` on the Lua side, and an example stub program attached with
`bpftool cgroup attach`.

This phase is first because it needs no boot change: cgroup programs are attachable on any kernel with
`CONFIG_CGROUP_BPF`, and `bpftool` can attach them without a custom loader. It delivers per-service
network ACLs in Lua and exercises the whole path — stub, kfunc, ctx, verdict, tests — before the
project depends on anything a user has to reboot for.

Deliverables: `lib/luacgroup.c`, `Kconfig`/`Kbuild`, `examples/`, `tests/cgroup/`, README row,
`config.ld` entry.

### Phase 2: the LSM bridge

The `lsm` module: `bpf_lualsm_run` registered for `BPF_PROG_TYPE_LSM`, a `ctx` carrying the hook
identity and the verdict, `lsm.attach(callback)`, a stub program for one representative hook
(`bprm_check_security`), and the loader.

The loader is real work: `bpftool` has no way to create an LSM link, so this needs a small libbpf
program that loads the object, attaches it and pins the link. Phase 2 owns it, along with detecting
whether `bpf` is in `/sys/kernel/security/lsm` and saying so plainly when it is not.

### Phase 3: hook coverage and arguments

Beyond one hook: a stub set covering the hooks worth reaching first (`bprm_check_security`,
`file_open`, `socket_connect`, `task_alloc`, `cred_prepare`, `kernel_module_request`), and the
question this phase exists to answer — how a Lua callback reads a hook's arguments when every hook has
a different signature. The proposal in `api.md` is that the stub packs what it wants into a buffer and
Lua unpacks it with `struct`, exactly as `luaxdp` already passes its `arg`.

### Phase 4: the policy fast path

The map-backed pattern: Lua builds the ruleset into a pinned map, the stub decides from the map, and
calls the kfunc only on a miss or when the entry says the rule is functional. An example that shows
both paths and a benchmark that shows the difference, because the claim in "Shape of the work" is
worth a number in our own tree rather than a citation.

### Phase 5: per-process and per-cgroup policy

`BPF_LSM_CGROUP` attachment, so a policy applies to a cgroup subtree rather than system wide, and BPF
task storage for per-task state — the closest Linux equivalent of the credential-attached sandbox
`secmodel_sandbox` gets from kauth. This is the phase that turns "a rule" into "a sandbox".

### Phase 6: examples and documentation

An exec auditor (observation) and an allowlist sandbox (enforcement), a documentation pass, and the
API cleanup the examples expose.

## Sizing

Sized by what fits in a reviewable pull request.

| Scope | Phases |
|-------|--------|
| Minimum useful | 0 to 2. Cgroup rules on a stock kernel, plus one LSM hook proving the bridge. |
| Complete | 0 to 6. Coverage, the map fast path, scoped policy, examples. |

Phase 2 is the boundary: everything before it works on an unmodified distribution kernel, everything
after it assumes the operator opted into `lsm=bpf`.

## Non goals

* **Writing an LSM.** Not a kernel patch, not a shim security module, not an upstream submission. If
  that path is ever taken it is a different project with a different risk profile.
* **Replacing SELinux or AppArmor.** This is a scripting layer over the same hook surface, useful for
  policies that are dynamic, small, or specific to one deployment. It stacks with whatever major LSM
  is loaded; it does not compile a policy for it.
* **A policy language.** No DSL, no compiler, no rule file format. Lua is the language; `set`, `rcu`
  and `bpf.map` are the data structures.
* **Unprivileged sandboxing.** Landlock exists for that, is unprivileged by design, and is not
  reachable from a kernel module. A script here needs `CAP_BPF`/`CAP_SYS_ADMIN` and is administrator
  policy, not self-restriction.
* **Sleepable LSM hooks in phase 1 to 4.** The kfunc runs from a non-sleepable program; the sleepable
  subset is a documented restriction, not an early feature.

## Risks

| Risk | Mitigation |
|------|-----------|
| BPF LSM is not enabled on the developer's or the user's kernel | Phase 1 needs no boot change at all; phases 2 on detect and skip. Documented in the README, checked by the loader, reported by the tests. |
| `lunatik_ebpf.h` is not on `master`; building on it couples this epic to #561 | Phase 0 settles it explicitly rather than discovering it in phase 2. |
| Hook argument access differs per hook, and a wrong BTF type is a verifier error at best | Stub-packs-a-buffer keeps the C side generic; the per-hook knowledge lives in the stub, which is where a mistake is a load failure rather than a kernel bug. |
| A deny rule locks the operator out of the machine | Examples are allowlists over a scratch scope, never system wide defaults. Tests run the enforcement cases against a dedicated cgroup or a scratch binary. |
| Verdict semantics: not every hook can refuse, and returning the wrong value on a void hook is a verifier rejection | Table of what each hook accepts in `kernel-notes.md`; the stub, not Lua, is responsible for the return type. |
| The interpreter on a hot hook makes the system crawl | The map fast path is phase 4, but the shape is designed for from phase 1: the ctx carries what a decision needs, so a stub can decide without calling in. |

## Definition of done, per phase

1. builds clean on the target kernel, no new warnings;
2. LDoc comments on every new function and object type, and the module listed in `config.ld` in
   alphabetical order;
3. a row in the README module table;
4. a test in the right suite, wired into that suite's `run.sh`, and described in `tests/README.md`;
5. the test skips (not fails) when the kernel lacks the config, the boot parameter, or the tooling;
6. the full suite still passes: `sudo lunatik test`;
7. error paths audited: for every raise, whatever was already acquired is released;
8. commits are small and each one stands alone.

