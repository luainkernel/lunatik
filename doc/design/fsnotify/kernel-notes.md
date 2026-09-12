# Kernel notes: fsnotify

Reference sheet for the `fsnotify` binding. Every symbol and signature below was checked against
Linux 6.8 (`/usr/src/linux-headers-6.8.0-124-generic/include`, its `Module.symvers`) and compared
against upstream v6.15. Re-check on the kernel you target: `fs/notify/` has been reworked repeatedly,
and two of the interfaces below changed inside the 6.x series.

## Header map

| Header | What you need from it |
|--------|----------------------|
| `linux/fsnotify_backend.h` | `struct fsnotify_group`, `struct fsnotify_ops`, `struct fsnotify_mark`, the `FS_*` masks, group flags and priorities, the mark API |
| `linux/fsnotify.h` | where the hooks are called from: `fsnotify_open_perm`, `fsnotify_file_perm`, and in 6.14+ `fsnotify_mmap_perm`, `fsnotify_truncate_perm` |
| `linux/namei.h` | `kern_path` |
| `linux/dcache.h`, `linux/path.h` | `d_path`, `struct path`, `path_put` |

`linux/fsnotify_backend.h` is **not** a uapi header, but it ships in `linux-headers-$(uname -r)` and
autogen already reads non-uapi headers (`linux/notifier.h`, `linux/sched.h`), so the `FS_*` constants
can be generated the usual way.

## Exported symbols we rely on

Checked in `Module.symvers` for 6.8.0-124-generic. All `EXPORT_SYMBOL_GPL`, which is fine for
Lunatik: its modules declare `MODULE_LICENSE("Dual MIT/GPL")`.

    fsnotify_alloc_group            GPL   create a group
    fsnotify_put_group              GPL   drop the creation reference (destroys it)
    fsnotify_init_mark              GPL   initialize a mark for a group
    fsnotify_add_mark               GPL   attach a mark to an object
    fsnotify_find_mark              GPL   find this group's mark on an object
    fsnotify_destroy_mark           GPL   detach and free a mark
    fsnotify_put_mark               GPL   drop a mark reference
    fsnotify_wait_marks_destroyed   GPL   flush pending mark destruction
    fsnotify                        GPL   the dispatcher itself (not needed by a consumer)
    __fsnotify_parent               GPL   ditto
    fsnotify_get_cookie              GPL   rename cookie allocation

Path resolution, plain `EXPORT_SYMBOL`:

    kern_path                             path string -> struct path
    path_put                              release it
    d_path                                struct path -> string, needs a caller supplied buffer

**Not exported**: `fsnotify_detach_mark` and `fsnotify_free_mark` individually. Use
`fsnotify_destroy_mark`, which does both. Nor `fsnotify_recalc_mask`, `fsnotify_get_mark`,
`fsnotify_conn_mask` and `fsnotify_clear_marks_by_group`, all of them declared in the same header:
declared is not exported, and the list above is the whole of what a module gets.

## In-tree precedents

A kernel module creating its own group is the normal case, not a trick. Consumers in 6.8:

| Consumer | Ops used | Notes |
|----------|----------|-------|
| `fs/notify/dnotify/dnotify.c` | `handle_inode_event` | the smallest complete example |
| `kernel/audit_watch.c`, `audit_tree.c`, `audit_fsnotify.c` | `handle_inode_event` | `fsnotify_alloc_group(&ops, 0)` at `device_initcall` |
| `fs/nfsd/filecache.c` | `handle_inode_event` | |
| `fs/notify/fanotify/fanotify_user.c` | `handle_event` | the only permission event user, and the only one setting `priority` |

Read `dnotify.c` first: it is about 400 lines and covers group creation, marks, and teardown.

## Semantics that shape the API

### Permission events are synchronous and the return value is the answer

The dispatcher stops at the first group that objects:

    while (fsnotify_iter_select_report_types(&iter_info)) {
            ret = send_to_group(mask, data, data_type, dir, file_name, cookie, &iter_info);
            if (ret && (mask & ALL_FSNOTIFY_PERM_EVENTS))
                    goto out;
            fsnotify_iter_next(&iter_info);
    }

`fs/notify/fsnotify.c`, 6.8. A non zero return from `handle_event` on a permission event is the
denial, and it propagates up through `fsnotify_open_perm` to `security_file_open` and out of the
syscall. Return `-EPERM`; the caller does not sanitize the value.

Consequences for the binding:

* the handler runs **in the context of the process performing the access** — `current` is the actor,
  which is why `event:pid()` is meaningful;
* it **may sleep** (fanotify parks the syscall there waiting for a userspace answer), so a process
  context runtime is correct and a `softirq` runtime is not;
* it **re-enters** if the handler touches a watched path. See the guard in `api.md`.

