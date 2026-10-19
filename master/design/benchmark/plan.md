# Plan

## What each version changed on the paths measured

Read in each commit at the tags of `README.md`. The set column names the phase whose numbers cover
the path.

| Path | Release | Commits | Set |
|------|---------|---------|-----|
| the lock a dispatch takes, with its holder recorded on every acquire | 5.0 | 5a8ae5a82, d9745a8b7 | call, event |
| a softirq object reached with IRQs off locks with irqsave | 5.0 | f5276dfcd | call (hardirq) |
| a wait on a runtime's lock that a stop or a fatal signal ends | 5.0 | b64c6f99d | call (resume) |
| the ready flag and the CPU read from `lunatik_runtime_t` | 5.0 | 43cb3a6fd | event |
| one protected handler per callback, through `lunatik_cpcall` | 5.0 | d17646445, 3654ad640 | event |
| a dispatch refused from under the runtime's own lock | 5.0 | 9ff8de9cf | event |
| percpu runtimes, which 4.x does not have | 5.0 | 77323aa4c, 1928cac49 | event |
| `rcu.foreach` takes an entry's reference inside its protected call | 5.0 | 45958419b | call |
| skb's data views, one per layer, emptied after each callback | 5.0 | 10fe3e155 | event |
| a monitored method allocates with the object's gfp under its lock | 5.0 | f9afbafab | call |
| `data`'s `__tostring` under the object's lock | 5.0 | c4120a639 | call |
| the monitor clears a call or return hook around the method, and restarts the collector only if it was running | 5.1 | fc740745a, cd231006a, 55d9f3270 | call |
| a recursion through C priced against a byte budget of the kernel stack | 5.0 | 03e208b66 | call |
| an object holds its class's module, is released on a worker from atomic context, and its memory outlives the grace period | 5.0 | f758115df, 63d0bbeca, e259bd836 | call |
| a clone creates its class's metatables | 5.0 | 441811b98 | call (resume) |
| `rcu.table`: a number key as its decimal string, the cycle check on storing a table, walks inside an SRCU read side | 5.0 | b96f2c42f, 70d70de12, 7595e4008 | call |
| `require`: the C searcher ahead of the Lua one, and the searchers through `lunatik_callsleepable` | 5.0 | 09a1e3ef1, dfdea8636 | call |
| the range checks of integer setters and accessors | 5.0 | 826ed306f, 8d3ac4403, 7c98a66a4 | call, event |
| Lua 5.5.0 to 5.5.1 | 5.0 | f09a808b1 | under every number, not isolated |

`hid`'s report closed after `raw_event` (e81ca3e6e) is not in either set: it needs a HID device as
the event source, which the driver does not have.

## Method

**A per-call number** is the time of a loop of N calls, taken with `linux.time` before and after,
minus the time of the same loop with the call removed, divided by N. N is calibrated so the loop takes
10 ms or more where the context allows it. The loop runs in three places:

- process: the script body, in the task of the `lunatik run` that the driver pins with `taskset`;
- softirq: a netfilter `PRE_ROUTING` callback of a softirq runtime, fired by a packet the driver
  injects (`kernel-notes.md`, pktgen);
- hardirq: a kprobe handler of a hardirq runtime on `getppid`, fired by `perf bench syscall basic`;
  the runtime holds its lock with interrupts off (AGENTS.md, Execution contexts), so each hit times a
  loop of 1 ms or less and the samples of many hits aggregate.

