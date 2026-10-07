# Landlock as a reference model

Landlock is the kernel's own sandbox: a process declares which accesses a ruleset handles, adds rules
that allow some of them on some objects, and restricts itself; from then on its domain only narrows.
It is built as an LSM (`security/landlock/`), so it is the closest in-tree model of what the policy
fast path (#669), the scoped policy (#670) and the sandbox example (#671) are for. This note takes its
choices one by one and says what each means for those phases. It is a reference, not a phase:
Landlock is read as a policy model, not as a registration path (`kernel-notes.md` settles that), and
unprivileged self-sandboxing stays a non goal (`plan.md`).

The kernel sources were read at the upstream tags `v6.8` and `v6.6`, the tree's floor. A citation
reads `file:line` at `v6.8`, then the `v6.6` line after a slash; a file under `security/landlock/`
is named without its directory. The Ubuntu 6.8 tree carries stable backports into
`security/landlock/` that move lines, so the numbers are the tags', not a distribution's. Landlock's
ABI is 3 at `v6.6`, filesystem only, and 4 at `v6.8`, which adds TCP `bind` and `connect`
(`LANDLOCK_ABI_VERSION`, `syscalls.c:140/132`). What later releases changed is named where it
matters. Recommendations for the maintainer are marked as such; the rest is what the sources say.

## The model

`landlock_create_ruleset()` takes the access rights the ruleset *handles*; `landlock_add_rule()`
adds rules that *allow* some of them on a file or beneath a directory named by an `O_PATH`
descriptor, or on a TCP port; `landlock_restrict_self()` merges the ruleset into the calling
thread's domain as a new layer. An access is granted when every layer either does not handle it or
finds a rule on the path that allows it (`landlock_unmask_layers`, `ruleset.c:623`, `unmask_layers`
in `fs.c:232` at `v6.6`). The domain lives in the thread's credentials and follows it through `fork`
and `execve`.

## Handled: the default when a key is absent

What Landlock does:

* A right no layer handles is granted without a walk: `landlock_init_layer_masks`
  (`ruleset.c:689`, `init_layer_masks` in `fs.c:315` at `v6.6`) sets a layer's bit only for a right
  that layer handles, and a request left empty is granted before the walk (`fs.c:415/504`).
* A handled right that no rule on the walk grants is refused: the walk reaches the real root with the
  layer's bit still set (`fs.c:529/613`) and the hook answers `EACCES`.
* Rules only allow. A rule with an empty `allowed_access` is refused with `ENOMSG`, since "empty
  allowed_access (i.e. deny rules) are ignored in path walks" (`syscalls.c:306/340`); a rule may
  allow only what its ruleset handles (`EINVAL`); a ruleset that handles nothing is refused as well
  (`ruleset.c:59/53`).
* "Handled" belongs to the ruleset, fixed when it is created, one mask per layer (`access_masks[]`,
  `ruleset.h:229`; `fs_access_masks[]`, `ruleset.h:151` at `v6.6`). The userspace documentation
  gives the reason: the program and the kernel may not know each other's rights, so the denied by
  default set is explicit and a kernel update never makes a sandbox stricter (`landlock.rst`,
  "Compatibility").

#669 maps a key to allow or deny and sends an absent key to Lua (`api.md`, "The policy fast path":
`1 = allow, 2 = deny, absent = ask Lua`). That is a different model: Landlock has no deny entries
and no escape hatch, and an absent key is a denial inside what is handled. Two questions follow.

*Whose property is "handled".* Kept in the map, as an entry per hook that turns governance on, it
lets Lua govern or release a hook without touching the program, but a map never written, or written
halfway by a script that raised, governs nothing and allows everything without a word. Kept in the
program, the hook a stub is attached to is the handled set, and the stub's source fixes what an
absent key means there, as the mask given to `landlock_create_ruleset` does. The bridge on `master`
already puts the default in the program: `bpf_luaxdp_run` answers `-1` when no verdict was reached,
and `examples/filter/https.c` decides `action < 0 ? XDP_PASS : action`.

*What absent means, per hook.* Sent to Lua, every key the map does not name pays the interpreter,
about 4.5 µs against 70 ns in the NetBSD measurement `plan.md` cites; on `bprm_check_security` that
is each exec of an unlisted binary, on `file_open` nearly every open in the scope. Read as a denial,
as in Landlock, the map is the whole allowlist, a denial never enters Lua, and a rule that needs Lua
is an entry that says so.

