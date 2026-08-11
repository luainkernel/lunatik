# Testing the fsnotify binding

Lunatik's tests are shell scripts emitting KTAP, driving a kernel Lua script and asserting on what it
prints to `dmesg` or on what userspace observes. `tests/notifier/` is the closest existing model:
a callback fires from a kernel event, and the test triggers that event from the shell. Read it,
plus `tests/lib.sh` (`run_test`, `mark_dmesg`, `dmesg_since`, `check_dmesg`, `ktap_skip`), before
writing anything new.

Run everything with `sudo lunatik test`, one suite with `sudo lunatik test fsnotify`.

## What this suite needs that others do not

**A scratch subtree, created and destroyed per test.** Every mark in every test goes on a directory
under `/tmp` created by the test itself. No test marks `/`, `/etc`, `/lib/modules/lua`, or the
directory the script was loaded from. This is not tidiness: a permission test that denies the wrong
open can make the machine unable to read its own scripts, and the cleanup path then cannot run
either.

The shape, in the `trap` convention the existing suites already use:

    SCRATCH=$(mktemp -d /tmp/lunatik-fsnotify.XXXXXX)
    cleanup() { lunatik stop "$SCRIPT" 2>/dev/null; rm -rf "$SCRATCH"; }
    trap cleanup EXIT
    cleanup_stale                      # run once up front, as the other suites do

**An escape hatch for the enforcement tests.** A permission test installs a rule that denies, then
proves the denial. If the script cannot be stopped afterwards, the machine keeps the rule. Every
permission test therefore:

* marks only the scratch subtree, so nothing outside it can be denied;
* stops the script in the `trap`, not at the end of the happy path;
* is written so that the deny rule matches a name that exists only in the scratch subtree.

**A way to assert a denial.** Userspace side, not `dmesg`: run the access and check the error.

    if cat "$SCRATCH/secret" 2>&1 | grep -q "Operation not permitted"; then ...

`EPERM` is what a non zero return from the handler produces. Assert on both the failure of the
command and the specific error, so that a test does not pass because the file was missing.

## Test matrix

Fill this in as the phases land. Each row is one `.sh` plus one `.lua`, following the convention that
the description of the test lives in the shell script and the Lua file carries a single line pointing
back at it.

Coverage here means event × object kind × outcome, including the successes, not a list of features.

### Phase 1 and 2: notification

| Test | Proves |
|------|--------|
| `open.sh` | an inode mark reports `FS_OPEN` for that file and not for its neighbour |
| `modify.sh` | `FS_MODIFY` and `FS_CLOSE_WRITE` arrive in order for a write |
| `dirent.sh` | a directory mark with `FS_EVENT_ON_CHILD` reports `FS_CREATE`, `FS_DELETE`, `FS_MOVED_FROM`/`FS_MOVED_TO`, and the event carries the child's name |
| `identity.sh` | `event:name()`, `event:ino()`, `event:dir()`, `event:isdir()` and `event:pid()` match what the shell knows (`stat -c %i`, `$$`) |
| `nomask.sh` | an event outside the mark's mask does not reach the handler |
| `reentrancy.sh` | a handler that itself opens a watched file returns instead of deadlocking; the machine survives and the suite continues |

`reentrancy.sh` is the one that justifies the guard. Write it in phase 1, before the permission work
exists: it is cheap while the worst case is a missed notification, and expensive once the worst case
is a locked filesystem.

Where a test needs to count handler invocations, use one shape across the suite: the handler
increments a counter in an `rcu.table` and the shell asserts on the delta across the run, never on the
absolute value, so a previous run cannot make a test pass.

    local shared = rcu.table()
    shared.calls = (shared.calls or 0) + 1

### Phase 3: marks

| Test | Proves |
|------|--------|
| `mount.sh` | a mount mark reports events for files under it (bind mount a scratch dir to keep the blast radius small) |
| `sb.sh` | a superblock mark reports events on a scratch filesystem (loop mounted tmpfs), and skips if it cannot create one |
| `remask.sh` | `mark:mask(new)` changes what arrives, both adding and removing an event |
| `ignore.sh` | `mark:ignore()` suppresses the named events and nothing else |
| `find.sh` | `watch:find(path)` returns the mark that was installed and `nil` for a path with none |
| `remove.sh` | after `mark:remove()` no further events arrive, and `watch:stop()` on a watch with live marks leaks nothing (`fsnotify_wait_marks_destroyed` plus a second run of the same test) |
| `lifetime.sh` | dropping the last Lua reference to a watch and forcing a collection does not oops and does not keep delivering |

### Phase 4: permission

Every test here skips without `CONFIG_FANOTIFY_ACCESS_PERMISSIONS`, checked once in the suite's
`run.sh` and reported with `ktap_skip` per planned test so the plan count stays honest.

| Test | Proves |
|------|--------|
| `allow.sh` | a handler returning `ALLOW` lets the open through — the success case, which is the one a broken verdict path breaks silently |
| `deny.sh` | a handler returning `DENY` makes `cat` fail with `EPERM`, and the neighbouring file still opens |
| `default.sh` | a handler that returns nothing allows, rather than denying |
| `exec.sh` | `FS_OPEN_EXEC_PERM` denies an exec of a scratch binary while an ordinary read of the same file still succeeds |
| `access.sh` | `FS_ACCESS_PERM` gates a read after the open |
| `error.sh` | a handler that raises does not leave the access half decided; the documented behaviour (allow, with the error logged) is what happens |
| `sleep.sh` | a handler that calls `linux.schedule` completes and the syscall returns afterwards, proving the process context claim |

`default.sh` and `allow.sh` exist because the dangerous failure mode of this feature is a verdict path
that denies everything: a test suite that only asserts denials passes on a module that never allows.

### Phase 5: examples

| Test | Proves |
|------|--------|
| `example_monitor.sh` | the integrity monitor example loads, reports a write under the scratch tree, and stops cleanly |
| `example_allowlist.sh` | the exec allowlist example denies a name outside the list and permits one inside it |

## Conventions to follow

* skip, do not fail, when the kernel lacks a config;
* mark `dmesg` before the run, read only what came after, and `check_dmesg` at the end;
* clean up in a `trap`, and run the cleanup once up front as well;
* `lunatik run` exits 0 even when the script fails to load — assert on output, never on exit status;
* one `.sh` per row above, wired into `tests/fsnotify/run.sh` and described in `tests/README.md` in
  the same commit as the code it tests.

## Manual verification before calling a phase done

The suite runs on one kernel. The version drift table in `kernel-notes.md` covers three interfaces
that changed inside 6.x, so phase 4 is not done until permission events have been seen working on
both a 6.8 kernel and a 6.14 or newer one — the priority gating means a wrong `group->priority` shows
up as "no events at all" on the newer kernel and as "works fine" on the older one.

