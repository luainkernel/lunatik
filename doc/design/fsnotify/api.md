# The Lua API: `fsnotify`

This began as a proposal and records what was built. The reference for each method is the LDoc
generated from `lib/luafsnotify.c`; what this document carries is the shape and the reasons behind
it, and the kernel constraints that drove them are in `kernel-notes.md`. Where it and the code
disagree, the code is right.

One kernel module, `fsnotify` (`lib/luafsnotify.c`), owning three object classes:

* `fsnotify` — the watch: an `fsnotify_group` with its ops and its Lua callback;
* `fsnotify.mark` — the handle on one mark, which the kernel keys by the object it sits on;
* `fsnotify.event` — the object handed to the callback, reset per event and cleared on return,
  following the registry pattern `lib/luanetfilter.c` uses for its `skb`.

## Conventions

* Event masks are integers from `linux.fs`, combined with `|`: `fs.OPEN | fs.MODIFY`.
* Object kind selectors are strings, as `skb:data("mac")` already does: `"inode"`, `"mount"`, `"sb"`.
* Paths are strings, resolved in the kernel with `kern_path`.
* A kernel that cannot do what an argument asks for refuses that argument and names why — `"mount"`
  before 6.10, a permission event without `CONFIG_FANOTIFY_ACCESS_PERMISSIONS` — rather than dropping
  the method: the method is there on every kernel, and the script gets something to branch on.
* The whole module is process context only. Marking sleeps, and so does the handler.

## Creating a watch

    local fsnotify = require("fsnotify")
    local fs       = require("linux.fs")

    local function handler(mask, event)
        print(event:name(), event:ino())
    end

    local watch = fsnotify.watch(handler)

`fsnotify.watch(callback)` allocates the group and returns the watch object. Nothing is delivered
until a mark exists.

The callback is invoked as `callback(mask, event)`:

* `mask` — the event mask that fired, testable against `linux.fs` bits;
* `event` — the event object, valid only for the duration of the call.

For notification events the return value is ignored. For permission events it is the verdict; see
below.

`mask` comes first, matching `notifier`'s `callback(event, ...)` shape literally: `luanotifier_handler`
pushes the event integer, then whatever extras the chain supplies. It is a plain integer rather than a
method on the event because every handler starts by testing it, and the event does **not** also carry
it: one spelling, not two.

## The `watch` object

| Method | Returns | Notes |
|--------|---------|-------|
| `watch:mark(path, mask[, kind])` | `mark` | `kind` defaults to `"inode"`; `"mount"` and `"sb"` mark the containing mount or superblock |
| `watch:find(path[, kind])` | `mark` or `nil` | `fsnotify_find_mark`; what this watch already installed |
| `watch:stop()` | | removes every mark and drops the group; a second call does nothing |

    local mark = watch:mark("/tmp/scratch", fs.OPEN | fs.MODIFY | fs.CREATE | fs.DELETE)
    watch:mark("/tmp/scratch", fs.OPEN_PERM, "mount")

`watch:stop()` tears down: it removes every mark the watch placed, drops the callback out of the
registry and puts the group. A watch never stopped is torn down the same way from `release`.

What `stop` does not do is wait. `fsnotify_wait_marks_destroyed()` is a flush, and a mark can still be
inside an event under fsnotify's SRCU — an event blocked on the runtime lock that `stop` is itself
holding, so waiting there deadlocks. The group outlives the call instead, and `free_group_priv` frees
the watch from fsnotify's own reaper once the last mark is gone. The flush belongs to module exit,
where nothing holds the lock.

### Class shape

Process context, so no `LUNATIK_OPT_SOFTIRQ`: `fsnotify.watch` raises from an interrupt-context
runtime, and from a percpu one. All three classes carry `LUNATIK_OPT_SINGLE | LUNATIK_OPT_EXTERNAL`
— private and non-shareable, with `object->private` set by the module rather than allocated with the
object, since the group owns the watch and the watch owns its marks. Errors follow the base
convention, negative errno raised through `lunatik_throw`/`pusherrname`.

## The `mark` object

| Method | Returns | Notes |
|--------|---------|-------|
| `mark:mask([mask])` | integer | reads, or removes the mark and adds it again, the only thing that recalculates the object's mask |
| `mark:ignore([mask])` | integer | the ignore mask, for events this mark should not report |
| `mark:remove()` | | `fsnotify_destroy_mark` |