**Recommendation for the maintainer.** "Handled" is the program's: attaching a stub puts a hook under
policy, and the default for an absent key is a constant of that stub, not of the map. The map's
values are `ALLOW`, `DENY` and `ASK`, the last being #669's functional rule, so one layout serves
every stub. The sandbox stub of #671 reads an absent key as `DENY`, Landlock's default; the stub of
#669's example reads it as `ASK`. The criterion "a key absent from the map falls through to the
callback" then describes that stub, and the convention #669 documents says which stub has which
default.

## Identity against a path string

What Landlock does:

* A rule names a file or a directory by an `O_PATH` descriptor (`get_path_from_fd`,
  `syscalls.c:258/244`). The kernel ties the inode to a `landlock_object` and the rule keys on that
  object (`get_inode_object`, `fs.c:88/88`), which holds the inode (`ihold`, `fs.c:138/138`) until
  no rule names it or its filesystem shuts down (`hook_sb_delete`, `fs.c:844/927`).
* A check walks from the accessed dentry to the real root, parent by parent (`dget_parent`), crossing
  mounts with `follow_up`, and looks each inode's object up in the domain
  (`is_access_to_paths_allowed`, `fs.c:396/485`; `find_rule`, `fs.c:197/206`).
* The author gives the reason for not using path strings: a sandboxed process may sit in a mount
  namespace of its own, so "a sandboxing security policy cannot be defined with absolute file paths
  like used by AppArmor and Tomoyo"; file labels and extended attributes are ruled out as well
  (Salaün 2024, section 7.3).

What a rename does there: the anchor of a rule is identity, what lies beneath it is location. A
ruled directory keeps its rule when renamed; a file moved out from under it loses the grant at its
next access, and one moved in gains it. A sandboxed task could gain rights by moving files, and
`LANDLOCK_ACCESS_FS_REFER` (ABI 2) closes that: `current_check_refer_path` (`fs.c:731/813`) answers
`EXDEV` to a link or a rename that would leave the file with more rights where it lands, and `REFER`
is denied in every domain that handles the filesystem (`LANDLOCK_ACCESS_FS_INITIALLY_DENIED`,
`ruleset.h:29`; `ACCESS_INITIALLY_DENIED`, `fs.c:159` at `v6.6`). A task whose domain handles the
filesystem may not change the mount topology at all (`hook_sb_mount` and its siblings,
`fs.c:966/1049`, through `get_current_fs_domain` at `v6.8`, `fs.c:250`), since the policy is defined
over it. A rename by a task outside the domain is not checked, and the rule moves with the
directory.

What the stub has: at `bprm_check_security`, `bprm->file`, and so the inode, and `bprm->filename`,
the name the caller passed to `execve` (`alloc_bprm`, `fs/exec.c:1554/1520`); at `file_open`,
`file->f_path`. Both hooks are in `sleepable_lsm_hooks`, and `bpf_d_path` is allowed to an LSM
program on any hook of that set, sleepable or not (`bpf_d_path_allowed`,
`kernel/trace/bpf_trace.c:953/946`), so the stub can also build a path from the file. Two strings,
then:

* `bprm->filename` is relative when the caller's was (`./hello`); it is one of several names for a
  file: on a merged `/usr` distribution `/bin` is a symlink to `usr/bin`, so `/bin/true` and
  `/usr/bin/true` are one inode, and `api.md`'s allowlist names the first; and it stays the script's
  name when the interpreter is checked, since `exec_binprm` switches `bprm->file` to the interpreter
  and runs `security_bprm_check` again (`fs/exec.c:1832/1788`, `:1771/1727`);
* the path `bpf_d_path` builds from the file settles those three, but it is absolute from the task's
  own root (`d_path`, `fs/d_path.c:286/286`), so it names the file where the caller's mount
  namespace and root put it, and it costs a walk and a string copy per decision;
* either is cut at the key width, 64 bytes in the sketch (`"c64"`), where two long paths with a
  common prefix share a key.

