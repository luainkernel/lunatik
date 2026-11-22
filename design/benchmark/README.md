# Benchmark: what the 5.x series costs against v4.4.1

The plan for #1761. Read at Lunatik master `2ccc0a2eb`, against the tags `v4.4.1` (`f0482c4eb`),
`v5.0` (`461a1d104`) and `v5.1` (`e9b48135f`), and at the kernel this host runs, Ubuntu HWE 6.8.12
(`6.8.0-138-generic`, aarch64). Nothing here is code.

## Why

v5.0 changed the paths a hook, a method and a `require` run through, and v5.1 changed the one every
monitored method runs through. Nobody measured what either cost: a cost claim in a review is a
measurement (AGENTS.md), and the tree has no tool to take one. The 5.2 work changes these paths again,
and a pull request that touches them has nothing to compare its numbers with.

## Expected results

1. One command measures a ref: it builds the ref in a worktree of its own, installs it, runs the
   benchmark set, and reinstalls the tree it was launched from, writing a CSV per round with the ref,
   the kernel, the load and the time.
2. The cost of one call made from Lua, in ns per operation, in a process runtime and in armed
   softirq and hardirq ones, for each operation `plan.md` lists.
3. The cost of an event seen from outside: packets per second through a netfilter and an XDP hook,
   the time a `getppid` takes with a kprobe on it against without, the creation and the stop of a
   runtime, and a percpu script against one runtime on the same hook.
4. The footprint: each module's text and data, and the memory a runtime and an object hold.
5. A report of v4.4.1, v5.0 and v5.1 with the median and the spread of each number. Every
   difference past the spread becomes an issue with its number, and the v5.1 numbers are the
   baseline a 5.2 pull request on these paths measures against.

## Decided

Taken with the maintainer on 2026-10-15:

- three versions, v4.4.1, v5.0 and v5.1, so that each difference is attributed to the release that
  made it, v5.1 having changed the monitored method;
- one script per operation, with a table of names per API generation resolved before the timed
  loop, so the text measured is the same in the three versions;
- the benchmark lives in `tools/bench/`, a driver and the scripts it installs itself under
  `/lib/modules/lua/bench/`, outside `make install`, since it installs other refs and passes or
  fails nothing;
- #1761 is the epic, with one issue per phase.

## Phases

| Phase | What it delivers | Expected result |
|-------|------------------|-----------------|
| 1 | the driver, the statistics and the footprint | 1, 4 |
| 2 | the per-call set | 2 |
| 3 | the event set | 3 |
| 4 | the run over the three refs and the report, no code | 5 |

Phases 2 and 3 build on the driver's interface and not on each other. `plan.md` holds the method,
the operations with the commits each one measures, and what each phase is held to; `kernel-notes.md`
holds the kernel facts the method rests on, each with the line it was read at.

