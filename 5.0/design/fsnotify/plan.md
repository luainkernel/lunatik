# Plan: filesystem notification and permission binding

Execution plan for the `fsnotify` binding.

## Expected results

1. A Lua script can watch filesystem events (open, access, modify, attrib, create, delete, move,
   close, unmount) by marking an inode, a mount or a superblock.
2. A Lua handler receives **permission** events (`FS_OPEN_PERM`, `FS_ACCESS_PERM`,
   `FS_OPEN_EXEC_PERM`) and denies the access by returning a verdict, on a stock distribution kernel.
3. The handler gets the identity of the object involved: event mask, dirent name, inode number,
   directory context.
4. Marks are added, removed and re-masked from Lua, without reloading the script.
5. Two examples — an integrity monitor (notification) and an allow/deny rule (permission) — plus a
   KTAP suite covering the event × object × outcome matrix.

## Where we are today

Lunatik has no filesystem observability at all. The closest existing things are structurally similar
but touch nothing in `fs/notify`:

* `notifier` registers on kernel notifier chains (netdevice, keyboard, vt) and calls a Lua function
  that returns a `linux.notify` status code — the same "callback plus verdict" shape this binding
  needs (`lib/luanotifier.c`);
* `netfilter` runs a Lua callback per packet with a registry-cached `skb` object reset per call, and
  turns the return value into a kernel verdict (`lib/luanetfilter.c`);
* `probe` can observe `security_*` or VFS functions through kprobes, but only observes: a kprobe
  cannot change the outcome of what it probes (`lib/luaprobe.c`);
* `syscall` resolves syscall addresses for probing (`lib/luasyscall.c`).

A full sweep of every local and remote branch found no `fsnotify`, `fanotify` or `inotify` code, and
no issue or pull request on the subject. This is a clean slate.

## What is missing

| Expected result | Gap |
|-----------------|-----|
| Watch filesystem events | No group, no marks, no event delivery. Nothing in `fs/notify` is reachable from Lua. |
| Deny on permission events | No permission handler, no verdict path, and no reentrancy guard — the missing piece that makes this dangerous rather than merely absent. |
| Object identity in the handler | No representation of an event. Name, inode, directory and mask are all C-side only. |
| Dynamic marks | No object lifecycle for a group or a mark, and no path resolution from Lua. |
| Examples and tests | No suite, and no harness for driving file access from a test and asserting the outcome. |

Supporting gaps:

* no `FS_*` constants in `linux.*`; they live in `linux/fsnotify_backend.h`, which is not a uapi
  header — autogen already handles non-uapi headers (`linux/notifier.h`, `linux/sched.h`), so this is
  a spec entry, not a new mechanism;
* no way to turn a Lua path string into a kernel object (`kern_path`), which every mark needs;
* the test suite has no pattern for "run a userspace command, assert it was denied".

## Shape of the work

One new kernel module, `fsnotify` (`lib/luafsnotify.c`), owning two object classes: a **watch** (an
`fsnotify_group` plus its ops) and the **event** passed to the handler. The full API proposal is in
`api.md`; the kernel constraints that drive it are in `kernel-notes.md`.

The single most important of those constraints, because it shapes the whole design:

> Permission events are delivered **synchronously, in the context of the process performing the
> access**, and the return value of the group's `handle_event` is the answer: non zero denies. This is
> not a notification the kernel sends after the fact; the syscall is parked inside your handler. It
> may sleep, which is why a process context runtime works, and it re-enters if the handler touches a
> watched path, which is why a reentrancy guard is part of phase 1 rather than a later fix.

The second constraint worth stating up front: this is **not** an LSM. It sees file access, not
process, credential, capability or socket operations, and it cannot grant anything — it can only
refuse. The rest of the system surface is the subject of the `lsm-ebpf` project.

## Phases

Each phase is one or more self contained pull requests.

### Phase 0: constants

Add the `FS_*` mask constants to autogen as `linux.fs`. Small change that forces a full pass through
the build, the generated `linux.*` modules and the docs pipeline before touching `fs/notify`.

Deliverables: an `autogen/specs.lua` entry for `linux/fsnotify_backend.h` with prefix `FS_` and an
explicit `include` list of the event masks and flags.

No change to `autogen.lua` is needed: the masks are plain hex literals and resolve like any other
define. The `include` list is, because the prefix also matches the group priorities (`FS_PRIO_0/1/2`)
and two constants that belong to inotify and dnotify internals (`FS_IN_IGNORED`, `FS_DN_MULTISHOT`).
`kernel-notes.md` lists what goes in and what stays out. Curating this is most of the work in the
phase; the entry itself is four lines.

