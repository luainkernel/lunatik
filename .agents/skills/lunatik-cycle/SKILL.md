---
name: lunatik-cycle
description: Build, install, reload and run the Lunatik test suites, and recover from a wedged /dev/lunatik, an orphan module, stale autogen output or a vermagic mismatch. Use when building the tree, running tests, or debugging a module that will not load or unload.
---

AGENTS.md, "Build, install, test", is the authority on the cycle; this skill orders it and carries what
the shared host does to it.

# The cycle

    make
    make C=1                 # sparse, for a change touching __percpu or another address space
    bash tools/lunatik-host bash -c 'sudo make install && sudo lunatik reload && sudo lunatik test'

The lock covers install through test as one cycle, since the device and the installed tree under
`/lib/modules/lua` are shared: another session that installs between your install and your run
gives you its scripts against your modules. Inside the lock the steps are the usual ones, never a
partial `*_install` and never `rmmod` by hand:

    sudo make install
    sudo lunatik reload
    sudo lunatik test [suite]

`lunatik test` runs the INSTALLED suite, so `sudo make install` must precede it. When iterating
without module changes, `bash tests/<suite>/run.sh` skips the reload and is gentler on the
device. `make scripts_install` does not install tests: after touching lib or tests, run the full
install, or the installed suite drifts from the tree.

A worktree installs only after `make`: `scripts_install` needs the autogen output. Keep the
install's output visible, and confirm what landed under `/lib/modules/lua/` (timestamp, or a
grep for a symbol only the branch has) before trusting a run against it. `tools/lunatik-host` runs
`tools/checks/disk.sh` first: a build that stops halfway on a full disk leaves the previous install in
place, and the suite then measures that one; the check names the worktrees to remove.

A tree that drops a crash guard (a checker, an `argcheck`) is not installed or run on the shared
host: the test covering the guard reproduces the crash. `crash-guard.sh` blocks it; an experiment
needs the maintainer's authorization first, and `CRASH_AB_OK=1` on the command records that.

`lunatik test` unloads the modules when it finishes: `sudo lunatik reload` before a direct
`bash tests/<suite>/<test>.sh` afterwards, or it skips with `not loaded`.

`lunatik reload` refuses with `couldn't replace <modules>: loaded from another build` when something
still holds a module it had to replace, and no suite runs until it passes. The holder is in `lsmod`'s
`Used by` column or in `lunatik list`; stop it and reload. A module nothing names is pinned until a
reboot, which is the maintainer's.

A scratch script under `/lib/modules/lua` is written with the editor and copied in with `sudo cp`,
and its size is read before it runs: a `tee` under a `sudo` that takes its password on stdin gets
the rest of that stdin as the file and writes it empty, and `lunatik run` of an empty script exits
0 and prints nothing, which reads as a clean run. Remove the script right after.

An example is run through `sudo bash tools/watchdog.sh examples/<script> [spawn | [--context=softirq|hardirq] [--percpu]]`,
which stops it if the host loses the connectivity it had; an example that returns a thread body takes
`spawn` there, or its function is never called. `example-guard.sh` refuses a bare `lunatik run` or
`spawn` of an example, and `NETWORK_LOSS_OK=1` on the command runs one bare on a machine whose
connectivity is expendable.

# When a test fails

A failure is read before anything is run again: a rerun that passes measures the rerun, not the
code, and the ring buffer is no record, since every test clears it at its start. The journal keeps
every unit's lines, and the window around the test's own prints is where a host process acting on
what the test created shows up:

    bash tools/journal.sh "nl80211_station: added"      # every unit, 3 s around the last match; adm or sudo

Read which of the test's prints came out and which did not, then what NetworkManager, networkd,
wpa_supplicant or udev did to the interface, the device or the file in that window; the errno the
KTAP line carries is then matched to the kernel function that returns it on the path between the
last print and the missing one. The hand-back names that mechanism, or carries the failure as a
hypothesis with what was not captured; `tools/checks/untraced.sh` refuses the word that skips both.

# One operation at a time