Where the perm hooks are called from, 6.8:

    security/security.c:3045    security_file_open()  -> fsnotify_open_perm(file)
    fs/readdir.c:99             fsnotify_file_perm(file, MAY_READ)
    include/linux/fsnotify.h    fsnotify_file_area_perm() is the FS_ACCESS_PERM entry point

All of this is behind `CONFIG_FANOTIFY_ACCESS_PERMISSIONS`; without it the inline hooks compile to
`return 0` and no group can deny anything. It is `=y` on Ubuntu's 6.8 kernel.

### `handle_event` versus `handle_inode_event`

`struct fsnotify_ops` offers both:

    int (*handle_event)(struct fsnotify_group *group, u32 mask, const void *data,
                        int data_type, struct inode *dir, const struct qstr *file_name,
                        u32 cookie, struct fsnotify_iter_info *iter_info);
    int (*handle_inode_event)(struct fsnotify_mark *mark, u32 mask, struct inode *inode,
                              struct inode *dir, const struct qstr *file_name, u32 cookie);

`handle_inode_event` is the simplified form the in-tree kernel consumers use. It hands you the mark,
the inode and the name, and the core does the iteration bookkeeping
(`fsnotify_handle_inode_event`, `fs/notify/fsnotify.c:260`). It does **not** give you the
`struct path`, and it is reached only for marks the core selected as inode-ish.

The proposal starts on `handle_inode_event` for phases 1 to 3 and moves to `handle_event` for phase 4
if the permission path needs the `path` or the iterator. Prototype before deciding: the two are not
mutually exclusive across phases, but shipping both ops on the same group is not a design, it is an
accident.

### Data types: what the event actually carries

    enum fsnotify_data_type {
            FSNOTIFY_EVENT_NONE,
            FSNOTIFY_EVENT_PATH,     /* struct path *  — has mnt and dentry */
            FSNOTIFY_EVENT_INODE,    /* struct inode * */
            FSNOTIFY_EVENT_DENTRY,   /* struct dentry * */
            FSNOTIFY_EVENT_ERROR,    /* struct fs_error_report * */
    };

Accessors are inlines in the same header: `fsnotify_data_inode`, `fsnotify_data_path`,
`fsnotify_data_dentry`, `fsnotify_data_sb`. `fsnotify_data_path` returns `NULL` for anything but
`FSNOTIFY_EVENT_PATH`, which is why `event:path()` returns `nil` rather than raising.

### What `d_path` renders

`d_path` resolves against the accessing task's own root, `get_fs_root_rcu(current->fs, &root)`
(`fs/d_path.c:286` at v6.12, `:287` at v5.15), and delivery is synchronous, so `current` is the task
performing the access: a chrooted or containerised accessor gets the path as it sees it, not as the
script's own namespace would spell it. An unlinked file carries a trailing ` (deleted)` inside the
same string (`:288` and `:289`), which the function's own kernel-doc calls ambiguous.

### Group flags and priority

    #define FSNOTIFY_GROUP_USER  0x01  /* user allocated group: accounted allocation */
    #define FSNOTIFY_GROUP_DUPS  0x02  /* allow multiple marks per object */
    #define FSNOTIFY_GROUP_NOFS  0x04  /* group lock is not direct reclaim safe */

A kernel group passes `0`, as audit does. `FSNOTIFY_GROUP_USER` is for groups backed by a userspace
fd and changes the allocation accounting; it is not what this binding is.

Priority lives in the group as `group->priority`, but **the constants were renamed inside 6.x** and the
6.8 names are not the ones the current documentation uses. On 6.8 they are plain defines written inside
the struct body, and the field is an `unsigned int`:

    /* include/linux/fsnotify_backend.h:208, Linux 6.8 */
    #define FS_PRIO_0	0 /* normal notifiers, no permissions */
    #define FS_PRIO_1	1 /* fanotify content based access control */
    #define FS_PRIO_2	2 /* fanotify pre-content access */
    unsigned int priority;

From 6.10 the same three values are an enum and the field carries its type:

    enum fsnotify_group_prio {
            FSNOTIFY_PRIO_NORMAL = 0,       /* normal notifiers, no permissions */
            FSNOTIFY_PRIO_CONTENT,          /* fanotify permission events */
            FSNOTIFY_PRIO_PRE_CONTENT,      /* fanotify pre-content events */
            __FSNOTIFY_PRIO_NUM
    };
    enum fsnotify_group_prio priority;

Write the assignment under a version guard, or define a local alias; do not use `FSNOTIFY_PRIO_CONTENT`
before 6.10, where it does not exist.