Marks are separate objects rather than a table keyed by path inside the watch, because the kernel
already keys them (`fsnotify_find_mark` on the object's connector) and duplicating that mapping in C
would be a second source of truth. `watch:find` exists so a script does not have to keep its own.

## The `event` object

| Method | Returns | Notes |
|--------|---------|-------|
| `event:name()` | string or `nil` | dirent name, when the event carries one |
| `event:ino()` | integer or `nil` | inode number of the object the event is about |
| `event:dir()` | integer or `nil` | inode number of the parent directory, for dirent events |
| `event:isdir()` | boolean | `FS_ISDIR` |
| `event:pid()` | integer | the process performing the access — `current`, valid because delivery is synchronous |
| `event:path()` | string or `nil` | only when the kernel handed the group a `struct path` |

What is available depends on which data type the kernel attached to the event (`PATH`, `INODE`,
`DENTRY`, `ERROR`); `kernel-notes.md` has the table. Methods return `nil` rather than raising when the
event does not carry the field, so a handler can be written once for several masks.

`event:path()` is the expensive one: it needs `d_path` and a page sized buffer. It stays a method, so
a handler that only matches on the name never pays for it. What it renders is the accessing task's own
view of the path, `" (deleted)"` and all; `kernel-notes.md` has the citations.

## Permission events

    local function guard(mask, event)
        if mask & fs.OPEN_EXEC_PERM ~= 0 and not allowed:has(event:name()) then
            return fsnotify.action.DENY
        end
        return fsnotify.action.ALLOW
    end

    local watch = fsnotify.watch(guard)
    watch:mark("/tmp/scratch", fs.OPEN_PERM | fs.OPEN_EXEC_PERM | fs.EVENT_ON_CHILD)

`fsnotify.action.ALLOW` is 0 and `fsnotify.action.DENY` is `-EPERM`, which is what the kernel expects
back from `handle_event`. They are named constants in the module rather than raw numbers because
returning a bare `-1` from a handler by accident is a denial, and because a boolean would invert
badly: `nil` (a handler that forgot to return) must mean allow.

Denial surfaces to the process as `EPERM` on the syscall. A handler that wants another error answers
that negative errno and the syscall fails with it; anything the kernel would not read as an errno,
including a handler that returns nothing or raises, allows.

Requires `CONFIG_FANOTIFY_ACCESS_PERMISSIONS`. The `*_PERM` constants are present either way, since
the config gates the permission hooks and not the defines, so their presence cannot be the test: the
module decides in C, and marking for a permission event on a kernel built without them has to refuse
rather than register a mark nothing will ever reach.

## Reentrancy

A handler runs inside the syscall of the process being watched. If it opens a watched file — directly,
or indirectly through `require`, a `print` to a watched log, or a Lunatik script under a marked
mount — it re-enters, and with the runtime already locked by the outer call that is a deadlock rather
than a wrong answer.

The guard is the runtime's own owner check, read in the dispatcher before anything runs:

    if (lunatik_isowner(watch->runtime))
            return LUAFSNOTIFY_ALLOW;   /* allow, and do not recurse */

Task identity, and none of it the module's own state: the core records the task that holds the
runtime lock when it takes it, so the check covers every way that task can already hold it — this
callback opening a path it marks, a `thread` body, a `device` file operation, another module's
callback in the same runtime. A `handler == current` field in the group's private data, which is what
this document first proposed, would have caught only the first of those.

The base has a mechanism for the adjacent problem, and it is the one not taken. `luanotifier_call`
detects that its callback is firing while the runtime lock is already held and calls `lunatik_handle`
(no lock) instead of `lunatik_run` (takes it):

    bool islocked = !notifier->unregister; /* still inside register_fn? */
    if (islocked) lunatik_handle(...); else lunatik_run(...);

Reusing the held lock would let the nested handler actually run rather than being skipped. The reason
to skip anyway is that nesting here is unbounded — the nested handler can open a watched file too —
so the recursion has no floor. The code says so at the check, because the alternative is one line
away and the next reader will wonder.

**Serialization.** A process context runtime locks a mutex around the callback, so every watched access
on the machine passes through one lock. A slow handler does not only slow the process that triggered
it, it serializes all watched accesses. That is the mechanism behind "a slow handler is a slow system".
Nothing in the epic measured it: it is documented on the module as a contract, and the number is
still owed.

Two conventions on top of the guard, for the examples and the documentation:

* never mark `/`, `/lib/modules/lua`, or the directory holding the script;
* prefer a mount or inode mark on a scratch subtree to a superblock mark on the root filesystem.

## Worked examples

Both of them ship, one per regime, and the README says how to run each:

* [`examples/fsmonitor.lua`](../../../examples/fsmonitor.lua), notification: an inode mark on one
  directory with `EVENT_ON_CHILD`, and one log line per event naming the entry, its inode and the pid
  that caused it.
* [`examples/execguard.lua`](../../../examples/execguard.lua), permission: `FS_OPEN_EXEC_PERM` on the
  same shape of mark, answering `DENY` for an entry a `set` does not name.

Each marks one directory and nothing wider, and that is the whole of what confines it: an inode mark
reports, and refuses, for the entries of that one directory, where a `"mount"` or `"sb"` mark reaches
every file of a mount or of a whole filesystem. A monitor over `/etc` reads well in a sketch and
marks the root filesystem's mount in practice.

The matching is Lua's, using `set`; the module supplies the event and takes the verdict. That split is
the point of the binding.

## Settled by precedent

Three questions that looked open have answers already in the base, so they are recorded here rather
than left for review:

* **`fsnotify.watch(callback)`, not `fsnotify.new`.** Constructors that register are named for what
  they do or for what they attach to: `netfilter.register`, `xdp.attach`, `notifier.netdevice`. `new`
  is for plain construction: `socket.new`, `rcu.table`.
* **`mask` is the argument, and the event does not also carry it.** One spelling. See above.
* **One callback per watch.** `notifier` is one callback per object; if you need two behaviours, make
  two watches. The kernel would allow one per mark, but that puts a dispatch in C that Lua does better.

## Decided while building

Two questions this document left open for review, and what the code answered.

1. **`event:pid()` is a bare integer, not a `task` object.** Everything the event exposes dies with
   the dispatcher's frame: the object is reset per event and cleared when the callback returns, so a
   handle that outlived the call would be the one thing a script could keep past it, which is exactly
   what clearing the event is there to prevent. The number is `task_pid_nr(current)`, the same one
   `task:pid()` reports, so a script that wants the object looks it up while the callback runs.
2. **`event:path()` does not cache.** A handler that tests the path and then logs it pays `d_path`
   twice; one that matches on `name` pays nothing, and that is the common shape — both examples take
   it. A cache would be one more field to clear on the path whose one job is clearing what a kept
   event must not read, and it would have to be cleared per event, since the object is reused for
   every event of the watch.

