---
name: lunatik-cycle
description: Build, install, reload and run the Lunatik test suites, and recover from a wedged /dev/lunatik, an orphan module, stale autogen output, a vermagic mismatch or a shadowed script. Use when building the tree, running tests, or debugging a module that will not load or unload.
---

AGENTS.md, "Build, install, test", is the authority; this skill orders the workflow.

# The cycle

    make
    sudo make install        # never a partial *_install
    sudo lunatik reload      # never rmmod by hand
    sudo lunatik test [suite]

`lunatik test` runs the INSTALLED suite, so `sudo make install` must precede it. When iterating
without module changes, `bash tests/<suite>/run.sh` skips the reload and is gentler on the
device. `make scripts_install` does not install tests: after touching lib or tests, run the full
install, or the installed suite drifts from the tree.

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

