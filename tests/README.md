# Lunatik Tests

Integration tests for lunatik kernel modules. Output follows
[KTAP](https://docs.kernel.org/dev-tools/ktap.html) format.

## Requirements

- Lunatik modules loaded: `sudo lunatik load`
- Lua scripts installed: `sudo make tests_install`
- Root privileges

## Running

All suites:

```
sudo bash tests/run.sh
```

Individual suite:

```
sudo bash tests/monitor/run.sh
sudo bash tests/thread/run.sh
sudo bash tests/runtime/run.sh
```

Individual test:

```
sudo bash tests/monitor/gc.sh
sudo bash tests/thread/shouldstop.sh
sudo bash tests/thread/run_during_load.sh
sudo bash tests/runtime/refcnt_leak.sh
sudo bash tests/runtime/resume_shared.sh
```

## Suites

### monitor

Regression tests for `lunatik_monitor` (spinlock + GC interaction).

- **gc**: GC running under spinlock triggers "scheduling while atomic".
  A spawned thread uses a `sleep=false` fifo from a `sleep=true` runtime;
  `f:pop()` allocates inside `spin_lock_bh`, forcing GC that finalizes a
  dropped AF_PACKET socket.

### thread

Regression tests for `luathread`.

- **shouldstop**: `thread.shouldstop()` must return `false` in a `run`
  (non-kthread) context without crashing, and `true` when stop is requested
  in a `spawn` (kthread) context.

- **run_during_load**: `runner.spawn()` called from a script's top-level
  code (during module load) must error instead of hanging the kernel.

### runtime

Regression tests for `lunatik_newruntime`.

- **refcnt_leak**: module use-count leak when a script errors after a
  successful `netfilter.register()` call.

  `require("netfilter")` creates an LSTRMEM string in the Lua state via
  `__symbol_get("luaopen_netfilter")`.  Each `netfilter.register()` call
  increments the runtime kref (via `lunatik_getobject`), so after one
  successful register the kref is 2.  If the script then errors,
  `lunatik_newruntime`'s error path calls `lunatik_putobject(runtime)`
  (kref 2→1), but never reaches 0 — `lua_close()` is never called.
  The LSTRMEM string is never freed, `symbol_put_addr()` is never invoked,
  and luanetfilter's use-count stays elevated.  `lunatik reload` then fails
  with "Module luanetfilter is in use".

  Fix: in the error path, set `runtime->private = NULL` under the spinlock
  (so any in-flight hook sees NULL and bails), call `lua_close(L)` explicitly
  (GC runs, hook finalizer fires: `nf_unregister_net_hook` +
  `lunatik_putobject` kref 2→1, LSTRMEM freed → `symbol_put_addr` restores
  refcnt), then `lunatik_putobject(runtime)` kref 1→0 → `kfree`.

- **resume_shared**: `runtime:resume()` must correctly pass shared (monitored)
  objects across runtime boundaries. Pushes a value into a shared `fifo`,
  passes it to a sub-runtime via `resume()`, and asserts the value can be
  popped.