| Event | Path string key | Inode key, `(s_dev, i_ino)` |
|-------|-----------------|-----------------------------|
| file renamed or hard linked | the new name misses: an `ALLOW` is lost, a `DENY` is escaped | follows the file |
| file copied | misses | misses: a new inode |
| package upgrade, a new file renamed over the old | still matches | misses: a new inode |
| file deleted, another one created | a file created under the name inherits the entry | a file given the freed number inherits the entry |
| exec through a symlink or a relative name | `bprm->filename` differs, the `d_path` string does not | the same inode |
| another file mounted, or chrooted, at an allowed path | matches: the `ALLOW` extends to it | misses: another inode |
| another file with the same number on the superblock: in another btrfs subvolume, or in another layer of an overlay across filesystems without `xino` | misses | matches: the `ALLOW` extends to it |

For an allowlist a miss fails closed: the binary is refused until Lua writes its key. A string that
matches another file fails open: a task that can mount or chroot puts its own binary under an
allowed name, which is the author's argument above. A deny entry keyed on a name is defeated by `ln`
and `mv`; Landlock has no deny rules at all.

Reuse of a number is a hazard Landlock does not have and a map does: a rule holds its inode, while a
hash entry keyed by `(s_dev, i_ino)` holds nothing, and after the file goes its number can return as
another file on the same filesystem. On some filesystems two live files share the pair as well: btrfs
numbers the inodes of each subvolume from a counter of its own under one superblock
(`root->free_objectid++`, `fs/btrfs/disk-io.c:4957/4966`; `btrfs_find_actor`, which matches the
root as well as the number, `fs/btrfs/inode.c:5545/5514`), and an overlay whose layers sit on
different filesystems without `xino` gives a non-directory the number its layer gave it
(`ovl_map_ino`, `fs/overlayfs/inode.c:861/985`). `stat` tells those files apart by a device of its
own, the subvolume's (`btrfs_getattr`, `fs/btrfs/inode.c:8750/8656`) or the layer's
(`ovl_map_dev_ino`, `fs/overlayfs/inode.c:153/153`), which is not the superblock's `s_dev` the stub
reads. BPF has the counterpart of Landlock's per-inode object: inode
storage (`BPF_MAP_TYPE_INODE_STORAGE`) hangs a value off the inode's LSM blob
(`include/linux/bpf_lsm.h:39/39`) and frees it with the inode. From userspace its key is a file
descriptor (`kernel/bpf/bpf_inode_storage.c:81/81`), as `landlock_add_rule` takes an `O_PATH` one;
`lib/luabpf.c` opens hash, array, LRU hash, queue and stack maps only, and a descriptor key means
nothing to a kernel runtime. An LSM program can write inode storage itself
(`BPF_FUNC_inode_storage_get`, `kernel/bpf/bpf_lsm.c:208/208`), so a verdict Lua returns on a miss
can be cached on the inode it was about.

Lua cannot name an inode key today either: no binding turns a path into `(s_dev, i_ino)`;
`fsnotify`'s `event:ino` reports an event's inode number, without the device. `luabpf_map_get`
already resolves a path with `kern_path` to find a pin, and the identity is read from the same
`struct path`. `fsnotify`'s `watch:mark` is the tree's precedent for Landlock's stance: a path
resolved once, the mark on the inode.

A rule on a directory that covers what lies beneath it, Landlock's `path_beneath`, needs the walk in
the stub: a bounded loop over `d_parent`, and across mounts the parent `struct mount` that
`follow_up` reads, a type internal to `fs/mount.h` though present in the kernel's BTF. That walk has
not been prototyped.

**Recommendation for the maintainer.** The fast path keys on the inode, `(s_dev, i_ino)` read by
the stub from the file the hook carries, and the path travels in the `data` argument, where Lua
reports it and matches on it in a functional rule. Neither string names the file: one is what the
caller typed, the other where the file sits in the caller's view, and a rename or a link defeats
both, a mount by matching another file; the inode key fails closed on what defeats it for an
allowlist, a copy and an upgrade, and #671's example says that an upgraded binary needs its key
written again; on btrfs and on an overlay across filesystems without `xino` the pair is not unique,
and there it fails open as a mounted path does. Lua gets a way to turn a path into that key, read
from the inode's superblock as the stub reads it and not from `stat`; directory rules wait for the
walk to be prototyped, and inode storage, which removes reuse and those collisions, for a Lua-side
way to write it.