fanotify sets the value from the `FAN_CLASS_*` the user asked for. On 6.8 the dispatcher does not gate
permission delivery on it, but on 6.14+ the open path consults
`fsnotify_sb_has_priority_watchers(sb, FSNOTIFY_PRIO_CONTENT)` and marks the file
`FMODE_NONOTIFY_PERM` when no such watcher exists — a group that wants permission events on those
kernels must set the content priority before its marks are added, or its handler will simply never be
called. Set it explicitly on every kernel; it costs nothing on 6.8 and is required later.

### Marks

    void fsnotify_init_mark(struct fsnotify_mark *mark, struct fsnotify_group *group);
    int  fsnotify_add_mark(struct fsnotify_mark *mark, <object>, unsigned int obj_type,
                           int add_flags);
    void fsnotify_destroy_mark(struct fsnotify_mark *mark, struct fsnotify_group *group);

`obj_type` is `FSNOTIFY_OBJ_TYPE_INODE`, `_VFSMOUNT` or `_SB`, which is how the same call marks a
file, a mount or a whole filesystem. Convenience inline: `fsnotify_add_inode_mark`.

The mark's mask is set on the mark (`mark->mask`) before adding.

### Changing a live mark's mask

`fsnotify_recalc_mask` is not exported, so a module cannot recalculate the object's aggregate mask
after writing `mark->mask` — and that aggregate, which `fsnotify()` tests before any group is reached,
is what decides whether an event is dispatched at all. Writing `mark->mask` alone therefore only
narrows what a mark reports; a bit added that way never arrives.

`fsnotify_add_mark` ends in `fsnotify_recalc_mask(mark->connector)` (`fs/notify/mark.c`, 6.12), so the
exported route to a new mask is to destroy the mark and add it again. The destroy has to come first:
`fsnotify_add_mark_list` refuses a second mark of the same group on the same object with `-EEXIST`
unless the group carries `FSNOTIFY_GROUP_DUPS`.

### The ignore mask

`send_to_group` clears `mark->ignore_mask` on every `FS_MODIFY` unless the mark carries
`FSNOTIFY_MARK_FLAG_IGNORED_SURV_MODIFY` (`fs/notify/fsnotify.c`, 6.12). That is fanotify's "ignore
until the file changes", which an ignore mask a script asked for is not, so set the flag on the mark
before adding it. Leaving `FSNOTIFY_MARK_FLAG_HAS_IGNORE_FLAGS` clear keeps the legacy reading, where
the ignore mask names event types and the flags in it are the mark's own — which is what
`mark:ignore(mask)` means. No recalculation is needed for it: an ignore mask only ever suppresses.

### What umount does to a mark

`fsnotify_sb_delete` sends `FS_UNMOUNT` to every watched inode of the superblock and detaches the marks
on them and on the superblock itself; `__fsnotify_vfsmount_delete`, from `mntput`, does the same for a
mount. Detaching drops only the reference `fsnotify_add_mark` took, so a mark whose module still holds
the reference `fsnotify_init_mark` left stays allocated and merely becomes detached: a later
`fsnotify_destroy_mark` on it returns without doing anything, and the module's own `fsnotify_put_mark`
frees it. Marks do not pin the mount, and umount does not wait for them.

### Version drift, verified

Read from the `include/linux/fsnotify_backend.h` of each release named. Inside the range this tree
supports, 5.15 and later:

| Change | before | from |
|--------|--------|------|
| `fsnotify_alloc_group` | `(ops)` | `(ops, flags)`, 5.19 |
| The mark's ignore mask | `mark->ignored_mask` | `mark->ignore_mask`, 6.0 |
| `fsnotify_add_mark` | `(mark, connp, obj_type, add_flags, fsid)` | `(mark, connp, obj_type, add_flags)`, 6.8 |
| `fsnotify_add_mark` second parameter | `fsnotify_connp_t *connp` | `void *obj`, the object itself, 6.10 |
| `fsnotify_find_mark` | `(connp, group)` | `(obj, obj_type, group)`, 6.10 |

`fsnotify_add_inode_mark(mark, inode, add_flags)` is an inline with the same signature across the whole
range, so a binding that only marks inodes sees none of the last three.

Before 6.10 a mount's connector is `&real_mount(mnt)->mnt_fsnotify_marks`, and `real_mount` is in
`fs/mount.h`, which is not installed for modules. An inode's (`&inode->i_fsnotify_marks`) and a
superblock's (`&sb->s_fsnotify_marks`) are public, so on those kernels a module can mark an inode and a
filesystem but not a mount; `luafsnotify` drops `"mount"` from the kinds it accepts there rather than
offering one that cannot work.

The rest lands above 6.9 and matters only when targeting those kernels:

