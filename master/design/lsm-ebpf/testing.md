# Testing the LSM binding

Lunatik's tests are shell scripts emitting KTAP, driving a kernel Lua script and asserting on what it
prints to `dmesg` or on what userspace observes. `tests/bpf/` is the closest existing suite — it
already deals with maps and pinned objects — and the XDP path in `examples/filter/` shows the build
and load sequence a stub program needs. Read both, plus `tests/lib.sh`, before writing anything new.

Run everything with `sudo lunatik test`, one suite with `sudo lunatik test lsm`.

## What this suite needs that others do not

**A stub program, built at test time.** Every test here has three parts, not two: the shell script,
the kernel Lua script, and an eBPF object. The suite needs `clang -target bpf` and `bpftool`, and
`sudo make btf_install` must have run so the stub can resolve our kfunc. Missing any of them is a
skip, not a failure.

**Two skip levels, checked in the suite's `run.sh` before anything else.**

    grep -qw bpf /sys/kernel/security/lsm   # phases 2+; absent on stock Ubuntu
    test -d /sys/fs/cgroup                  # phase 1

The first is the one that matters: on a machine booted without `lsm=...,bpf` every LSM test must skip
with a message saying so, and report `ktap_skip` per planned test so the plan count stays honest. A
suite that fails there would fail on most developers' machines and be ignored within a week.

**A scratch cgroup for the enforcement tests.** Phase 1 tests attach to a cgroup created by the test,
never to the root cgroup:

    CG=/sys/fs/cgroup/lunatik-test
    mkdir -p "$CG"
    cleanup() { bpftool cgroup detach "$CG" ... 2>/dev/null; rmdir "$CG" 2>/dev/null; ...; }
    trap cleanup EXIT

Then run the traffic with `echo $$ > "$CG/cgroup.procs"` in a subshell, so only that subshell is
subject to the policy. A test that attaches to the root cgroup and denies `connect` takes the machine
off the network, including whatever the operator was using to watch the test run.

**A way to assert a denial.** Userspace side: run the operation, check the error.

    if ! out=$(timeout 5 nc -w1 "$BLOCKED" 80 2>&1) && echo "$out" | grep -q "Permission denied"; then

Assert on both the failure and the specific error, so a test does not pass because the host was
unreachable anyway.

**Pinned link cleanup.** LSM attachments are pinned links that outlive the process that made them. A
test that leaves one behind leaves the policy installed. Unpin in the `trap`, and run the cleanup once
up front too, so a previous crashed run does not poison the next one.

## Test matrix

Fill this in as the phases land. Each row is one `.sh` plus one `.lua` (plus one `.c` for the stub),
following the convention that the description of the test lives in the shell script and the Lua file
carries a single line pointing back at it.

Coverage means the matrix of hook × outcome, including the allows, not a list of features.

### Phase 1: `tests/cgroup/`

| Test | Proves |
|------|--------|
| `attach.sh` | `cgroup.attach` from a non-sleepable runtime registers; from a sleepable one it raises |
| `allow.sh` | a callback returning 0 lets the connection through — the success case a broken verdict path breaks silently |
| `deny.sh` | a callback returning `-EPERM` makes `connect` fail with `EACCES`/`EPERM` inside the test cgroup, while the same connection succeeds outside it |
| `address.sh` | `ctx:address()` and `ctx:port()` match what the test dialled |
| `rewrite.sh` | setting `ctx:address()` redirects the connection to a local listener |
| `argument.sh` | data packed by the stub arrives intact and unpacks with `struct` |
| `detach.sh` | after `cgroup.detach()` the traffic flows unfiltered |
| `nokey.sh` | a stub naming a runtime that does not exist fails loudly rather than silently allowing |

### Phase 2 and 3: `tests/lsm/`

Every test skips without `bpf` in the active LSM list.

| Test | Proves |
|------|--------|
| `available.sh` | `lsm.available()` agrees with `/sys/kernel/security/lsm` |
| `attach.sh` | attach registers, and a second attach on the same runtime replaces rather than duplicates |
| `allow.sh` | a callback returning 0 lets an exec proceed |
| `deny.sh` | a callback returning `-EPERM` makes the exec of a scratch binary fail with `EPERM`, and an exec of another binary still works |
| `default.sh` | a callback that returns nothing allows, rather than denying |
| `chain.sh` | the stub's `if (ret) return ret` is honoured: a hook already refused upstream stays refused even when the callback returns 0 |
| `hookid.sh` | the `hook` argument distinguishes two hooks served by one runtime |
| `argument.sh` | the packed argument arrives and decodes, for each hook in the phase 3 stub set |
| `pid.sh` | `ctx:pid()` is the process performing the operation |
| `error.sh` | a callback that raises does not wedge the hook; the documented behaviour is what happens |

`allow.sh`, `default.sh` and `chain.sh` exist because the dangerous failure of this feature is not a
missed denial, it is a module that denies everything or that converts someone else's denial into an
allow. A suite that only asserts denials passes on both.

### Phase 4: `tests/lsm/` (fast path)

| Test | Proves |
|------|--------|
| `map_hit.sh` | an entry written from Lua decides in the stub, and the Lua callback is never invoked (count invocations) |
| `map_miss.sh` | a key absent from the map falls through to the callback |
| `map_update.sh` | rewriting the map from Lua changes the decision without reloading anything |
| `bench.sh` | reports decisions per second for the map path and the callback path; informational, not a pass/fail gate |

`map_hit.sh` is the one that proves the design claim. Write it as soon as phase 4 starts: if the
callback runs anyway, the fast path does not exist and the API is wrong.

**Counting invocations**, which two rows above depend on, needs one shape used everywhere rather than
one per test. The callback increments a counter in an `rcu.table` shared with a reader script, and the
shell reads it after driving the traffic:

    local shared = rcu.table()          -- in the kernel script
    shared.calls = (shared.calls or 0) + 1

Assert on the delta across the run, not the absolute value, so a previous run cannot make a test pass.
`tests/bpf/` already drives pinned maps from the shell and is the model for the plumbing.

### Phase 5 and 6

| Test | Proves |
|------|--------|
| `cgroup_scope.sh` | a `BPF_LSM_CGROUP` policy applies inside the cgroup and not outside it |
| `task_storage.sh` | per-task state survives across hook invocations for the same task and is not shared with another |
| `example_auditor.sh` | the exec auditor example loads, logs an exec, and stops cleanly |
| `example_sandbox.sh` | the allowlist sandbox denies a binary outside the list and permits one inside it |

## Conventions to follow

* skip, do not fail, when the kernel lacks a config, the boot parameter or the tooling;
* mark `dmesg` before the run, read only what came after, and `check_dmesg` at the end;
* clean up in a `trap` — detach, unpin, remove the cgroup — and run the cleanup once up front;
* `lunatik run` exits 0 even when the script fails to load; assert on output, never on exit status;
* one `.sh` per row above, wired into the suite's `run.sh` and described in `tests/README.md` in the
  same commit as the code it tests.

## Verifying on a kernel that has BPF LSM

The development machine is not enough for phases 2 and later. Before calling one of them done, run
the suite on a kernel booted with `bpf` in the LSM list:

    GRUB_CMDLINE_LINUX="... lsm=lockdown,capability,landlock,yama,apparmor,bpf"
    sudo update-grub && sudo reboot
    grep -w bpf /sys/kernel/security/lsm       # confirm before trusting a green run

A green suite on a machine without `bpf` in that list means every LSM test skipped. Check the totals,
not the exit status: `# Totals: pass:0 fail:0 skip:12` is not a passing phase.

