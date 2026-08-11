# Proposed Lua API: `fsnotify`

This is a design proposal, not a specification. Names and shapes are open for review; the constraints
behind them (in `kernel-notes.md`) are not. Anything here that turns out to conflict with a kernel
constraint loses.

One new kernel module, `fsnotify` (`lib/luafsnotify.c`), owning two object classes:

* `watch` — an `fsnotify_group` with its ops and its Lua callback;
* `fsnotify.event` — the object handed to the callback, reset per event and cleared on return,
  following the registry pattern `lib/luanetfilter.c` uses for its `skb`.

## Conventions

* Event masks are integers from `linux.fs`, combined with `|`: `fs.OPEN | fs.MODIFY`.
* Object kind selectors are strings, as `skb:data("mac")` already does: `"inode"`, `"mount"`, `"sb"`.
* Paths are strings, resolved in the kernel with `kern_path`.
* A missing optional kernel feature means a missing method, not a runtime error.
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
| `watch:stop()` | | disarms the callback; the group is torn down on release |

    local mark = watch:mark("/tmp/scratch", fs.OPEN | fs.MODIFY | fs.CREATE | fs.DELETE)
    watch:mark("/tmp/scratch", fs.OPEN_PERM, "mount")

`watch:stop()` follows the soft-stop convention the repository already uses, and `lib/luanotifier.c`
is the model to copy: `stop` only clears the registered callback, so the handler becomes a silent
no-op, and the teardown that can sleep happens in `release`, which always runs in process context
(`lua_close` → GC → `release`).

That split matters here rather than being a formality: `fsnotify_wait_marks_destroyed()` is a flush and
sleeps. Destroying the group from `stop` would put a sleeping call wherever a script chose to call it.

### Class shape

Process context, so no `LUNATIK_OPT_SOFTIRQ`. `LUNATIK_OPT_SINGLE`, matching
`luanotifier_process_class`, which is the closest analogue in the base. Errors follow the base
convention, negative errno raised through `lunatik_throw`/`pusherrname`.

## The `mark` object

| Method | Returns | Notes |
|--------|---------|-------|
| `mark:mask([mask])` | integer | reads, or sets and recalculates |
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
a handler that only matches on the name never pays for it.

## Permission events

    local function guard(mask, event)
        if mask & fs.OPEN_EXEC_PERM ~= 0 and not allowed[event:name()] then
            return fsnotify.action.DENY
        end
        return fsnotify.action.ALLOW
    end

    local watch = fsnotify.watch(guard)
    watch:mark("/tmp/scratch", fs.OPEN_PERM | fs.OPEN_EXEC_PERM, "mount")

`fsnotify.action.ALLOW` is 0 and `fsnotify.action.DENY` is `-EPERM`, which is what the kernel expects
back from `handle_event`. They are named constants in the module rather than raw numbers because
returning a bare `-1` from a handler by accident is a denial, and because a boolean would invert
badly: `nil` (a handler that forgot to return) must mean allow.

Denial surfaces to the process as `EPERM` on the syscall.

Requires `CONFIG_FANOTIFY_ACCESS_PERMISSIONS`. Without it the `*_PERM` constants are absent from
`linux.fs` and marking with them raises.

## Reentrancy

A handler runs inside the syscall of the process being watched. If it opens a watched file — directly,
or indirectly through `require`, a `print` to a watched log, or a Lunatik script under a marked
mount — it re-enters, and with the runtime already locked by the outer call that is a deadlock rather
than a wrong answer.

The proposal is a guard by task identity in the group's private data:

    if (group_priv->handler == current)
            return 0;               /* allow, and do not recurse */
    group_priv->handler = current;
    ret = lunatik_run(...);
    group_priv->handler = NULL;

Task identity, not a per-CPU flag: the handler may sleep, so the guard has to survive a reschedule.
The stored task is written and read only by the task itself in the nesting case, so no additional
lock is needed, but this is exactly the kind of claim that gets a prototype and a test rather than a
paragraph — phase 1 owns proving it.

The base already has a mechanism for the adjacent problem, and the prototype should be compared
against it before settling. `luanotifier_call` detects that its callback is firing while the runtime
lock is already held and calls `lunatik_handle` (no lock) instead of `lunatik_run` (takes it):

    bool islocked = !notifier->unregister; /* still inside register_fn? */
    if (islocked) lunatik_handle(...); else lunatik_run(...);

Reusing the held lock would let the nested handler actually run rather than being skipped. The reason
to skip anyway is that nesting here is unbounded — the nested handler can open a watched file too —
so the recursion has no floor. Say that in the code, because the alternative is one line away and the
next reader will wonder.

**Serialization.** A process context runtime locks a mutex around the callback, so every watched access
on the machine passes through one lock. A slow handler does not only slow the process that triggered
it, it serializes all watched accesses. That is the mechanism behind "a slow handler is a slow system",
and it is what phase 4 should measure.

Two conventions on top of the guard, for the examples and the documentation:

* never mark `/`, `/lib/modules/lua`, or the directory holding the script;
* prefer a mount or inode mark on a scratch subtree to a superblock mark on the root filesystem.

## Worked example: integrity monitor

    local fsnotify = require("fsnotify")
    local fs       = require("linux.fs")

    local WATCHED <const> = "/etc"

    local function audit(mask, event)
        if mask & (fs.MODIFY | fs.ATTRIB) ~= 0 then
            print(string.format("changed: %s (ino %d, pid %d)",
                event:name() or "?", event:ino() or 0, event:pid()))
        end
    end

    local watch = fsnotify.watch(audit)
    watch:mark(WATCHED, fs.MODIFY | fs.ATTRIB | fs.CREATE | fs.DELETE, "mount")

## Worked example: exec allowlist

    local fsnotify = require("fsnotify")
    local fs       = require("linux.fs")
    local set      = require("set")

    local SCRATCH <const> = "/tmp/scratch"
    local allowed  = set.new{"hello", "true"}

    local function guard(mask, event)
        local name = event:name()
        if name and not allowed:has(name) then
            return fsnotify.action.DENY
        end
        return fsnotify.action.ALLOW
    end

    local watch = fsnotify.watch(guard)
    watch:mark(SCRATCH, fs.OPEN_EXEC_PERM, "mount")

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

## Open questions for review

1. Whether `event:pid()` should return a `task` object once `luatask` lands from the eBPF work,
   rather than a bare integer.
2. Whether `event:path()` should cache the resolved string for the duration of the event, since a
   handler that tests it and then logs it pays `d_path` twice.

