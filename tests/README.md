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
```

Individual test:

```
sudo bash tests/monitor/gc.sh
sudo bash tests/thread/shouldstop.sh
sudo bash tests/thread/run_during_load.sh
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

