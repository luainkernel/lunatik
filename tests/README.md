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

### crypto

Covers the `crypto` module: `shash`, `skcipher`, `aead`, `rng`, `hkdf`,
`comp`.

### io

- **test**: kernel `io` library (open/read/write/seek/lines/type); also
  asserts `io` is absent from softirq runtimes.

### monitor

Regression tests for `lunatik_monitor` (spinlock + GC interaction).

- **gc**: a spawned thread uses a `sleep=false` fifo from a `sleep=true`
  runtime; `f:pop()` allocates inside `spin_lock_bh`, forcing GC that
  finalizes a dropped AF_PACKET socket. Must not trigger "scheduling
  while atomic".

### notifier

- **context_mismatch**: calling a hardirq-class constructor (e.g.
  `notifier.keyboard`) from a process runtime must error with "runtime
  context mismatch" without oopsing during `__gc`.

- **init_dispatch**: `notifier.netdevice(cb)` at script init must handle
  the synchronous `NETDEV_REGISTER` replay `register_netdevice_notifier`
  performs for existing devices.

### probe

- **kprobe_concurrent**: registers kprobes on every syscall and runs
  one load generator per CPU; `lunatik stop` must complete within 5s
  with no kernel errors under concurrent handler firings.

### rcu

- **map_values**: `rcu.map()` iterates booleans, integers, userdata,
  mixed types, and skips nil (deleted) entries.

- **map_sync**: `rcu.map()` remains safe when called while another
  kthread is modifying the table.

### runtime

Regression tests for `lunatik_newruntime` and cross-runtime plumbing.

- **refcnt_leak**: module use-count leak when a script errors after a
  successful `netfilter.register()` call. The fix, under the runtime
  spinlock, nulls `runtime->private`, calls `lua_close(L)` to fire the
  hook finalizer (`nf_unregister_net_hook` + `symbol_put_addr`), and
  then releases the runtime.

- **resume_shared**: `runtime:resume()` passes shared (monitored) objects
  across runtime boundaries. Push into a shared `fifo`, resume a
  sub-runtime with it, assert the value pops on the other side.

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

### socket

- **unix/stream**: `socket.unix` STREAM server (bind/listen/accept) and
  client (connect/send/receive), both using the path stored at
  construction.

- **unix/dgram**: `socket.unix` DGRAM server (`receivefrom` with
  `DONTWAIT`) and client (`sendto` using the stored path).

### thread

Regression tests for `luathread`.

- **shouldstop**: `thread.shouldstop()` returns `false` in a `run`
  (non-kthread) context without crashing, and `true` in a `spawn`
  (kthread) context when stop is requested.

- **run_during_load**: `runner.spawn()` called from a script's top-level
  code must error instead of hanging the kernel.
