# Lunatik Tests

Integration tests for lunatik kernel modules. Output follows
[KTAP](https://docs.kernel.org/dev-tools/ktap.html) format.

## Requirements

- Lunatik installed: `sudo make install`
- Root privileges

## Running

All suites (reloads the modules before and unloads after):

```
sudo lunatik test
```

Individual suite:

```
sudo lunatik test <suite>          # e.g. runtime, socket, thread, ...
```

Or invoke the harness directly (no reload):

```
sudo bash tests/run.sh
sudo bash tests/runtime/run.sh
sudo bash tests/runtime/refcnt_leak.sh
```

## Suites

### bpf

Tests for the `bpf` module (pinned eBPF map access). Requires
`bpftool`; skipped when it is not available.

- **map_values**: creates a pinned hash map with `bpftool`, then exercises
  `lookup`, `update` (flag semantics included), `delete`, `remove`, `next`
  driving a generic `for`, `info`/`#` and the lifecycle after `close`;
  also asserts that the key-value handle carries no queue methods, and
  that `bpf.hash` rejects non-map paths, every other map type and
  mismatched key/value sizes.
- **array**: array map coverage — update/lookup by packed index,
  zero-filled reads of unwritten indexes, out-of-range lookup and
  update, `delete`/`remove` rejection, full index iteration and the
  cross-type constructor rejection.
- **lru**: LRU hash round-trip (update, lookup, remove, delete) and the
  cross-type constructor rejection.
- **queue**: queue map coverage — push/peek/pop in FIFO order, empty-map
  `nil`, full-map `false` and `BPF_EXIST` overwriting the oldest, invalid
  push flags, the absence of key-value methods on the handle, the
  cross-type constructor rejection and metadata with `key_size` 0.
- **stack**: the same for LIFO stack maps.
- **map**: the `bpf.map` layer — scalar, multi-value and `struct` codec
  specs, the table proxy (assignment, `nil` delete, `pairs`, `<close>`
  and function-named keys as plain map keys) over hash, array and
  lru_hash, the queue and stack objects (`push`/`pop`/`peek`, FIFO and
  LIFO order, empty `nil`, full `false`, `info`), spec size validation
  and the cross-type rejection.
- **map_softirq**: opens and exercises the hash map while loading a
  softirq runtime (atomic-context allocator path).
- The harness also cross-checks a Lua-written value with
  `bpftool map lookup` (kernel-to-userspace interop).

### crypto

Covers the `crypto` module: `shash`, `skcipher`, `aead`, `rng`, `hkdf`,
`comp`. `comp` is skipped where `crypto.comp` is not built: `hascomp` asks
the runtime for the binding, instead of the suite reading the kernel version.

- **context**: an object refused for its execution context leaves nothing
  allocated. `crypto.shash("sha256")` and `crypto.comp("lz4")` from an armed
  softirq runtime are refused, and the modules backing those algorithms -
  named by holding one object of each kind alive and watching which of
  `/proc/crypto`'s modules gain a reference - keep the reference counts they
  had. Skips when no module backs either, and when the loaded `luacrypto` cannot
  be shown to be the build this case was installed with, since only that one is
  known to refuse before allocating.

### data

- **bounds**: `data.new()` and `data:resize()` accept the sizes they serve,
  round-trip a byte at the far end of the buffer, and refuse zero, a
  negative and anything past `INT_MAX`; a refused resize leaves the object
  on its old buffer.
- **resize_atomic**: a failed reallocation must not look like a success. A
  vmalloc-backed buffer grown from a `GFP_ATOMIC` runtime asks the page
  allocator for an order past `MAX_PAGE_ORDER`, so the allocation fails by
  construction and `data:resize()` has to keep the size and the bytes it
  had. Skips when the buffer did not land in `vmalloc`.
- **zeroed**: an owned buffer holds no byte the script did not write.
  `data.new()` and a `data:resize()` that grows come back zeroed, on the
  `krealloc` and the `kvmalloc` arm of the allocator and from an atomic
  runtime. A round poisons its buffers and frees them so the next round
  allocates over them, and a shrink followed by a growth back into the block
  it kept reads the buffer's own bytes and needs no such luck. Skips on a
  kernel that zeroes every allocation itself, where a fixed `data.new()` and
  a broken one read the same.

### device

- **held**: an open file holds the device's memory from its open to its
  close, and a refused open gives it back at once, while the node goes with
  `dev:stop()` or with the runtime, whatever is open. A kprobe on
  `luadevice_free`, read from `kprobe_profile`, counts the devices whose
  memory went, and one on `lunatik_releaseobject` the Lunatik objects freed.
  A live device reads and writes, and an open its callback
  refuses fails with `ECANCELED` and holds nothing, so its device goes with
  its runtime. A device stopped and collected from its own write while a
  file holds it leaves `/dev` and sysfs at once; the file reads and writes
  `ENXIO`, reopening it through `/proc` finds no device, and the memory goes
  at its close and not before. A device stopped and collected from its own
  open, between the share the open took and its callback, leaves that open a
  file that reads `ENXIO` and holds the memory until its close. A runtime
  stopped while a file holds its device removes the node, and the file
  reads, writes and reopens `ENXIO`; the script starts again under the same
  name with that file still open, the file reads `ENXIO` rather than reach
  the new device, a reopen of it through `/proc` is refused with `ENXIO`
  when the new device took its number, and the memory goes at its close,
  the stopped runtime's object with it, once the driver runtime has collected
  the copy of its handle that `lunatik stop` left there.
  A build without the
  file's hold reads freed memory in each held case, so the test skips unless
  the loaded `luadevice` lists `luadevice_free` in `/proc/kallsyms`.

### examples

- **shared**: drives the spawned `examples/shared` daemon over its own port with
  a kernel-side client: a GET of a key that was never assigned and a GET of a
  key a SET removed each answer with an empty line, instead of taking the thread
  body down and leaving the port bound with nobody in `accept()`; and a peer
  that hangs up with its reply unread, which resets the session, leaves the
  daemon answering the connection after it. That peer is a userspace one, since
  a lunatik socket shuts down before it releases; the case skips without
  `python3`. A GET of a key that was set answers with the value and nothing
  else, over a rewrite to a shorter value too, which the byte-exact assertion
  tells from a reply carrying the whole slot.

### fifo

- **bounds**: `fifo.new()` accepts the capacities it serves and refuses
  zero, one (kfifo's own floor), a negative and anything past
  `KMALLOC_MAX_SIZE`, including a value `__kfifo_alloc()`'s `unsigned int`
  truncated into a small fifo; `fifo:pop()` refuses a size past the
  capacity, which it could never return.

### fsnotify

Every mark in this suite goes on a scratch directory the test creates and
removes, `/tmp/lunatik-fsnotify` or the one the example under test names: a mark
outside a scratch subtree is what makes a machine unable to read its own files.
A mount or superblock mark reaches every file it covers, and a permission mark
decides whether an access happens at all, so the tests that place either mount
their own tmpfs there and mark that; the one exception is `context`, whose
permission mark allows and only asks whether the mask is taken.

- **open**: an inode mark reports `FS_OPEN` for the file it was placed on, with
  the mask the callback asserts, and reports nothing for a neighbour in the
  same directory.

- **nomask**: an `FS_MODIFY` mark ignores an `FS_OPEN` on the same file, and
  still delivers the `FS_MODIFY` that follows, so the negative half cannot pass
  on a watch that stopped working.

- **child**: a directory mark reports a child's `FS_OPEN`, tagged
  `FS_EVENT_ON_CHILD`, only when its mask carries that flag; without it the
  child's open delivers nothing while the directory's own open still delivers
  `FS_OPEN | FS_ISDIR`, so the negative half cannot pass on a dead watch.

- **kinds**: the three kinds of mark, on a tmpfs the test mounts under the
  scratch directory and bind mounts a second time, skipped when that mount does
  not appear. Before 6.10, where the binding has no mount kind, `mark` and
  `find` refuse that kind with the message the binding documents, pointed at
  that tmpfs, and the rest skips. A mount mark reports a file opened under its
  mount and reports neither a file outside it nor the same inode opened through
  the other mount; a superblock mark reports that same open and nothing on
  another filesystem. `watch:find` then returns the mark of each kind by path
  and kind, and `nil` for a kind the watch did not mark, and the tmpfs is
  unmounted under all three, which is the path where the kernel clears a
  group's marks on its own before the watch walks them.

- **mask**: a live mark's masks. A mark placed for `FS_OPEN` and set to
  `FS_MODIFY` stops reporting the open and starts reporting the write, which
  separates a recalculated object mask from a field written on the mark alone;
  a second mark carrying both events and ignoring `FS_OPEN` reports only the
  write, so the ignore mask suppresses what it names and nothing else, and a
  read after that write is silent too, so a write does not clear it.

- **marks**: the mark as an object. `watch:find` returns the mark the watch
  placed, `nil` where it has none and `nil` after `remove`, a second mark on
  the same object is refused with `EEXIST`, a removed mark's handle raises and
  the mark delivers nothing while its neighbour does, and `stop` takes every
  mark with it and leaves no usable handle. The whole test runs twice in a row
  and counts the events of each round, so a mark or a group the first round
  leaked shows as a second line rather than passing a presence test.

- **vanished**: `mark:mask` removes the mark and adds it again from its path,
  so a path the shell moved away raises `ENOENT`, leaves the handle dead and
  leaves the inode unmarked, whose open through the new name is then silent.
  The call comes from the read handler of a device the script creates, outside
  any callback, where the walk is not confined to the directory cache and the
  missing name answers `ENOENT` whatever the filesystem keeps of it.

- **inside**: a mark removed, and a mark's mask set, from inside the callback,
  which runs in fsnotify's SRCU read section and takes the group's mark mutex
  there, the path inotify's one-shot watch takes to destroy its own mark. The
  mark removed on its first event delivers once; the mark set from `FS_OPEN`
  to `FS_MODIFY` on its first event delivers that open once, nothing for the
  read after it, and the write. Both resolve a path, and a callback's task may
  hold the lock of the directory the event is about, so a path resolved there
  stays in the directory cache: a name the shell never touches answers `EAGAIN`
  instead of descending into that lock, while the two cached paths resolve. The
  open events arrive with no directory lock held, so a mark on the scratch
  directory for `FS_CREATE`, which fires inside the parent's lock, resolves the
  same name from its callback and answers `EAGAIN` there; a tree without the
  flag wedges the host on that case, so it discriminates by the message. From
  an open's callback, `watch:mark` places a mark on a cached path that then
  delivers, and answers `EAGAIN` for the uncached name; another watch of the
  same runtime asked from that callback answers `EAGAIN` for it too, since the
  flag belongs to the runtime. A file renamed before its open leaves the name
  its mark was placed with out of the cache, so `mark:mask` set from that open's
  callback answers `EAGAIN` and leaves the mark removed, the second open
  silent. A watch stopped from inside its own callback,
  which removes its marks in the same read section, returns from `stop`,
  delivers nothing afterwards, and leaves a runtime that still tears down
  cleanly.

- **raise**: a callback that raises on a notification event is logged under the
  module's name, and the next event on the same mark still reaches it, so the
  first case cannot pass because the watch was gone. `error` asserts the same
  of a permission event and skips without the hooks; this one runs on every
  kernel.

- **identity**: the matrix of event kind by accessor. A file open carries a
  `struct path`, so `name`, `ino`, `dir`, `isdir`, `pid` and `path` all answer;
  a directory open is flagged `FS_ISDIR`; a create, a rename and a delete name
  the entry and its directory and carry no path. Each case asserts every
  accessor, the `nil` ones included, against what the shell already knows: the
  inode numbers from `stat -c %i`, the pid from its own `$$`, and the path it
  built. A stimulus the shell performs itself is matched by that pid, so another
  process touching the scratch file cannot be read as it. `FS_RENAME`, which
  `handle_event` receives with no same-parent filter, names the old entry, its
  directory and the moved inode for a move within the marked directory and for
  one out of it; a write to a file already unlinked reports a path ending in
  ` (deleted)`; and a file buried past `PATH_MAX` makes `event:path()` raise
  `ENAMETOOLONG`.

- **overlap**: an event matched by two marks of one watch arrives once. The
  watch dispatches through `handle_event`, called once per group with the event
  as raised, not once per matching mark; a file marked together with its parent
  directory (`FS_EVENT_ON_CHILD`) is delivered once, tagged `FS_EVENT_ON_CHILD`
  and carrying its `name` and `dir`, and the directory's own open still arrives
  once. The lines are counted by the shell's own pid.

- **expired**: an event kept past the callback it was handed to raises when
  read. Two watches in one runtime, so the prober reads the keeper's stashed
  event while no event of the keeper's is in flight; reading it from a later
  event of the same watch would find the object reset and alive. Its
  discrimination rests on the message the prober asserts.

- **reentrancy**: a callback that opens the file it watches returns instead of
  deadlocking on the runtime lock it already holds. Its discrimination rests on
  the message the callback prints and on the read returning within 10 seconds;
  removing the guard reproduces an unkillable process, not a failed assertion.

- **thread**: a spawned thread body, which holds the runtime lock for its whole
  life, opens the path its own runtime watches and returns instead of blocking
  on that lock. Its discrimination rests on the message the body prints and on
  observer.lua seeing the open the guarded runtime skipped; removing the guard
  reproduces an unstoppable kernel thread, not a failed assertion.

- **lifetime**: a second `stop()` is a no-op and `mark` raises after it;
  delivery ends at `stop()`; and a watch left unstopped is torn down by the
  object's release, after which unlinking the marked inode raises no kernel
  error.

- **context**: `fsnotify.watch` refuses a callback that is not a function, a
  softirq runtime and a percpu runtime, and takes a second watch on a runtime
  that already has one; `mark` and `find` raise the errno name for a path that
  does not resolve and refuse an invalid kind, and `mark` and `mark:mask` take a
  permission mask or name the config a kernel built without the hooks lacks,
  `mark:mask` keeping the mark's mask when it refuses.
  The shell counts the passing cases rather than looking only for a failing one,
  so a case that never ran cannot pass.

- **fsmonitor**: the `fsmonitor` example, run from where `examples_install` puts
  it, so what the test covers is what a reader of the README gets. It reports a
  create, a write, an attribute change and a delete in the directory it watches,
  each with the entry name and the inode number, and the two the shell performs
  itself carry its own pid. A subdirectory created there is reported, a directory
  entry event of the marked directory, and neither the file created inside that
  subdirectory nor a write to it is, since the subdirectory carries no mark and
  `FS_EVENT_ON_CHILD` reaches one level; nothing is reported at all once the
  example is stopped.

The tests below cover the permission events, where the callback's return value
decides whether the access happens. Each of them sources `perm.sh`, which mounts
a tmpfs of its own and asks the module through `probe.lua` whether this kernel
has the permission hooks at all, skipping the whole plan when it does not. Every
mark they place is on a tmpfs the test mounted, so a rule that denies reaches
nothing the machine needs and the unmount takes the mark with it. Every one of
them undoes its rule in the trap, and the deny tests read the denied file again
after the watch is stopped.

- **allow**: a callback returning `ALLOW` lets the open through, and the
  callback saw the open that produced the content the shell read. This is
  asserted first: a verdict path that denies everything passes any test that
  only asserts denials.

- **deny**: a callback returning `DENY` fails the open with `EPERM` while the
  neighbouring file it does not name still opens, a third file answered
  `-4095`, the last errno the kernel recognises, fails with that number, and
  the denied file opens again once the watch is stopped.

- **default**: everything that is not a deliberate denial allows. A callback
  that returns nothing, one that returns `1`, one that returns a string and one
  that returns `-1000000` all leave the open through: a positive answer would
  be a kernel warning and `EINVAL` in `do_dentry_open`, or a fake byte count in
  `vfs_read`, and one below `-MAX_ERRNO` a pointer `IS_ERR` does not
  recognise. So do `math.maxinteger`, whose low 32 bits are `-1`, the
  string `"-1"`, which `lua_tointeger` would take as one, and `-4096`, the
  first value past the errno range.

- **exec**: a mark for `FS_OPEN_EXEC_PERM` denies the exec of a program copied
  onto the tmpfs while an ordinary read of the same file still succeeds, and the
  program runs again once the watch is stopped.

- **access**: a mark for `FS_ACCESS_PERM` leaves the open alone and denies the
  read that follows it, which the shell separates by opening the file on a
  descriptor of its own before reading from it.

- **error**: a callback that raises allows the access and the raise is logged;
  a second open still reaches the callback, so the first case cannot pass
  because the watch was gone. Its kernel log carries a Lua error on purpose,
  as `raise`'s does.

- **sleep**: a callback that calls `linux.schedule` finishes and the open waits
  for it, which is what makes a process-context runtime the right one for a
  hook that runs inside the accessing task's syscall.

- **upgrade**: a mark placed for `FS_OPEN` and set to `FS_OPEN_PERM` through
  `mark:mask` denies the open, and the callback sees the permission event. This
  is the case the group's priority is set for on every group: from 6.10 the
  open path delivers a permission event only where a content-priority group
  marked the object, counted when the mark was added, so a priority taken on
  the first permission mask would leave this mark uncounted and the open would
  succeed with nothing said. Before 6.10 it passes either way.

- **directory**: a directory mark reaches a permission event two ways the file
  marks do not exercise. `FS_OPEN_PERM` with `FS_EVENT_ON_CHILD` on a directory
  denies the open of a file inside it, through the parent iterator, while the
  directory's own open stays allowed and it still lists; `FS_ACCESS_PERM` on a
  directory denies its listing, which `iterate_dir` asks for, while a file
  inside still reads, since that mark carries no `FS_EVENT_ON_CHILD`. Both
  directories are on the tmpfs, and the gated file opens again after the stop.

- **execguard**: the `execguard` example, run from where `examples_install` puts
  it, over a tmpfs mounted at the directory the example marks. A program whose
  name its allowlist carries runs, one it does not name is refused with `EPERM`,
  and a copy of that refused program, same name, runs from a sibling directory
  and from a subdirectory of the scope: the mark is on that one directory, so
  the rule reaches neither outside it nor below it. The refusal names the entry,
  the pid it was refused to and the allowlist as its reason, and ends with the
  example. A script the allowlist names is refused when its interpreter is a
  copy of `sh` in the scope, and the refusal names `sh`: the kernel opens the
  interpreter for exec too. Run again with a pid list in the scope, the same
  allowed program runs for a shell the list names and is refused to one it does
  not, with the pid as the reason, and a name the allowlist does not carry is
  refused to an unlisted shell with the allowlist as the reason, the check made
  first, each shell exec'ing in place so the pid that
  asks is the listed one, and a listed shell is still refused a name the
  allowlist does not carry. Run once its scope is gone, the example fails to
  load with `ENOENT`: asking whether the kernel takes a permission mask
  swallows no other error. What it says on a kernel without the hooks is not
  covered, since the suite skips there.

### hid

- **register**: what `hid.register()` makes of an `id_table`. It accepts one
  of a single entry and one of `LUAHID_MAXIDS`, under a vendor no device on
  the bus carries, and registers again after every refusal; the accepted
  drivers reach `/sys/bus/hid/drivers` and leave it with the runtime. A
  longer table, a length a `__len` metamethod fabricates, a length that is
  not an integer, an entry that is not a table and an entry that raises
  while it is read are each refused, and each refusal forces the refused
  driver's finalizer. A name filling `NAME_MAX` with no room for its
  terminator is refused too, and the longest that does leave room reaches
  the bus intact. Skips when the kernel has no HID bus.
- **idtable_leak**: an `id_table` whose entries raise from `__index` leaves
  nothing allocated behind. The refusal is repeated until what a leak would
  hold is tens of MiB in `SUnreclaim`, and the script then holds as many
  live buffers of the same size; skips when the counter does not move for
  that probe either.

### io

- **test**: kernel `io` library (open/read/write/seek/lines/type); also
  asserts `io` is absent from softirq runtimes.

### linux

- **random**: `linux.random` ranged draws stay within `[m, n]`, covering
  the two-argument, one-argument and negative-range forms.
- **fs**: `linux.fs` carries every fsnotify event mask at the value the
  `FAN_*`/`IN_*` uapi pins it to, every entry is a single distinct bit,
  and the composite and private names the curated `include` list drops
  (`FS_MOVE`, `FS_EVENTS_POSS_ON_CHILD`, `FS_IN_IGNORED`,
  `FS_DN_MULTISHOT`) are absent.

- **lookup**: `linux.lookup` answers `nil` for a symbol kallsyms does not
  carry and a lightuserdata for one it does, and rejects a non-string
  argument; a `softirq` and a `hardirq` runtime resumed past their body, the
  armed state a hook calls from, each resolve a symbol and get `nil` for an
  absent one; skipped without `CONFIG_KPROBES`, which the resolution needs.

### lua

Holds the vendored Lua to the contract the top-level README documents, so a
bump of `lua/` that drops a kernel guard fails here instead of compiling.

- **floats**: no float literal, exponent, hexadecimal float or `^` compiles;
  `/` is integer division on a constant, a register and a coerced string,
  raises on zero and dispatches `__idiv`; `__div` and `__pow` are not
  metamethods, on a table or on a string; `math` keeps only its integer
  half; `tonumber` refuses every float spelling; `string.format` refuses
  every float conversion; `string.pack` refuses `f` and `d` and packs and
  unpacks `n` as an integer.
- **identifiers**: `_VERSION` is `"Lua 5.5-kernel"`, `collectgarbage("count")`
  answers in bytes, `package.path` resolves under `/lib/modules/lua/`, `os`
  and `debug.debug` are absent, `io` has no default stream, pipe or
  `setvbuf`, and `package` has no `cpath` and resolves a C module in the
  kernel symbol table.

### luac

- **run**: the bytecode compiler `lunatic`: compiled chunks (full and
  stripped) run under `lunatik run` and `require`; error messages carry the
  source path and line, or `?:?:` when stripped; `-l` lists a compiled
  chunk; a syntax error names the file and line, `-p` writes no chunk, and
  250 inputs compile in one call; `lunatik compile` forwards its arguments
  and `lunatic`'s exit status; a stock (float) number format is rejected
  by the chunk header, in the kernel and as an input to `lunatic`; `-e` with
  the host's byte order gives the default output and with the other order a
  chunk the kernel's header check rejects;
  `load(..., "t")` rejects a chunk in the kernel. Skips when `lunatic` is
  not installed.

### monitor

Regression tests for `lunatik_monitor` (spinlock + GC interaction).

- **gc**: a spawned thread uses a `sleep=false` fifo from a `sleep=true`
  runtime; `f:pop()` allocates inside `spin_lock_bh`, forcing GC that
  finalizes a dropped AF_PACKET socket. Must not trigger "scheduling
  while atomic".

### netlink

Tests for netlink: the `AF_NETLINK` address family in `socket`, and the
higher-level `netlink.*` modules built on top of it.

- **rtnl**: `netlink.channel` from a netdevice callback is refused, probed
  from the replay of a `notifier.netdevice` registration: registering the
  family takes a lock a request holds while its handler may wait on the RTNL
  that task holds. A channel is accepted once the registration returned. A
  build without the refusal hangs only if such a request is in flight, which
  the test cannot rule out, so it skips unless the loaded `luanetlink` is the
  installed one.

- **socket**: opens an `AF_NETLINK` socket; a bind/`getsockname` round-trip
  exercises the address translation, and an `RTM_GETLINK` dump exercises send
  (which attaches the kernel destination) and receive.
- **message**: builds a message with attributes and parses it back, asserting
  the round-trip preserves the type and attribute values; and the edges:
  malformed wire data parses to nothing, empty attribute sets round-trip
  empty, and a non-u32 number value raises.
- **session**: over a fake socket, `dump()` terminates (does not hang) on an
  empty read; `talk()` drains the reply up to the kernel acknowledgment,
  keeping a data reply and passing a zero error code; and `talk()` raises the
  bare symbolic error name on a kernel error reply.
- **genl_family**: `genl.family("nlctrl")` resolves the generic netlink
  controller family to `GENL_ID_CTRL`; then on the same instance a `GETFAMILY`
  `call()` round-trip (regression for the orphaned-ACK desync), a `GETFAMILY`
  `dump()` that lists every family (with `nlctrl` among them), and an unknown
  family raising.
- **link_list**: `rt.link():list()` lists interfaces; asserts loopback (`lo`,
  ifindex 1) is present with a non-zero MTU.
- **link_updown**: `rt.link():set()` brings a down dummy interface up and
  asserts `IFF_UP` appears in its dump flags, then brings it down and asserts
  the flag is cleared.
- **link_netns**: the pid a session takes (`socket.new`'s fourth argument):
  `rt.link()` without one lists the initial namespace, `lo` and not the dummy
  device the test put in a namespace of its own; `rt.link(pid)` with the pid of
  a process kept there lists that dummy; the pid of a reaped process raises
  `ESRCH`, a pid out of range raises, and so does a protocol past `MAX_LINKS`
  in that namespace. The script then kills the process, the last task in a
  namespace whose name the test already deleted, and lists the dummy again
  through the session it holds: the socket keeps its namespace alive. Once the
  script has closed its sockets, the one the kernel refused having kept no
  reference, the namespace goes, and with it the veth pair the test gave it,
  whose end in the initial namespace disappears (skips without `nsenter`,
  network namespaces, the dummy driver or veth). On a kernel where `socket.new`
  refuses a task's namespace with `EOPNOTSUPP`, the script says so and the
  five namespace cases skip on that message.
- **addr_list**: `rt.addr():list(AF_INET)` lists addresses; asserts `127.0.0.1`
  is present on loopback with `prefix_len == 8`.
- **route_list**: `rt.route():list()` returns at least one route with its
  `family`, `scope` and `rtype` fields populated.
- **route_adddel**: `rt.route():add()` creates a dummy `192.0.2.0/24` route via
  `lo` in an isolated table whose id is > 255 (exercising the `RTA_TABLE`
  attribute path), confirms it in a dump, asserts a duplicate add raises
  (`NLM_F_EXCL`), then `del()` removes it.
- **rule_adddel**: `rt.rule():add()` creates a FIB rule directing lookups to an
  isolated table whose id is > 255 (exercising the `FRA_TABLE` attribute),
  confirms it in a dump, asserts a duplicate add raises (`NLM_F_EXCL`), then
  `del()` removes it; a second add/del round uses a table id that fits the u8
  header field, exercising the header-side id path (no `FRA_TABLE`).
- **channel**: a softirq runtime registers a generic netlink family, unicasts
  to an absent port id (which returns `false`), and installs a `PRE_ROUTING`
  netfilter hook that, on received traffic (NET_RX softirq), both multicasts to
  the group and unicasts to a fixed port id; a userspace subscriber bound to
  that port id and joined to the group receives both, proving kernel-to-
  userspace multicast and unicast delivery from softirq; on its first packet the
  hook calls `netlink.channel`, which must raise there, and the same script run
  percpu is refused at load (skips without `gcc`/`genl`).
- **nl80211**: loads `mac80211_hwsim` (simulated wifi), then
  `netlink.nl80211.interface` lists the simulated `wlan` interfaces over the
  nl80211 generic netlink family
  (asserting one is present, in `STATION` mode and with its fields decoded) and
  asserts both simulated wiphys come out of `netlink.nl80211.wiphy`'s
  fragmented `GET_WIPHY` dump (skips without `mac80211_hwsim`).
- **nl80211_iface**: `netlink.nl80211.interface():add()` creates an AP interface
  on the first simulated wiphy, asserts it returns the new `ifindex` and the
  interface shows up as an AP in a dump, asserts a second add of the same
  interface raises, then `del()` removes it (skips without `mac80211_hwsim`).
- **nl80211_ap**: creates an AP interface on the first simulated wiphy, brings
  it up (`rt.link():set`), then `netlink.nl80211.ap():start()` begins beaconing
  with a minimal open-AP beacon on channel 1, asserts a second start raises,
  and `stop()` ends it — the whole AP bring-up staying in the kernel (skips
  without `mac80211_hwsim`).
- **nl80211_station**: over a beaconing AP, `netlink.nl80211.station():add()`
  adds a station and asserts it appears in `list()`, a duplicate add raises,
  `set{authorized = true}` is accepted (the `STA_FLAGS2` path), and `del()`
  removes it (skips without `mac80211_hwsim`).

The three tests that create the AP interface move the simulated wiphy into a
network namespace of their own, and every session of their scripts takes the
pid of the process kept there, so no process of the initial namespace, a
network manager's included, acts on the interface under the test; the wiphy
comes back when the namespace goes (they skip without `iw` or `nsenter`).

### notifier

- **context_mismatch**: calling a hardirq-class constructor (e.g.
  `notifier.keyboard`) from a process runtime must error with "runtime
  context mismatch" without oopsing during `__gc`.

- **init_dispatch**: `notifier.netdevice(cb)` at script init must handle
  the synchronous `NETDEV_REGISTER` replay `register_netdevice_notifier`
  performs for the devices the namespace already has.

- **netns_scope**: `notifier.netdevice` reports the devices of every network
  namespace, each with the inode number of its namespace, which `linux.netns()`
  gives for the initial one and `linux.netns(pid)` for a task's: pid 1's is the
  initial namespace's, the pid of the process kept in a second namespace gives
  that one's, a reaped pid raises `ESRCH` and pid 0 is out of bounds. With that
  namespace holding a homonym of every device, `lo` is replayed once per
  namespace with its own number, a dummy device created and deleted on both
  sides is reported on register and on unregister with the number of its side,
  and one moved across is unregistered with the number of the namespace it
  leaves and registered with the number of the one it joins (skips without
  `nsenter`).

- **replay**: a flag the script clears once `notifier.netdevice` returns
  tells the events `register_netdevice_notifier` delivers itself for the
  devices the namespace already has from the live ones: a dummy device brought
  up before the script runs is replayed as a `REGISTER` and an `UP`, both under
  the flag; one created, brought up and deleted afterwards is reported live,
  none under it; and none is flagged once the registration has returned.

- **inside**: `notifier.netdevice` from inside a netdevice callback is refused,
  in both the contexts the callback runs in: the replay the registration
  delivers on its own task, and a live event on another task. A coroutine
  resumed from the callback, the body of a runtime the callback creates and a
  runtime the callback resumes are refused too, since the refusal keys on the
  task that holds RTNL and not on a Lua state; a registration made once the
  callback has returned, or raised, is accepted, and `notifier:stop()` from
  inside the callback is accepted and ends delivery.
  A tree without the guard wedges the host rather than failing the test, so it
  never runs against one: the discrimination is the message it asserts, and those
  last three cases; it skips unless the loaded `luanotifier` lists
  `luanotifier_netdevice_call`, which sets the task, in `/proc/kallsyms`. The
  runtimes it resumes register only once resumed, so they hold no block, which
  would keep them alive past the script: stopping the script leaves
  `luanotifier`'s use count as it was.

- **stop**: `runtime:stop()`, and the `__close` of a runtime held by a `<close>`
  local, from inside a netdevice callback are refused, on the replay and on a
  live event, since the close runs every release of the state on the callback's
  task and a netdevice block's unregistration waits on the RTNL that task
  holds; the child it would have stopped reports the event that follows, and a
  stop once the callback returned is accepted. A percpu set's `stop()` and
  `__close` are refused from the same callbacks and accepted afterwards; its
  runtimes hold no block, so a build without that refusal closes them without
  wedging and the message is what discriminates. A tree without the runtime's
  refusal wedges the host, so the test skips unless the loaded `lunatik` lists
  `lunatik_lstop` in `/proc/kallsyms`. The child is started through the
  runner, so the cleanup stops it by name whatever a case leaves.

- **chain_continues**: a netdevice block whose runtime is being torn down
  returns `notify.DONE`, not the `-ENXIO` of `lunatik_run`, whose
  `NOTIFY_STOP_MASK` bit stopped the chain: a device created while one
  runtime holds its teardown reaches the block a second runtime registered
  after it.

### probe

- **aggregate**: a target another kprobe already holds is aggregated by the
  kernel, and every handler attached to that address runs on a hit. One plain
  hardirq runtime registers two probes on the `personality` syscall and one
  `setarch` calls it once: the second `probe.new` succeeds, both handlers print
  once, the kprobe list grows by two lines over one more address, since an
  aggregate lists each member separately, and the stop gives all of it back. The
  target is the same address twice, not two names the kernel resolves to one,
  which is arm64-specific and needs an unimplemented syscall.

- **argument**: the `argument` closure a handler receives, on its three
  outcomes: a probe on `vfs_read` reads the byte count the caller asked for,
  a negative index raises, and both it and the `dump` closure stop reaching
  the registers once the handler that received them returned.

- **armed**: `probe.new`, `stop` and `enable` all reach a kprobe call that
  sleeps, so each is allowed while the script loads, in process context, and
  refused from a handler, where the runtime is in hardirq: the script registers,
  toggles and stops a probe on the way in, then probes `vfs_read` and calls all
  three from its own handler. Do not run it against a build without the guard,
  which would reach `synchronize_rcu` with interrupts off.

- **dropreason**: the kprobe target the kernel's drop path offers and the
  argument its reason arrives in, which moved together at v6.11, where
  `kfree_skb_reason` became a static inline over `sk_skb_reason_drop`: the
  script probes whichever symbol `linux.lookup` finds, and the shell checks
  that name against `/proc/kallsyms` and that the handler counts the
  `NO_SOCKET` drops of a batch of datagrams sent to a closed UDP port, which
  a handler reading the wrong argument counts none of. Skipped without
  `CONFIG_KPROBES` or `CONFIG_HAVE_FUNCTION_ARG_ACCESS_API`, on a kernel that
  carries neither symbol, and when something holds the port.

- **handlers**: which handler a hit runs, over the four handlers tables
  `probe.new` takes: only `pre`, only `post`, both, and neither. Each script
  probes the `personality` syscall, which one `setarch` calls exactly once, so
  the handler the table defines runs once and the one it does not never runs;
  the empty table has nothing to print, so what it asserts is that `probe.new`
  still succeeds, and each of those rows checks the kprobe it armed on load and
  gave back on stop. The post half of a hit had no coverage before: nothing in
  the tree registered a `post` handler. Two further rows cover what `probe.new`
  reads from that table: of a `pre` and a `post` added to it after `probe.new`,
  the `pre` fires and the `post` does not, and a percpu script whose runtimes
  disagree about one is refused, leaving no kprobe armed.

- **kprobe_concurrent**: registers kprobes on every syscall, each handler
  counting into an `rcu.table` and a `data` buffer, and runs one forking
  load generator per CPU; `lunatik stop` must complete within 30 s with no
  kernel errors under concurrent handler firings.

- **percpu_probe**: the runtimes of a percpu script share one kprobe on
  the `personality` syscall, which nothing else on an idle host calls: a
  pinned `setarch` is handled exactly once, by the runtime of the CPU it
  ran on, with the address the script gave, and no runtime is reached
  through a kprobe it did not register;
  the set arms that one kprobe however many runtimes it has, and unregisters
  it when it stops; a call pinned to the CPU whose runtime is published last
  is dropped while the runtimes are still being created, and counted once they
  are up; the same script run as a plain runtime drops a call that reaches its
  kprobe before the script body returned, the path where readiness is the only
  thing between arming and the handler;
  one set holds a kprobe per target, and a second probe on the same
  symbol in one runtime is refused, leaving no kprobe armed; `stop` and `enable`
  are refused in a percpu runtime, where the object owns the kprobe; a probe from
  a handler, after the script loaded, is refused; the same script probes as a
  plain hardirq runtime, arming its own kprobe and unregistering it when it
  stops; a plain runtime stops its own probe, twice with no effect, is refused an
  `enable` afterwards, and refuses a probe on a symbol the kernel does not have;
  and a set whose last runtime errors releases the kprobe the earlier ones
  shared, leaving no kprobe armed, no script registered and no use-count on the
  probe module.

### rcu

- **map_values**: `rcu.map()` iterates booleans, integers, userdata,
  mixed types, and skips nil (deleted) entries.

- **map_foreign**: `rcu.map()` refuses an object of another class
  instead of walking its private data as a table.

- **index_whole**: an index matches the whole key. On a one-bucket table, a
  prefix of a stored key reads `nil` and an assignment to it adds an entry
  instead of replacing the longer one, the empty key reads `nil` until it is
  set, and two keys alike up to an embedded NUL are told apart.

- **bounds**: `rcu.table()` defaults to a usable table, accepts the bucket
  counts it serves, and refuses zero (`roundup_pow_of_two()` is undefined
  there), a negative, and the counts whose byte size wraps; a count it can
  size but no allocator serves is a memory error with no kernel warning
  behind it.

- **map_sync**: `rcu.map()` remains safe when called while another
  kthread is modifying the table.

- **newobject_oom**: a failed private allocation in `lunatik_newobject()`
  surfaces as a graceful error without the `__gc` finalizer running on
  uninitialized memory. The failure is forced on the `GFP_ATOMIC` path,
  where a bucket count past `KMALLOC_MAX_SIZE` cannot be served by
  construction.
- **bigtable_free**: a large `rcu.table()` whose private exceeds `KMALLOC_MAX`
  is backed by `vmalloc`; releasing it must free with `kvfree`, not `kfree`,
  so the teardown leaves the kernel alive.

- **entry_release**: the value an entry drops is released after the table's
  spinlock, on the writing task. Two children, each holding `byteorder`, are
  stored as the only reference their entries hold; removing one entry and
  replacing the other closes each child there, and the module's use count is
  back when the body returns. A kprobe on `lunatik_releaseobject` says where
  each close ran: a hit taken with bottom halves off carries `b` in its flags,
  `D` where the handler also masks interrupts, so a build that puts under the
  lock fails the read on any kernel, with or without
  `CONFIG_DEBUG_ATOMIC_SLEEP`; the children hold nothing that sleeps on close,
  so that build fails the test and not the host.

- **object_grace**: a reader takes its reference on an entry's object under
  `rcu_read_lock` alone, and a writer replacing the entry puts the object's
  last reference at once: the object's memory outlives the grace period and
  the reader takes the reference unless the count is zero, reading the entry
  as gone. A reader thread reads one key, by index and through `rcu.map`, and
  touches the object each hands it, while a writer thread replaces that key's
  `data` object on every iteration, for a few seconds; every read is a usable
  object or nil, the reader saw the entry replaced while it read, and `dmesg`
  carries no refcount warning or oops. A stress, not a forced window; skips
  unless the loaded core carries `lunatik_getobject_rcu`.

### runtime

Regression tests for `lunatik_newruntime` and cross-runtime plumbing.

- **refcnt_leak**: module use-count leak when a script errors after a
  successful `netfilter.register()` call. The fix, under the runtime
  spinlock, nulls `runtime->private`, calls `lua_close(L)` to fire the
  hook finalizer (`nf_unregister_net_hook` + `symbol_put_addr`), and
  then releases the runtime. The percpu case errors on the last runtime, so
  the rollback has the hooks of the earlier ones, which the shared registration
  holds, to release; it needs more than one CPU and skips otherwise.

- **resume_shared**: `runtime:resume()` passes shared (monitored) objects
  across runtime boundaries. Push into a shared `fifo`, resume a
  sub-runtime with it, assert the value pops on the other side.

- **resume_results**: `runtime:resume()` returns what the resumed script
  yields, and what it returns: one object, then two in the order they were
  yielded, then the returned one. A yielded value that is not a Lunatik
  object, and a yielded `SINGLE` one, are refused by name and leave the
  runtime suspended and resumable; a number given to `resume()` is refused
  the same way; and a runtime whose body has returned is dead to the next
  `resume()`. The first `resume()` carries two objects the script checks it
  got in order, so the values come back off the resumed stack rather than
  from a slot indexed by the caller's argument count, and one round carries
  more objects than `LUA_MINSTACK`, in both directions.

- **resume_foreign**: `runtime:resume()` refuses an object of another class
  instead of reading its private data as a Lua state.

- **foreign_method**: `device:stop`, `notifier:stop`, `probe:stop`,
  `probe:enable` and the `rcu.table` index metamethods refuse an object of
  another class instead of reading its private data as their own.

- **foreign_checker**: a method of every class a process runtime can
  construct (`data`, `fifo`, `completion`, `set`, `crypto_shash`, `task`,
  `runtime`), called through the class's metatable, refuses an object of
  another class naming both classes, refuses `nil` and refuses a userdata
  of another library; `rcu.map` refuses `nil`; and a method on a closed
  runtime or fifo is refused instead of dereferencing its NULL private.

- **resume_percpu**: `percpu:resume()` delivers the objects it is given to
  every runtime of a process set and of a softirq one, each marking its own
  CPU id in the shared `rcu.table`s it receives, and two of them are marked in
  the order they were passed; what a runtime yields is dropped, and the next
  `resume()` carries the runtimes past their yield; a hardirq set, whose
  runtimes resume under `spin_lock_irqsave`, receives what it is given and
  raises when it is given nothing; the error a runtime raises comes back naming
  it and leaves that runtime dead, so the next `resume()` fails on it again,
  while a value that cannot cross is refused without consuming the yield; and
  it refuses a stopped object, whose runtimes have no state left, and an object
  of another class.

- **resume_mailbox**: `completion` objects pass through `runtime:resume()`
  to enable the mailbox pattern. Sub-runtime sends via `fifo` +
  `completion`; main runtime receives.

- **rcu_shared**: `rcu.table()` is clonable into `lunatik._ENV` and
  retrievable from another runtime.

- **opt_guards**: `lunatik_opt_t` guards reject `SINGLE` objects in
  `resume()` / `_ENV[key] = obj` and accept `MONITOR`/`NONE`.

- **opt_skb_single**: `skb` and `skb:data()` are `SINGLE`, cannot be
  stored in `_ENV`; exercised through a `LOCAL_OUT` netfilter hook on
  loopback.

- **require_cloneobject**: `lunatik_cloneobject` loads the class into
  the receiving runtime via `class->opener` (`luaL_requiref`), even when
  that runtime never called `require()` for the module.

- **require_reopen**: a library opened again under another name (the
  `_ENV` object registers `luarcu` as `rcu.table`, the script's `require`
  as `rcu`) keeps the class metatables the first open created.

- **percpu**: `run <script> percpu` registers one object holding a
  runtime per possible CPU id, and runs the script once per runtime,
  each seeing its own id via `lunatik.cpu()`, which a plain runtime
  sees as `nil`; the script is listed once, by name; `stop` drops every
  runtime and lets it run again; `spawn` refuses percpu without
  creating any runtime; and a script that fails on one runtime rolls
  back the ones already created before the run returns.

- **percpu_object**: `lunatik.percpu()` runs the script once per possible
  CPU id, each runtime stamping its own id; `stop` closes every runtime
  and the object can be created again; `stop` refuses an object of another
  class; a script that fails on one runtime raises with its error instead of
  returning an object.

- **percpu_refuse**: a registration a percpu runtime cannot own fails
  at load, naming percpu, with a clean rollback, and the same script
  runs as a plain runtime: `device.new`, whose registration is global.

- **spawn_refuse**: a spawn whose thread cannot start leaves nothing
  registered. A runtime created for `softirq` or `hardirq` is refused by
  `thread.run`, which cannot start a thread on an IRQ runtime, and `lunatik
  list` must be empty afterwards; the same script spawns and stops as a
  process runtime.

- **spawn_suffix**: a script spawned with its `.lua` suffix registers its
  thread under the trimmed name `runner.stop` looks up, so the stop reaches
  the thread before it closes the runtime, whose lock the body holds while
  it runs.

- **percpu_netfilter**: the runtimes of a percpu script share one
  `LOCAL_IN` hook: with the ping pinned to the last online CPU, each marked
  request is counted exactly once, by the runtime of that CPU; a burst that
  reaches the hook while the runtimes are still being created is accepted
  without being counted; one set holds a hook per target, and a second
  registration of the same one in a runtime is refused; a registration from a
  callback, after load, is refused; and the same script registers as a plain
  softirq runtime.

- **collected**: a runtime, and a percpu set, whose last handle the collector
  takes closes. Its child requires `byteorder`, which holds the module until
  the child's state closes, so the module's refcnt counts the children open:
  the child run on its own raises it by one until its stop, and a driver that
  creates a runtime and a percpu set of it, keeps neither handle and collects
  leaves it where it was when its body returns.

- **self_stop**: a runtime cannot be stopped, resumed, threaded or dispatched
  to from under its own lock. A child resumed with its own handle, and a percpu
  set resumed with its own, call `stop()` and `resume()` on it from the resumed
  body, the runtime `thread.run` on itself too, and get "not allowed from the
  runtime itself"; the driver stops both afterwards, off the lock, and is
  accepted. A device's `read` stops, resumes and threads the runtime that made
  it through the runner's registry and gets the same refusals, opens its own
  node through `io.open` and fails, since `lunatik_run` answers `EDEADLK` to a
  dispatch on the task that holds the runtime's lock, and opens the node of a
  device another runtime made and succeeds. Without the checks each case waits on
  the lock its own task holds, so the test skips unless the loaded core is the
  installed one and that file carries the refusal.

### sched

Regression tests for `luasched`: the attach guards, and the dispatch path
through a struct_ops scheduler whose `enqueue` calls `bpf_luasched_run`.
Skipped when the kernel has no sched_ext (`/sys/kernel/sched_ext`), the
module lacks BTF, or `bpftool` or `clang` is unavailable.

- **sched attach**: `sched.attach()` refuses a sleepable runtime with
  `runtime context mismatch`.

- **sched reattach**: a hardirq runtime attaches, re-attaches (replacing the
  callback) and detaches without a Lua error.

- **sched pass**: registering the scheduler routes every enqueue on the host
  through the Lua callback, which sets the dispatch queue and slice and
  reports once; the report in `dmesg`, with no Lua error, is the proof. The
  scheduler is unregistered before its runtime stops.

### signal

Covers the `signal` module (`luasignal`): the bounds on a signal number, a
command and a pid, and what a valid call does.

- **signal/mask**: `sigmask` blocks and unblocks `TERM` for the task that runs
  the script, and `sigstate` reads it back as blocked, allowed and not pending;
  a signal of 0 or past the set, and a command past `SIG_UNBLOCK`, raise `out
  of bounds` instead of reaching `sigaddset`, whose shift is undefined there.

- **signal/kill**: with a child sleeping in the background and a pid the shell
  has reaped, `kill(child, 0)` probes the child, `kill(reaped)` raises `ESRCH`,
  a pid of 0, one past `PID_MAX_LIMIT` and one that would truncate to the
  child's, and a signal that would truncate to `TERM`, raise `out of bounds`,
  and `kill(child, TERM)` returns true; the shell then sees the child end on
  `SIGTERM`. The truncation cases target the child on every build, so a module
  without the bound signals the child and fails the case, never a stranger.

### set

- **set**: `set.new` sorting unsorted input and binary-search membership
  (`has`); size (`#`); duplicates kept; the empty-set and empty-string-member
  edges; and the raise on a non-string member. For the labeled flavor:
  `set.labeled` mapping members to labels and `match` returning the bitwise OR
  over the matching suffix hierarchy (0 on a miss); members that suffix one
  another; a label crossed as a bitmask on the Lua side; labels across the 32-bit
  range; the empty and empty-string-member edges; and the raises (non-string
  member, label outside [1, 2^32)).

### skb

- **connmark**: a `LOCAL_OUT` netfilter hook exercises `skb:connmark` (get/set)
  on a tracked UDP flow — an overwrite, a Lua-composed masked set that preserves
  out-of-mask bits, and a clear — cross-checked in the conntrack table with
  `conntrack -L`; a second `notrack`'d flow asserts `connmark` returns nil for
  read and write without conntrack. Conntrack is engaged via an nft `ct state`
  rule; skips cleanly if `nf_conntrack` is unavailable.

### socket

- **setsockopt**: `socket:setsockopt()` sets an integer option (`SO_RCVBUF`)
  and a packed struct option (`SO_RCVTIMEO_NEW` built with the `timeval`
  layout codec); with the receive timeout set, a receive with no data returns
  (raises) instead of blocking forever.

- **packet**: the AF_PACKET address a `socket:send()` with a destination builds.
  A `SOCK_DGRAM` send on loopback names the protocol and the interface, and the
  kernel reads the rest of `struct sockaddr_ll` from the same storage: the frame,
  read back on a `SOCK_RAW` socket bound to the same ethertype, must carry as its
  destination hardware address the zeros the binding declares. The same frame
  pins the protocol `socket.new` takes, which reaches `packet_create` as a
  `__be16`: an unbound socket created with the ethertype in network order
  receives it, one created with it in host order does not.

- **address**: what `getsockname()`, `getpeername()` and `receive(..., true)`
  answer with, per family. The kernel reports how many bytes it filled and the
  answer is those bytes: 16 for an AF_PACKET socket bound to loopback, 10 for an
  unbound one, 18 for a received frame and 26 for an AF_INET6 socket, each
  unpacked field by field, against the 126 of the whole storage. AF_INET and
  AF_NETLINK guard the arms that answer with integers, an unconnected
  `getpeername()` is refused with `ENOTCONN`, and a connected TCP socket, which
  names no sender, answers with the message alone. The AF_PACKET and AF_INET6
  cases skip where the kernel does not carry the family.

- **connect**: which argument `socket:connect()` reads as its flags. An AF_INET
  address is spelled as two arguments, so a call with no flags must not have its
  port read as one: the test connects to port 6922, whose value carries the
  `O_NONBLOCK` bit, and a port read as flags answers `EINPROGRESS` instead. A flag
  given past the port must still reach the kernel, and an AF_UNIX path, spelled as
  one argument, must not have the path itself read as the flags.

- **orphan**: a socket holds its network namespace for as long as the kernel
  keeps the socket, not only for as long as the script does. A TCP socket closed
  with its FIN unanswered stays in the kernel as an orphan, retransmitting the
  FIN on a timer until `net.ipv4.tcp_orphan_retries` gives up. The script opens
  a listener and a client over the loopback of a namespace of the test's own,
  where an nft rule drops every FIN and RST, connects and accepts, kills the
  last task in the namespace, whose name the test already deleted, and closes
  the sockets. The veth end the test left in the initial namespace still exists
  once the script is stopped, since the two orphans hold the namespace, and goes
  once the retries run out and the kernel frees them (skips without `nsenter`,
  `nft`, network namespaces or veth; on a kernel where `socket.new` refuses a
  task's namespace with `EOPNOTSUPP`, the three cases skip on that message).

- **rtnl**: what a socket refuses under RTNL, probed from the replay of a
  `notifier.netdevice` registration: a `netlink.rt` request, whose rtnetlink
  handler runs on the sending task and takes RTNL; a receive on a netlink
  socket, which can continue a dump under RTNL; and an option past
  `SOL_SOCKET`, which reaches the protocol, whose multicast memberships take
  RTNL. A `SOL_SOCKET` option and a UDP send are accepted there, and the
  request is accepted once the registration returned. A close runs the release
  on the calling task, so from the replay a UDP socket with no membership
  closes, by `close()`, by a `<close>` local going out of scope, and by both
  on one socket, the second a no-op; an
  `AF_PACKET` socket, a `NETLINK_GENERIC` one, a UDP socket that joined a
  multicast group before the registration and an `AF_INET6` one that joined an
  IPv4 group through `SOL_IP`, whose release ends in `inet_release`, are
  refused, the last two skipped where no group can be joined; the bind of a
  generic netlink socket to a group is refused and of an rtnetlink one
  accepted; and every socket the callback leaves open is closed once the
  registration returned. A tree without the
  refusal wedges the host, so the test skips unless the loaded `luanotifier`
  lists `luanotifier_netdevice_call`, which sets the task the refusal reads, in
  `/proc/kallsyms`, and unless the loaded `luasocket`, whose refusal has no
  symbol of its own, is the installed one; the request is sent only once the
  receive, which cannot wedge, was refused by the `luasocket` that is loaded.

- **unix/stream**: `socket.unix` STREAM server (bind/listen/accept) and
  client (connect/send/receive), both using the path stored at
  construction.

- **unix/dgram**: `socket.unix` DGRAM server (`receivefrom` with
  `DONTWAIT`) and client (`sendto` using the stored path).

- **unix/abstract**: AF_UNIX names in the abstract namespace (a leading NUL).
  `/proc/net/unix` publishes the whole registered name, so the characters it
  prints pin the address a bind declares: the name the script gave, and the
  longest one `UNIX_PATH_MAX` admits. Also the refusals — a second bind of one
  name, a name past `UNIX_PATH_MAX`, and the empty name, which autobinds and
  connects to nothing — and, where `python3` is available, a userspace peer
  connecting to the bound name, and a lunatik client reaching by connect and by
  send the names that peer bound.

- **unix/address**: the AF_UNIX name `getsockname()`, `getpeername()` and
  `receivefrom()` answer with. The kernel counts a pathname's terminator and an
  abstract name's bytes alone, so a pathname comes back as the script spelled it, an
  abstract name keeps its leading NUL, an autobound one is the NUL and the five
  hexadecimal digits the kernel picked, and an unbound socket is the empty string.
  `getpeername()` answers with those same names read across a connection, and a
  connected stream, unlike TCP, names its sender whenever that peer bound. A receive
  from a peer the kernel names no address for answers with the message alone.

### struct

- **test**: the `struct` codec derives a `string.pack` format from a layout
  descriptor — inter-field padding, signed fields, trailing pad, and
  out-of-order fields — with a pack/unpack round-trip, `fieldsize` reporting
  a named field's width, and the overlapping-fields (union) guard.

### task

Covers the `task` module (`luatask`).

- **task**: `task.current()` returns a usable task object from process
  context; `comm()` reports the caller's command name (`lunatik`, the CLI
  process that issues the script via the device's `write(2)` callback);
  `pid()`/`tgid()` are positive and match for the single-threaded caller;
  `prio()` stays within the kernel's dynamic priority range; `cpu()` returns
  a valid CPU index associated with the task; and independent `current()`
  calls agree and remain usable across garbage collection of another reference.
- **softirq**: `task` loads in a softirq-flagged runtime and
  `task.current()` allocates correctly using the class's softirq-safe
  allocation flags, without crashing the kernel.

### tc

Regression tests for `luatc`. The suite builds real TC/eBPF programs that call
`bpf_luatc_run`, attaches them with `tc` on the egress of a veth pair
whose peer sits in a network namespace, with the neighbor entries pinned so
ARP never competes with ICMP for the verdict; skipped when the module lacks
BTF, or `bpftool`, `clang` or `tc` is unavailable. The pass, drop and reattach
cases also fail on a "no callback attached" line: `tc.attach` detaches whatever
was bound before, and a first attach, which finds nothing, logs nothing.

- **tc pass**: the callback inspects `ctx:skb()` (IPv4 ethertype and the
  ICMP protocol byte of the ping) and `ctx:argument()` (a magic word the
  eBPF program passed through), and `action.ACT_OK` lets the packet reach
  its destination; the runtime is plain, covering the plain-name kfunc lookup.
  Every callback that reads the packet acts only on the ping, through the
  suite's `packet.isping`, since the namespace emits autoconf traffic of its own.

- **tc drop**: `action.ACT_SHOT` blocks the ping; the runtime is percpu,
  covering the dispatch to a percpu runtime.

- **tc reattach**: the script attaches one callback and then a second in the
  same runtime; the ping passes because only the last callback runs, exercising
  the re-attach path.

- **tc detach**: the callback drops the first ping and calls `tc.detach()`
  from inside the callback, letting other traffic through; traffic resumes
  because `bpf_luatc_run` then returns `-1` and the eBPF program falls back
  to `TC_ACT_OK`, and the kfunc, which reaches the runtime with nothing
  attached, reports "no callback attached".

- **tc attach**: `tc.attach` refuses a sleepable runtime with "runtime
  context mismatch".

- **tc zero-key**: an eBPF program calling `bpf_luatc_run` with a
  zero-sized key (which the verifier accepts) is rejected in the kfunc
  instead of underflowing the length into an out-of-bounds access. The program
  drops on rejection, so a working guard blocks the ping, proving the
  kfunc ran and returned without crashing.

### thread

Regression tests for `luathread`.

- **shouldstop**: `thread.shouldstop()` returns `false` in a `run`
  (non-kthread) context without crashing, and `true` in a `spawn`
  (kthread) context when stop is requested.

- **rtnl**: `thread:stop()` from a netdevice callback is refused, probed from
  the replay of a `notifier.netdevice` registration by a spawned driver, since
  a thread is started from a thread: the stop waits for the body, and a body
  may wait on the RTNL that task holds. The stop is accepted once the
  registration returned. The body polls `shouldstop` and takes no
  RTNL, so a build without the refusal accepts the stop from the callback and
  fails the assertion rather than hanging; the test runs on any build.

- **foreign_object**: `thread.run()` refuses an object of another class
  instead of using its private data as a Lua state.

- **run_args**: `thread.run()` passes its extra arguments, which must be
  Lunatik objects, to the function the script returned, in the order they
  were given: the body receives a `fifo` and a control block, and pushes a
  marker through the fifo once it reads the driver's token in the control
  block. A number in their place is refused with "invalid object" and a
  `SINGLE` object with "cannot share SINGLE object", neither reaching the
  runtime, which the run that follows proves still usable; a runtime already
  stopped is refused with "stopped runtime"; and a second run carries more
  objects than `LUA_MINSTACK`, which the body sees in order.

- **run_during_load**: `runner.spawn()` called from a script's top-level
  code must error instead of hanging the kernel, and leave the runtime it
  created unregistered.

- **name**: the name `thread.run()` is given reaches the kernel task as
  written, conversions included, instead of being taken as the format.

- **task**: `thread:task()` returns a `task` object: a usable one for
  `thread.current()` (`pid`, `comm`, `tgid`); for a spawned thread, reached
  through `lunatik._ENV.threads`, one reporting that thread (its `comm` is the
  thread name, its `pid` is not the caller's); and for a thread whose body has
  returned, one still reporting that thread, since `thread.run` holds a
  reference to the task until the thread object is collected. Stopping that
  exited thread leaves no kernel complaint, and the object `task()` returns
  after the stop has no task: its methods raise.

### xdp

Regression tests for `luaxdp`. The suite builds real XDP programs that call
`bpf_luaxdp_run`, pins them via `bpftool` and attaches them to a veth pair
whose peer sits in a network namespace, with the neighbor entries pinned so
ARP never competes with ICMP for the verdict; skipped when the module lacks
BTF, or `bpftool` or `clang` is unavailable. The pass, drop and reattach cases
also fail on a "no callback attached" line: `xdp.attach` detaches whatever was
bound before, and a first attach, which finds nothing, logs nothing.

- **xdp pass**: the callback inspects `ctx:packet()` (IPv4 ethertype and the
  ICMP protocol byte of the ping) and `ctx:argument()` (a magic passed by the
  eBPF program), and `action.PASS` lets the packet reach its destination; the
  runtime is plain, covering the plain-name kfunc lookup.

- **xdp drop**: `action.DROP` blocks the ping; the runtime is percpu,
  covering the dispatch to a percpu runtime.

- **xdp reattach**: the script attaches one callback and then a second in the
  same runtime; the ping passes because only the last callback runs, exercising
  the re-attach path.

- **xdp detach**: the callback drops the first ping and calls `xdp.detach()`
  from inside the callback, letting other traffic through; traffic resumes
  because `bpf_luaxdp_run` then returns `-1` and the eBPF program falls back
  to `XDP_PASS`, and the kfunc, which reaches the runtime with nothing
  attached, reports "no callback attached".

- **xdp attach**: `xdp.attach` refuses a sleepable runtime with "runtime
  context mismatch".

- **xdp zero-key**: an eBPF program calling `bpf_luaxdp_run` with a
  zero-sized key (which the verifier accepts) is rejected in the kfunc
  instead of underflowing the length into an out-of-bounds access. The program
  drops on rejection, so a working guard blocks the ping, proving the
  kfunc ran and returned without crashing.

- **xdp process**: a process-context runtime registered under the key of an
  eBPF program is refused by the kfunc, which logs it and leaves the verdict
  to the program, instead of taking the runtime's mutex in softirq.

- **xdp percpu**: with the ping pinned to the last online CPU, which is where
  the veth runs the receive softirq, the callback of a percpu script reports
  that CPU as its own id, and no other; skipped on a single CPU.