Never run two lunatik operations concurrently (`test`, `run`, `reload`, a suite's run.sh): the
device serializes, and concurrent operations deadlock into unkillable D-state processes that
only a reboot clears. Before starting one:

    ps -eo pid,stat,cmd | grep -E 'lua5.5.*lunatik|[[]lunatik]'   # any D state = wedged

`lunatik-lock.sh` looks for the same processes before a shell call and refuses the second operation;
`LUNATIK_LOCK_OK=1` on the command overrides it once what it lists is known to be stale.

A lunatik command that timed out in your tool did not die: the sudo child keeps holding the
device, and killing the wrapper does not kill it. Confirm the child is gone before relaunching;
run long operations one at a time and wait for completion.

# What the shared host does

`lunatik reload` cannot replace a module while something still holds it, and `make install` writes
the new file beside the one still loaded. After loading, `reload` compares each loaded module's
`srcversion` with the installed file's and refuses with `couldn't replace <modules>: loaded from
another build`, which stops `lunatik test` before the suite; `lunatik status` names the same
modules. A kernel thread outliving its
runtime is one way to pin a module, and nothing short of a reboot gets it back, so a test that
spawns one gives its body work that ends rather than a loop waiting to be stopped. A reference an
object leaks is another, and every cycle after it adds to the count. `tools/lunatik-host` refuses a cycle on a host
pinned that way, reading through `tools/checks/pinned.sh` the references a module keeps past its
holders once `lunatik_run` is gone, and names the cycle that leaves the host so; the state is
captured for the maintainer, whose reboot clears it, and `LUNATIK_PINNED_OK=1` runs a recovery that
knows what it holds. It also names a process a cycle leaves running, an orphan in its cgroup started
after the command: a `socat ...,fork` stopped with `kill $!` keeps the child it forked for a
connection, and a child whose peer sat in a namespace the cycle deleted holds its socket open for
good, a page of a veth's XDP `page_pool` among what it keeps.

After a kernel upgrade the installed modules were built for the previous kernel and fail to load with
`Exec format error` (a vermagic mismatch). Reinstall the headers, `make clean && make`, and reinstall
before the next `reload`. The eBPF modules also need the running kernel's BTF at build time,
`sudo make btf_install` before `make`, or they load without their kfunc, logging `missing module
BTF`, and every BPF program that calls it fails to load; and the `bpftool` wrapper needs
`linux-tools-$(uname -r)`, or every BPF program fails to load. `examples/filter` and
`examples/sniclassify` load the objects `make ebpf` builds in the checkout, which `make` does not:
run from a worktree without them, filter fails its attach and sniclassify its setup, and the run
measures nothing.

A wedged device — a `lunatik` process that stays in D state, usually below an oops in `dmesg` — is
cleared only by a reboot, as a pinned module is, and the reboot is the maintainer's to trigger: other
sessions share the host. Before asking, capture what the reboot erases with `tools/prereboot.sh`,
which saves the oops, the modules and what holds them, and every session's files under `/tmp` into
`scratch/reboot-<time>/`, write down which suites were pending and which build was installed, and
run nothing else against the device. After it, the suite that oopsed runs twice: a second oops is a
bug to trace, a clean pair is a symptom without its cause, said as such; "A wedged device" below orders both halves. One process in D on one look is not that: an ordinary `lunatik stop` sits there
while the kernel works, so what names a wedge is the one still in D on the next look.

What reaches a terminal after a machine dies is a fragment. The previous boot's kernel log survives in
the journal, `journalctl -b -1 -k`, and it carries the registers of every oops in the cascade, which is
what tells one faulting pointer from another. Read that before theorising from the excerpt, and resolve
the faulting `pc` against the disassembly of the module that was loaded — the `Code:` line in the oops
matches the build word for word, so it also proves which build crashed. A name in the trace is
resolved too, never read: `Comm:` is the task's own `comm`, which a thread sets for itself with
`PR_SET_NAME`, so `ps` or `/proc/<pid>/exe` says what ran it, and a symbol is confirmed in
`/proc/kallsyms`.


`lunatik reload` unloads only the modules the installed CLI lists. A module loaded from another
branch's install escapes it and pins the core: `rmmod` reports `Module lunatik is in use by ...`
while `lunatik list` is empty. Diff `lsmod` against the installed `lunatik/config.lua` to find the
orphan and `rmmod` it — the one case where a manual `rmmod` is the fix.

The autogen output (`autogen/linux/*.lua`, `autogen/.config`, `autogen/.stamp`) is untracked build
state and does not follow a branch switch. The symptom is a runtime `attempt to index a nil value`
on a `linux.*` constant, not a build error. Regenerate cleanly with `rm -f autogen/.stamp && make`:
the stamp's recipe clears `autogen/linux/*.lua` itself.

A worktree that has not run `make` cannot install: `scripts_install` needs the autogen output and
stops there, once it has rewritten the libraries and emptied `linux/`, with the previous install's
`lunatik/`, modules, examples and tests still in place. An install whose output was silenced
fails unseen, so every run after it tests that mix. A silenced `make` does the same one step earlier:
the chain stops at the build and the suite run next reports on the modules already installed. Keep the
build's and the install's output visible, and before reading a result confirm that what sits under
`/lib/modules/lua/` is the tree under test: its timestamp, or a grep for a symbol only the branch has.

`lunatik test` reloads the modules before the suite and unloads them after it. A test script run
directly afterwards (`bash tests/<suite>/<test>.sh`) skips with `not loaded` until the next
`lunatik reload`; that unload is the CLI's, not a leak.

`make install` clears each directory it writes under `/lib/modules/lua/` before writing it, and
leaves a scratch script at the top level in place.

Trust the formal test over manual poking. Iterating by hand — `lunatik run`/`stop`, `iw`, `ip`,
`rmmod`, `modprobe` — leaves stale state that wedges the next run: an interface in the wrong mode, an
orphan `.ko` still pinning the core, a script still registered. A test's `.sh` does its own setup and
teardown; a green formal test is the authoritative result, not a red manual scratch fighting leftover
state. A known-clean baseline is a precondition for a valid observation, not an afterthought: restore
it before a run and again after, so what the next run sees is the code under test, not the residue of
the last one.

# When something will not load or unload

The recovery paths are under "What the shared host does" above: the orphan module that escapes
reload, the stale autogen output after a branch switch, the pinned core, the vermagic mismatch
after a kernel upgrade. Match the symptom there before improvising.

Normal readings, not leaks: `lsmod` showing luathread/luadevice/lualinux with refcnt=1 on an
idle system is the driver runtime's require-pins (a kernel `require()` pins the owning module
until that state's `lua_close`). `/sys/module/X/holders` lists only symbol dependencies, not
require-pins; `refcnt` is the complete in-degree.

# A wedged device: before and after the reboot

A `lunatik` process in D state does not come back, and the reboot that clears it is the
maintainer's call ("What the shared host does" above). Before asking for it:

    ps -eo pid,stat,etime,cmd | awk '$2 ~ /D/'          # confirm, and note the PID
    bash tools/prereboot.sh                              # oops, modules and holders, D-state processes, every session's /tmp

Then write down (memory or scratch) which tree `make install` last ran from and its HEAD, the
suites not yet run, and the branches whose tests were interrupted. Run no further `lunatik`
command; the D-state child cannot be killed and every new one queues behind it. A module pinned
past `lunatik reload` takes the same capture before its reboot is asked for.

After the reboot, in this order:

    uname -r                                             # a kernel upgrade may have come with it
    journalctl -k -b -1 -o cat > scratch/oops-$(date +%F).txt   # if the capture was missed
    sudo apt install linux-headers-$(uname -r) linux-tools-$(uname -r)
    git worktree prune                                   # scratch worktrees under /tmp are gone
    ls scratch/reboot-*/tmp                              # what each session kept under /tmp
    git worktree add <scratch>/w<name> <ref> && git -C <scratch>/w<name> submodule update --init
    make clean && sudo make btf_install && make && sudo make install && sudo lunatik reload
    sudo lunatik test <the suite that oopsed>            # twice

A second oops is the bug, traced from `scratch/oops-*.txt`; a clean pair means the trigger
was state the reboot cleared, reported as untraced. Then the pending list, in the order the
branches stack.