## The ratchet and inheritance

What Landlock does:

* `landlock_restrict_self` builds a domain from the thread's current one plus the new ruleset as a
  further layer (`landlock_merge_ruleset`, `ruleset.c:538/403`). Every layer must grant, so a layer
  can only narrow; at 16 layers (`LANDLOCK_MAX_NUM_LAYERS`, `limits.h:18/18`) the call answers
  `E2BIG` (`ruleset.c:550/415`); nothing removes a domain.
* The domain is a pointer in the credentials' LSM blob, installed by `commit_creds`
  (`syscalls.c:504/448`) and copied by `hook_cred_prepare` (`cred.c:17/17`) whenever
  `prepare_creds` runs `security_prepare_creds` (`kernel/cred.c:242/294`). That carries it through
  `fork` (`copy_creds`, `kernel/cred.c:290/343`, which shares the parent's credentials with a
  `CLONE_THREAD` child and prepares a copy otherwise) and through `execve` (`prepare_exec_creds`,
  `kernel/cred.c:257/310`). Its task-side hooks are `cred_prepare` and `cred_free`; `task_alloc`
  and `bprm_committed_creds`, which #1007 names, are not among them at either tag.
* Sibling threads are not restricted, unlike a POSIX credential change (`landlock.rst`,
  "Inheritance"), and a landlocked task may `ptrace` only a task in a subdomain of its own
  (`domain_scope_le`, `ptrace.c:32/32`).

What #670 has instead:

* A cgroup follows `fork` as well: a child is born into its parent's cgroup
  (`Documentation/admin-guide/cgroup-v2.rst:267/238`), and `execve` does not move it. What differs is
  who can undo it. Moving a task takes write access to the destination's `cgroup.procs` and to the
  common ancestor's (`cgroup-v2.rst:560/524`), so an unprivileged task cannot leave a scope whose
  ancestors root owns; the administrator can, and can rewrite the map from Lua or detach the program.
  The scope is the administrator's choice and stays in the administrator's hands: not a ratchet, and
  not meant to be one.
* Task storage does not follow `fork`: every new task starts without it
  (`RCU_INIT_POINTER(p->bpf_storage, NULL)`, `kernel/fork.c:2462/2466`). A stub that wants
  Landlock's inheritance copies the parent's entry itself, from `task_alloc`: the hook #1007 names is
  the one BPF would need, not the one Landlock uses. #670 declines inheritance semantics of its own,
  so its task storage is per-task state and its scope is the cgroup.

**Recommendation for the maintainer.** The sandbox of #671 says at its top that it is administrator
policy scoped by a cgroup: the box's maintainer chooses the scope, can loosen it by writing the map,
and a task leaves it only through a migration the administrator allows. It promises no ratchet, and
points to Landlock for a process that restricts itself, the non goal `plan.md` states. A ratchet in
the bridge would need task storage copied at `task_alloc` and entries that only narrow, the
inheritance model #670 declines to invent.

## Fail-closed, against fsnotify's fail-open gate

Landlock refuses in two places, for different reasons, and leaves a third to the application:

* Applying: `landlock_restrict_self` answers `EPERM` unless the thread runs with `no_new_privs` or
  holds `CAP_SYS_ADMIN` in its user namespace (`syscalls.c:468/412`). The comment says why: "This
  avoids scenarios where unprivileged tasks can affect the behavior of privileged children"
  (`syscalls.c:438/382`). The refusal protects a set-user-ID child from a policy an unprivileged
  parent chose; it guards the system from the sandbox, not the sandbox from a leak, which is how
  #1007 reads it.
* Deciding: inside what is handled, no granting rule means `EACCES`; a walk that reaches the real
  root denies, and one that ends at a disconnected root denies unless the mount is internal
  (`fs.c:529-543/613-627`). The exception is named: pseudo filesystems, pipes and sockets reached
  through `/proc/<pid>/fd`, are allowed (`is_nouser_or_private`, `fs.c:223/283`; `landlock.rst`,
  "Special filesystems").
* Availability is the application's call, and the documentation recommends best effort: read the
  ABI version and enforce what the kernel supports, its example returning 0 where Landlock is absent
  ("Degrades gracefully", `landlock.rst:98/83`).