### Phase 1: watch and notify

The `fsnotify` module and the watch object: create a group, mark an inode by path, deliver
notification events to a Lua callback, tear down explicitly.

Deliverables: `lib/luafsnotify.c`, `Kconfig`/`Kbuild` entries, `tests/fsnotify/`, README module table
row, `config.ld` entry. The reentrancy guard lands here, with the notification path as its first
test, because phase 2 cannot be reviewed safely without it.

### Phase 2: event identity

Name, inode number, directory inode, `isdir`, and the pid of the process performing the access.
Settles the event object shape: which fields are always available, and which depend on the data type
the kernel handed to the group (`PATH`, `INODE`, `DENTRY`, `ERROR`).

### Phase 3: mark objects

Mount and superblock marks, mask updates on an existing mark, `ignore` masks, mark removal, and
`fsnotify_find_mark` so a script can query what it already installed. This is where the object
lifecycle gets its final shape.

### Phase 4: permission events

`FS_OPEN_PERM`, `FS_ACCESS_PERM`, `FS_OPEN_EXEC_PERM`, the verdict return path, the group priority
requirement, and the version guards for 6.14+ (`fsnotify_mmap_perm`, `fsnotify_truncate_perm`,
pre-content events). Depends on `CONFIG_FANOTIFY_ACCESS_PERMISSIONS`; skips cleanly without it.

This is the point at which the project does something a user can see, and the point at which a bug
locks a machine out of its own files. It lands after the guard, the identity and the lifecycle are
already reviewed.

### Phase 5: examples and documentation

An integrity monitor example (notification: log writes under a directory) and an allow/deny example
(permission: refuse `exec` outside an allowlist), a documentation pass, and whatever API cleanup the
examples expose.

## Sizing

Not a GSoC idea, so this is sized by what fits in a reviewable pull request rather than in hours.

| Scope | Phases |
|-------|--------|
| Minimum useful | 0 to 2. A working watcher: events reach Lua with enough identity to act on. |
| Complete | 0 to 5. Adds the lifecycle, enforcement and the examples. |

Phase 4 is the boundary that matters: everything before it is observability and can be merged on its
own; everything from it on is enforcement and needs the guard and the tests that precede it.

## Non goals

* **Being an LSM.** File access only. Process, credential, capability, socket and IPC surfaces belong
  to the `lsm-ebpf` project.
* **A userspace fanotify client.** This binding registers a *kernel* group, the way `dnotify`, `audit`
  and `nfsd` do. It does not open an fd, does not queue events for userspace, and does not reimplement
  the fanotify uapi.
* **Path based policy in C.** The C side delivers the event; matching (globs, allowlists, sets) is
  Lua's job, using `set`, `rcu` and the string library. The kernel module stays a binding.
* **Content access from the handler.** Reading the file being opened, from inside the handler that
  gates the open, is a deadlock waiting to happen. Out of scope; revisit only with pre-content events
  and a real use case.

## Risks

| Risk | Mitigation |
|------|-----------|
| Reentrancy: the handler triggers the event it is handling | Guard by task identity in phase 1, before any permission work. See `api.md`. |
| A denied event locks the system out of its own files | Examples and tests confine marks to a scratch directory. Documented prominently, and the permission example ships with a deny list, not a default deny. |
| Version drift: `fsnotify_add_mark` signature changed between 6.8 and 6.15; the permission path changed in 6.14 | Version guards from the start, following the `LINUX_VERSION_CODE` pattern already used in `lib/luaxdp.c`. Table of the deltas in `kernel-notes.md`. |
| Group priority requirement for permission events on newer kernels | Set `group->priority` explicitly; verify on both 6.8 and a 6.14+ kernel before phase 4 is called done. |
| `handle_inode_event` versus `handle_event` | The simplified op cannot carry everything the permission path needs. Choice and rationale in `kernel-notes.md`. |
| Sleeping in the handler blocks the watched process, and serializes every other watched access behind the runtime mutex | It is legal and expected here (fanotify parks the syscall waiting for userspace), but the cost is system wide, not per process: one lock, every watched access. Documented as an API contract, measured in phase 4. |

## Definition of done, per phase

1. builds clean on the target kernel, no new warnings;
2. LDoc comments on every new function and object type, and the module listed in `config.ld` in
   alphabetical order;
3. a row in the README module table;
4. a test in `tests/fsnotify/`, wired into that suite's `run.sh`, and described in `tests/README.md`;
5. the test skips (not fails) when the kernel lacks the config it needs;
6. the full suite still passes: `sudo lunatik test`;
7. error paths audited: for every raise, whatever was already acquired is released;
8. commits are small and each one stands alone.