| Change | 6.8 | from |
|--------|-----|------|
| Group priority constants | `FS_PRIO_0/1/2`, defines inside the struct; field is `unsigned int` | `enum fsnotify_group_prio` (`FSNOTIFY_PRIO_NORMAL/CONTENT/PRE_CONTENT`), 6.10 |
| Permission hooks | `fsnotify_open_perm`, `fsnotify_file_perm` | adds `fsnotify_mmap_perm`, `fsnotify_truncate_perm`; `fsnotify_file_area_perm` also tests `MAY_WRITE`/`MAY_ACCESS` |
| Priority gating on the open path | none | `fsnotify_sb_has_priority_watchers` + `FMODE_NONOTIFY_PERM` |
| Pre-content events | absent | `FSNOTIFY_PRIO_PRE_CONTENT`, HSM oriented |

Follow the `LINUX_VERSION_CODE` guard style already used in `lib/luaxdp.c`. Do not paper over the
`fsnotify_add_mark` difference with a cast; write the two calls under a version guard.

## Event masks

From `linux/fsnotify_backend.h`. These are bit masks, not a dense enum, which matters for the autogen
spec.

    FS_ACCESS  FS_MODIFY  FS_ATTRIB  FS_CLOSE_WRITE  FS_CLOSE_NOWRITE  FS_OPEN
    FS_MOVED_FROM  FS_MOVED_TO  FS_CREATE  FS_DELETE  FS_DELETE_SELF  FS_MOVE_SELF
    FS_OPEN_EXEC  FS_UNMOUNT  FS_Q_OVERFLOW  FS_ERROR
    FS_OPEN_PERM  FS_ACCESS_PERM  FS_OPEN_EXEC_PERM
    FS_EVENT_ON_CHILD  FS_RENAME  FS_ISDIR

`ALL_FSNOTIFY_PERM_EVENTS` is the mask of the three `*_PERM` bits. It and they are unconditional
defines: the config gates the hooks in `include/linux/fsnotify.h`, not the constants. So the presence
of `FS_OPEN_PERM` says nothing about whether a deny can be enforced, and a binding that needs to know
tests the config in C rather than the constant.

### What a `FS_` prefix actually matches

The header defines 27 names starting with `FS_`, and three more (`FS_PRIO_0/1/2`) indented inside the
group struct, which `cpp -dD` emits at column zero like any other define. A spec that just says
`prefix = "FS_"` takes all of them. What each group needs:

* **the event masks** are what the binding wants: `FS_ACCESS`, `FS_MODIFY`, `FS_ATTRIB`,
  `FS_CLOSE_WRITE`, `FS_CLOSE_NOWRITE`, `FS_OPEN`, `FS_MOVED_FROM`, `FS_MOVED_TO`, `FS_CREATE`,
  `FS_DELETE`, `FS_DELETE_SELF`, `FS_MOVE_SELF`, `FS_OPEN_EXEC`, `FS_UNMOUNT`, `FS_Q_OVERFLOW`,
  `FS_ERROR`, `FS_RENAME`, plus the flags `FS_EVENT_ON_CHILD` and `FS_ISDIR`, and the three
  `*_PERM` bits;
* **`FS_PRIO_0/1/2`** are group priorities, not event bits. They must not appear in a table of event
  masks;
* **`FS_IN_IGNORED`** is inotify's internal overload of the `FS_ERROR` bit and **`FS_DN_MULTISHOT`** is
  dnotify's. Neither is meaningful to this binding;
* the composites (`FS_MOVE`, `FS_EVENTS_POSS_ON_CHILD`, `FS_EVENTS_POSS_TO_PARENT`, the
  `ALL_FSNOTIFY_*` masks) drop out on their own: their values are expressions, and `autogen.lua` keeps
  only defines whose value is an integer expression.

So no change to `autogen.lua` is needed for the values themselves; the mask constants are plain hex
literals and resolve like any other. What is needed is an `include` list, the way `nf.action` does it.

`FS_EVENT_ON_CHILD` is what makes a mark on a directory report events on the files inside it; without
it a directory mark reports only events on the directory itself.

## Config dependencies

| Config | Needed for | On Ubuntu 6.8 |
|--------|-----------|---------------|
| `CONFIG_FSNOTIFY` | everything | `y` (implied by `CONFIG_INOTIFY_USER`) |
| `CONFIG_FANOTIFY` | — (uapi only, not needed by a kernel group) | `y` |
| `CONFIG_FANOTIFY_ACCESS_PERMISSIONS` | permission events | `y` |

The permission hooks are compiled out without the third; guard the whole phase 4 surface on it and
skip the tests rather than failing them.

## Sources

* `fs/notify/fsnotify.c`, `fs/notify/group.c`, `fs/notify/mark.c`, `fs/notify/dnotify/dnotify.c`,
  `kernel/audit_watch.c` (Linux 6.8)
* `include/linux/fsnotify_backend.h`, `include/linux/fsnotify.h` (6.8 and v6.15)
* `Module.symvers` from `linux-headers-6.8.0-124-generic`

