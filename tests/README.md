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
`comp`.

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

### fifo

- **bounds**: `fifo.new()` accepts the capacities it serves and refuses
  zero, one (kfifo's own floor), a negative and anything past
  `KMALLOC_MAX_SIZE`, including a value `__kfifo_alloc()`'s `unsigned int`
  truncated into a small fifo; `fifo:pop()` refuses a size past the
  capacity, which it could never return.

### fsnotify

Every mark in this suite goes on `/tmp/lunatik-fsnotify`, created and removed
by the test: a mark outside a scratch subtree is what makes a machine unable to
read its own files. A mount or superblock mark reaches every file it covers, so
the test that places one mounts its own tmpfs there and marks that.

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
  not appear. A mount mark reports a file opened under its mount and reports
  neither a file outside it nor the same inode opened through the other mount;
  a superblock mark reports that same open and nothing on another filesystem;
  an invalid kind raises naming the valid ones. `watch:find` then returns the
  mark of each kind by path and kind, and `nil` for a kind the watch did not
  mark, and the tmpfs is unmounted under all three, which is the path where the
  kernel clears a group's marks on its own before the watch walks them.

- **mask**: a live mark's masks. A mark placed for `FS_OPEN` and set to
  `FS_MODIFY` stops reporting the open and starts reporting the write, which
  separates a recalculated object mask from a field written on the mark alone;
  a second mark carrying both events and ignoring `FS_OPEN` reports only the
  write, so the ignore mask suppresses what it names and nothing else, and a
  read after that write is silent too, so a write does not clear it.

- **marks**: the mark as an object. `watch:find` returns the mark the watch
  placed, `nil` where it has none and `nil` after `remove`, a second mark on
  the same object is refused with `EEXIST`, a removed mark
  delivers nothing while its neighbour still delivers, and `stop` takes every
  mark with it and leaves no usable handle. The whole test runs twice in a row
  and counts the events of each round, so a mark or a group the first round
  leaked shows as a second line rather than passing a presence test.

- **inside**: a mark removed, and a mark's mask set, from inside the callback,
  which runs in fsnotify's SRCU read section and takes the group's mark mutex
  there, the path inotify's one-shot watch takes to destroy its own mark. The
  mark removed on its first event delivers once; the mark set from `FS_OPEN`
  to `FS_MODIFY` on its first event delivers that open once, nothing for the
  read after it, and the write.

- **identity**: the matrix of event kind by accessor. A file open carries a
  `struct path`, so `name`, `ino`, `dir`, `isdir`, `pid` and `path` all answer;
  a directory open is flagged `FS_ISDIR`; a create, a rename and a delete name
  the entry and its directory and carry no path. Each case asserts every
  accessor, the `nil` ones included, against what the shell already knows: the
  inode numbers from `stat -c %i`, the pid from its own `$$`, and the path it
  built. A stimulus the shell performs itself is matched by that pid, so another
  process touching the scratch file cannot be read as it.

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

- **context**: `fsnotify.watch` refuses a callback that is not a function and a
  softirq runtime, and takes a second watch on a runtime that already has one;
  `mark` raises the errno name for a path that does not resolve and refuses a
  permission event. The shell counts the passing cases rather than looking only
  for a failing one, so a case that never ran cannot pass.

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

### monitor

Regression tests for `lunatik_monitor` (spinlock + GC interaction).

- **gc**: a spawned thread uses a `sleep=false` fifo from a `sleep=true`
  runtime; `f:pop()` allocates inside `spin_lock_bh`, forcing GC that
  finalizes a dropped AF_PACKET socket. Must not trigger "scheduling
  while atomic".

### netlink

Tests for netlink: the `AF_NETLINK` address family in `socket`, and the
higher-level `netlink.*` modules built on top of it.

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
  userspace multicast and unicast delivery from softirq (skips without
  `gcc`/`genl`).
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

### notifier

- **context_mismatch**: calling a hardirq-class constructor (e.g.
  `notifier.keyboard`) from a process runtime must error with "runtime
  context mismatch" without oopsing during `__gc`.

- **init_dispatch**: `notifier.netdevice(cb)` at script init must handle
  the synchronous `NETDEV_REGISTER` replay `register_netdevice_notifier`
  performs for existing devices.

- **chain_continues**: a netdevice block whose runtime is being torn down
  returns `notify.DONE`, not the `-ENXIO` of `lunatik_run`, whose
  `NOTIFY_STOP_MASK` bit stopped the chain: a device created while one
  runtime holds its teardown reaches the block a second runtime registered
  after it.

### probe

- **kprobe_concurrent**: registers kprobes on every syscall and runs
  one load generator per CPU; `lunatik stop` must complete within 5s
  with no kernel errors under concurrent handler firings.

### rcu

- **map_values**: `rcu.map()` iterates booleans, integers, userdata,
  mixed types, and skips nil (deleted) entries.

- **map_foreign**: `rcu.map()` refuses an object of another class
  instead of walking its private data as a table.

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

- **percpu_netfilter**: the runtimes of a percpu script share one
  `LOCAL_IN` hook: with the ping pinned to the last online CPU, each marked
  request is counted exactly once, by the runtime of that CPU; a burst that
  reaches the hook while the runtimes are still being created is accepted
  without being counted; one set holds a hook per target, and a second
  registration of the same one in a runtime is refused; a registration from a
  callback, after load, is refused; and the same script registers as a plain
  softirq runtime.

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

- **unix/stream**: `socket.unix` STREAM server (bind/listen/accept) and
  client (connect/send/receive), both using the path stored at
  construction.

- **unix/dgram**: `socket.unix` DGRAM server (`receivefrom` with
  `DONTWAIT`) and client (`sendto` using the stored path).

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
BTF, or `bpftool`, `clang` or `tc` is unavailable.

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
  to `TC_ACT_OK`.

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
  code must error instead of hanging the kernel.

- **task**: `thread:task()` returns a `task` object: a usable one for
  `thread.current()` (`pid`, `comm`, `tgid`); for a spawned thread, reached
  through `lunatik._ENV.threads`, one reporting that thread (its `comm` is the
  thread name, its `pid` is not the caller's); for a thread whose body has
  returned, one whose methods raise instead of dereferencing the gone task.

### xdp

Regression tests for `luaxdp`. The suite builds real XDP programs that call
`bpf_luaxdp_run`, pins them via `bpftool` and attaches them to a veth pair
whose peer sits in a network namespace, with the neighbor entries pinned so
ARP never competes with ICMP for the verdict; skipped when the module lacks
BTF, or `bpftool` or `clang` is unavailable.

- **xdp pass**: the callback inspects `ctx:packet()` (IPv4 ethertype and the
  ICMP protocol byte of the ping) and `ctx:argument()` (a magic passed by the
  eBPF program), and `action.PASS` lets the packet reach its destination; the
  runtime is plain, covering the plain-name kfunc lookup.

- **xdp drop**: `action.DROP` blocks the ping; the runtime is percpu,
  covering the dispatch to a percpu runtime.

- **xdp detach**: the callback drops the first ping and calls `xdp.detach()`
  from inside the callback, letting other traffic through; traffic resumes
  because `bpf_luaxdp_run` then returns `-1` and the eBPF program falls back
  to `XDP_PASS`.

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

