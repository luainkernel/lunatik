---
name: lunatik-cycle
description: Build, install, reload and run the Lunatik test suites, and recover from a wedged /dev/lunatik, an orphan module, stale autogen output, a vermagic mismatch or a shadowed script. Use when building the tree, running tests, or debugging a module that will not load or unload.
---

AGENTS.md, "Build, install, test", is the authority; this skill orders the workflow.

# The cycle

    make
    make C=1                 # sparse, for a change touching __percpu or another address space
    sudo make install        # never a partial *_install
    sudo lunatik reload      # never rmmod by hand
    sudo lunatik test [suite]

`lunatik test` runs the INSTALLED suite, so `sudo make install` must precede it. When iterating
without module changes, `bash tests/<suite>/run.sh` skips the reload and is gentler on the
device. `make scripts_install` does not install tests: after touching lib or tests, run the full
install, or the installed suite drifts from the tree.

A worktree installs only after `make`: `scripts_install` needs the autogen output. Keep the
install's output visible, and confirm what landed under `/lib/modules/lua/` (timestamp, or a
grep for a symbol only the branch has) before trusting a run against it.

A tree that drops a crash guard (a checker, an `argcheck`) is not installed or run on the shared
host: the test covering the guard reproduces the crash. `crash-guard.sh` blocks it; an experiment
needs the maintainer's authorization first, and `CRASH_AB_OK=1` on the command records that.

`lunatik test` unloads the modules when it finishes: `sudo lunatik reload` before a direct
`bash tests/<suite>/<test>.sh` afterwards, or it skips with `not loaded`.

# One operation at a time

Never run two lunatik operations concurrently (`test`, `run`, `reload`, a suite's run.sh): the
device serializes, and concurrent operations deadlock into unkillable D-state processes that
only a reboot clears. Before starting one:

    ps -eo pid,stat,cmd | grep -E 'lua5.4.*lunatik|[[]lunatik]'   # any D state = wedged

A lunatik command that timed out in your tool did not die: the sudo child keeps holding the
device, and killing the wrapper does not kill it. Confirm the child is gone before relaunching;
run long operations one at a time and wait for completion.

# When something will not load or unload

The recovery paths are in AGENTS.md, "Build, install, test": the orphan module that escapes
reload, the stale autogen output after a branch switch, the scratch script shadowing an
installed module, the pinned core, the vermagic mismatch after a kernel upgrade. Match the
symptom there before improvising.

Normal readings, not leaks: `lsmod` showing luathread/luadevice/lualinux with refcnt=1 on an
idle system is the driver runtime's require-pins (a kernel `require()` pins the owning module
until that state's `lua_close`). `/sys/module/X/holders` lists only symbol dependencies, not
require-pins; `refcnt` is the complete in-degree.

# A wedged device: before and after the reboot

A `lunatik` process in D state does not come back, and the reboot that clears it is the
maintainer's call (AGENTS.md, "Build, install, test"). Before asking for it:

    ps -eo pid,stat,etime,cmd | awk '$2 ~ /D/'          # confirm, and note the PID
    tools/oops.sh > scratch/oops-$(date +%F).txt         # dmesg block, faulting instructions, D-state processes

Then write down (memory or scratch) which tree `make install` last ran from and its HEAD, the
suites not yet run, and the branches whose tests were interrupted. Run no further `lunatik`
command; the D-state child cannot be killed and every new one queues behind it.

After the reboot, in this order:

    uname -r                                             # a kernel upgrade may have come with it
    journalctl -k -b -1 -o cat > scratch/oops-$(date +%F).txt   # if the capture was missed
    sudo apt install linux-headers-$(uname -r) linux-tools-$(uname -r)
    git worktree prune                                   # scratch worktrees under /tmp are gone
    git worktree add <scratch>/w<name> <ref> && git -C <scratch>/w<name> submodule update --init
    make clean && sudo make btf_install && make && sudo make install && sudo lunatik reload
    sudo lunatik test <the suite that oopsed>            # twice

A second oops is the bug, traced from `scratch/oops-*.txt`; a clean pair means the trigger
was state the reboot cleared, reported as untraced. Then the pending list, in the order the
branches stack.