`fsnotify` on `master` fails open on every path. Its permission gate takes the callback's return as
the verdict and allows on anything else, "a callback that returns nothing or raises included, so a
rule that fails, or forgets to answer, takes nothing away" (`lib/luafsnotify.c`, module doc;
`luafsnotify_toverdict`), and `luafsnotify_handle` allows when the lock owner comes back through a
marked path and when the runtime is not ready. That fits a gate a watch puts on a path nobody asked
to close.

The eBPF bridge on `master` leaves the choice to the stub: `bpf_luaxdp_run` returns `-1` when no
runtime answers the key, when no callback is attached, and when the callback ends, by a return or a
raise, without setting an action (`lib/luaxdp.c`, `lunatik_ebpf.h`), and `examples/filter/https.c`
turns that into `XDP_PASS`. On an
LSM hook `-1` is `-EPERM`: an `lsm` kfunc that kept the sentinel would turn every failure of the
bridge into a denial, on the auditor's hook as on the sandbox's, without either stub choosing it.

**Recommendation for the maintainer.** The `lsm` kfunc (phase 2) answers "no verdict" with a value no
verdict uses, and the stub decides, as the XDP stub does: the sandbox stub of #671 denies inside its
scope whenever Lua gives no verdict (no runtime for the key, a raise, a callback that returns
nothing), and the auditor stub allows. `testing.md`'s `default.sh`, "a callback that returns nothing
allows", is then the auditor's row, and the sandbox takes its mirror: nothing returned, denied inside
the scope and allowed outside it. The sandbox refuses to start where `bpf` is not in the LSM list,
through `lsm.available()`, rather than degrade: Landlock's best effort is a program choosing to run
unconfined, while an administrator's sandbox that degrades is a policy believed installed that
enforces nothing. #671's README contrasts the two gates in these terms.

## What Landlock cannot express

Its author states the limit as a principle: the policy "is not programmable [...] nor can
communicate with user space (e.g., using eBPF and the related maps)", to shut out side channels, and
because a program per layer would make composition complex and slow (Salaün 2024, section 5.5; the
"Guiding principles" of `Documentation/security/landlock.rst:37/37`). Landlock's second patch series
moved to eBPF, the LSM framework and cgroups, and the series dropped eBPF in 2020 as unfit for
unprivileged users and as programs that stack rather than compose; that work bootstrapped the BPF
LSM this epic rides (section 8.4). The bridge is the privileged branch of that fork.

At `v6.8` a ruleset cannot state:

* a rule that depends on who asks beyond the domain: the pid, the uid, the parent, the cgroup;
* a rule that depends on history or time: a count, a rate, "its configuration once and nothing
  after", the stateful rule #670 is for;
* a rule that loosens: a domain only narrows, so `secmodel_sandbox`'s "on a signal, drop the network
  and grant the filesystem" (#670) keeps only its narrowing half;
* an exception carved out of an allowed hierarchy: rules only allow, so "all of `/usr` but
  `/usr/bin/su`" is not a ruleset;
* the error code a refusal returns (section 5.5);
* anything outside the rights its ABI knows: the filesystem at `v6.6`, and TCP `bind` and `connect`
  besides at `v6.8`;
* a policy put on a running process from outside it: `landlock_restrict_self` acts on the calling
  thread only, so a launcher restricts itself before it executes the program.

**Recommendation for the maintainer.** #671 puts one functional rule beside the allowlist, one that
decides with the task's identity or history in hand, "this file, this process, now", and says it is
the rule no Landlock ruleset can state. The candidate that needs nothing past phase 4 decides on the
task: a binary the allowlist does not name, allowed to the one process Lua recorded, by pid or by
cgroup, and refused to every other. The counting rule of #670 follows once task storage exists, and
an exception inside an allowed directory comes with the walk, where the nearest entry on it decides.

## Logging

Landlock logs nothing at `v6.6` or `v6.8`: `security/landlock/` has no audit code before `v6.15`,
which adds `audit.c`, the `AUDIT_LANDLOCK_ACCESS` and `AUDIT_LANDLOCK_DOMAIN` records and the
`LANDLOCK_RESTRICT_SELF_LOG_*` flags, ABI 7 (`Documentation/admin-guide/LSM/landlock.rst` at
`v6.15`). On most kernels this tree supports, a Landlock denial leaves no record.