**An event number** is read from outside: pktgen's packets per second, and `perf bench syscall
basic`'s time per call, each without the hook and with it, the difference being the hook's cost per
event.

**Repetition.** A batch is 30 samples of one operation in one context on one ref. A round installs the
three refs one after the other and runs every batch on each, and the rounds rotate the order of the
refs (v4.4.1, v5.0, v5.1; then v5.0, v5.1, v4.4.1; then v5.1, v4.4.1, v5.0), so the host's drift
shows as a difference between rounds and not between refs. There are three rounds or more. A batch
records the 1-minute load before and after it; one above 1.0, a CPU of six busy, is left out of the
report and named there. A difference between two refs counts when it has the same sign in every round
and exceeds the larger interquartile range of the two.

**Names across versions.** Each operation is one script. What it calls by a name that differs between
the API generations, a module, a function, a constant, comes from a table per generation (v4.4.1,
v5.0, v5.1), resolved into locals before the timed loop, so the loop is the same text on the three
refs. An operation a ref cannot run, percpu on v4.4.1, is skipped there, and the report says so.

## Phase 1: the driver, the statistics and the footprint

The driver is run under `tools/lunatik-host` with the refs to measure, the sets to run, the number of
rounds and a work directory for the worktrees and the output. It is held to:

- each ref is built in a worktree of its own, with its submodules, by its own Makefile, and
  installed in place of what is installed, nothing a previous ref installed left behind;
- the benchmark scripts of the ref's API generation are installed under `/lib/modules/lua/bench/`;
- the host ends as it began, the tree the driver was launched from installed and loaded, whether the
  run ends, fails or is interrupted;
- a round writes a CSV, one line per sample: ref, round, set, operation, context, N, ns, the load
  before and after, the kernel and the time; and a summary gives the median and the interquartile
  range per ref, operation and context.

The footprint set reads `size` of each module of the ref, the Lua heap of an empty runtime in each
context (`collectgarbage("count")`), and the kernel memory of a number of empty runtimes from
`/proc/slabinfo` (`kernel-notes.md`, slab).

Done when the footprint set runs over v4.4.1 and v5.1 on this host, a run interrupted with SIGINT
leaves master installed, and `sudo lunatik test` passes after either.

## Phase 2: the per-call set

| Operation | Contexts |
|-----------|----------|
| the empty loop, the floor every other number is read against | process, softirq, hardirq |
| a get and a set of an integer on a `data` buffer in its default, monitored mode | process, softirq, hardirq |
| `tostring` of that buffer | process, softirq |
| a call to a C function | process, softirq, hardirq |
| `rcu.table`: a get and a set with a number key and with a string key, a store of a table, a `foreach` over a table of 64 entries | process, softirq, hardirq |
| the creation of an object and its collection | process, softirq |
| a `resume` of another runtime handed an object | process |
| a `require` of a module already loaded, C and Lua, and the first `require` of each | process |

Done when each operation has its numbers on v4.4.1, v5.0 and v5.1 in each of its contexts, or a line
saying why a ref cannot run it.

## Phase 3: the event set

- netfilter: pktgen injects into one interface, on one CPU (`kernel-notes.md`, pktgen); packets per
  second without a hook, with a Lua `PRE_ROUTING` hook that accepts, with one that reads the skb, and
  with a percpu script of the same hook on the 5.x refs;
- XDP: the same injection through a generic XDP program that calls into Lua, packets per second with
  and without it;
- kprobe: `perf bench syscall basic`, pinned, time per call without a probe and with a Lua kprobe on
  the architecture's `getppid` entry (`kernel-notes.md`, kprobe);
- a runtime's life: the time from userspace of a `lunatik run` and a `lunatik stop` of an empty script,
  in process and in softirq.

Done when each event has its numbers on v4.4.1, v5.0 and v5.1.

## Phase 4: the run and the report

Three rounds or more over the three refs, run when the host is quiet. `results.md` beside this file
gives, per operation and context, the median and the interquartile range of each ref and the
difference from one release to the next, with the batches left out and why. Each difference that
counts becomes an issue with its number, and the report names it.

## Not covered

- x86_64: the host is aarch64; a number from another host is another report.
- The CI: a GitHub runner gives no stable time.
- A binding outside these paths: one whose hot path a later change touches adds its operation to a
  set in that change.