The auditor of #671 at an LSM hook is not that record. `call_int_hook` stops at the first module
that refuses (`security/security.c:859/774`), modules run in the order they registered
(`security_add_hooks` appends, `security/security.c:564/527`), and the boot line in
`kernel-notes.md` puts `bpf` last. Landlock also refuses an exec earlier than `bprm_check_security`:
`do_open_execat` opens the file with `__FMODE_EXEC` (`fs/exec.c:916/911`), which `hook_file_open`
checks as `LANDLOCK_ACCESS_FS_EXECUTE` (`get_required_file_open_access`, `fs.c:1103/1187`). A BPF
LSM program sees what every module before it let through, never what one refused.

What sees the chain's answer is a tracing program on the exit of the `security_*` call, `fexit` on
`security_bprm_check` or `security_file_open`. The verifier's deny list for tracing does not name
them (`btf_id_deny`, `kernel/bpf/verifier.c:20608/19530`), and a kfunc registered for
`BPF_PROG_TYPE_LSM` lands in the same `BTF_KFUNC_HOOK_TRACING` set that `BPF_PROG_TYPE_TRACING`
reads (`kernel/bpf/btf.c:7890/7829`), so the `lsm` kfunc would be callable from it. A tracing program
needs no `bpf` in the LSM list. This was read in the source, not run.

**Recommendation for the maintainer.** The exec auditor of #671 observes at the LSM hook what it is
for, the execs that happen, and says that a denial by another module never reaches it. A denial log,
Landlock's included, is an `fexit` stub on the `security_*` call: a separate example, worth
prototyping because it would also run on a kernel booted without `lsm=...,bpf`.

## What each phase takes

| Phase | From this note |
|-------|----------------|
| 2, the bridge | a "no verdict" answer distinct from every errno, which `-1` is not on an LSM hook |
| #669, the fast path | the absent-key default is the stub's; values `ALLOW`, `DENY`, `ASK`; the key is the inode, the path travels to Lua; a way for Lua to turn a path into the key, from the superblock and not from `stat` |
| #670, scoped policy | a cgroup scope is administrator policy, not a ratchet; task storage is not inherited, and inheriting it is a `task_alloc` copy #670 declines |
| #671, examples | the sandbox is scoped, denies on no verdict inside its scope, refuses to start without `bpf`, and states it is not Landlock; the mirror of `default.sh`; one functional rule no ruleset can state; the README contrasts it with `fsnotify`'s gate; the auditor states what it cannot see; a denial log is an `fexit` example |

## Sources

* Linux, upstream tags `v6.8` and `v6.6`: `security/landlock/` (`syscalls.c`, `ruleset.c`,
  `ruleset.h`, `fs.c`, `cred.c`, `ptrace.c`, `limits.h`), `Documentation/userspace-api/landlock.rst`,
  `Documentation/security/landlock.rst`, `fs/exec.c`, `fs/d_path.c`, `kernel/cred.c`, `kernel/fork.c`,
  `kernel/bpf/btf.c`, `kernel/bpf/verifier.c`, `kernel/bpf/bpf_lsm.c`,
  `kernel/bpf/bpf_inode_storage.c`, `kernel/trace/bpf_trace.c`, `include/linux/bpf_lsm.h`,
  `security/security.c`, `fs/btrfs/disk-io.c`, `fs/btrfs/inode.c`, `fs/overlayfs/inode.c`,
  `Documentation/admin-guide/cgroup-v2.rst`; browsable at
  `https://elixir.bootlin.com/linux/<tag>/source/<path>`
* Linux `v6.14` and `v6.15`: `security/landlock/audit.c` (present at `v6.15`, absent at `v6.14`),
  `Documentation/admin-guide/LSM/landlock.rst`, `Documentation/userspace-api/landlock.rst`
  ("Logging (ABI < 7)")
* M. Salaün, [*Landlock: From a security mechanism idea to a widely available
  implementation*](https://landlock.io/talks/2024-06-06_landlock-article.pdf), 2024, sections 5.5,
  7.3 and 8.4
* In this tree: `lib/luafsnotify.c`, `lib/luaxdp.c`, `lunatik_ebpf.h`, `lib/luabpf.c`,
  `examples/filter/https.c`, and `api.md`, `plan.md` and `testing.md` beside this note

