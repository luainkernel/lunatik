---
paths:
  - "**/tests/**"
---

# Tests

Tests are shell scripts emitting KTAP plus a kernel side Lua script.

* the description of what a test does goes in the `.sh`. The `.lua` gets one line pointing back at it;
* skip, do not fail, when the kernel lacks a required config;
* mark `dmesg` before the run, read only what came after, and `check_dmesg` at the end;
* clean up in a `trap`, and run the cleanup once up front as well;
* the cleanup undoes everything any case can create, not only what the happy path stops inline: a case
  that fails before its own teardown leaves its runtime registered, and the next run finds it already
  there. A new case extends the cleanup in the commit that adds it, so the up-front run clears the
  leak and a green formal test stays authoritative;
* a test that guards a kernel crash is not proved by removing the guard: that reproduces the crash,
  and on the shared host it is a forced reboot. Its discrimination rests on the message it asserts.
  An experiment that does remove a guard is authorized by the maintainer beforehand, names the
  machine it may take down, and runs after the commit it is meant to prove; `crash-guard.sh` blocks
  the install or run until `CRASH_AB_OK=1` says that happened. Removing a guard is the experiment,
  not running the fix: building and running a tree that adds or restores one is the ordinary cycle
  and asks nobody;
* the message a crash test asserts is read from the kernel that prints it, not from a generic error
  pattern: `check_dmesg` matched `WARNING` and `UBSAN` and no oops at all, so the kprobe crash of
  #843 killed the probed task and left the suite green. arm64 heads an oops with `Internal error:`
  (`arch/arm64/kernel/traps.c`) and an unclaimed debug trap with `Unexpected kernel BRK exception at
  EL1` (`debug-monitors.c`);
* a case tears down before it reads its verdict: every program it attached, pin it made and script it
  started is undone before the first check, so a failing check leaves nothing for the next case to
  trip on. A case that returns from a check with its program still attached turns one failure into
  one per case after it;
* a test does not depend on what else runs on the host: when a host process — a network manager, say
  — can race it by acting on a resource the test created, make the test robust to any such process,
  not wired to silence one by name, which does not carry to another distro or to CI;
* a case pins a refusal the API makes, never a capability it gave up: a notifier narrowed to the
  initial namespace came with a case asserting that a device of another namespace is not reported,
  so a lost capability became the contract and restoring it has to delete a green test;
* coverage means the matrix of operation by type by outcome, including the successes, not a list of
  features and not only the error paths;
* prove the test discriminates: disable the mechanism it covers, watch it fail, restore. Commit
  first, since restoring is a `git checkout --` that takes any uncommitted work with it. The defective
  side has to compile: a header reverted while its callers still pass the argument it drops stops at
  `too many arguments`, the suite then runs against the modules already installed, and that green run
  reads as a test that does not discriminate. The proof is run, not argued: a message the header
  says `check_dmesg` reads is one `KTAP_ERRORS` in `tests/lib.sh` matches, and the line the
  defective build prints is one that build printed. `tests/rcu/entry_release` said `check_dmesg`
  would read the BUG line of a sleep under the table's lock, which the pattern does not carry and
  the case never provokes, and proved nothing until a kprobe read where each release ran;
  `tools/checks/test-harness.sh` names a claimed message the pattern does not match;
* a test that wedges the host when the fix is absent, rather than failing, checks before its stimulus
  that the loaded module carries the fix, by a symbol only the fixed build has in `/proc/kallsyms`,
  or, where the check is inline and has no symbol, by its message read from the module file
  (`grep -aF "$REFUSAL" "$(modinfo -n <module>)"`), and skips when it does not: `lunatik reload`
  refuses a module it could not replace, but a test run by hand runs against whatever is loaded. A
  comparison of `srcversion` alone proves that the loaded module is the installed file and nothing
  about the file, so a checkout ahead of its install runs the case against the old module; the
  deferred unregistration of a netdevice notifier was first exercised against the build without it,
  and `tests/runtime/self_stop` first skipped on `srcversion`, copied from a sibling.
  `tools/checks/test-harness.sh` names a skip that reads `srcversion` and nothing else;
* a case whose stimulus the defective build would wait on forever asks first for a value that build
  gets wrong and returns from, so the discrimination proof fails there instead of hanging the cycle:
  #1757's timeout cases ask for `2^32` plus a few milliseconds, which a build without the bound
  truncates and waits briefly on, before `-1`, which it reads as forever;
* a case whose stimulus only exists on a busy machine is forced, not waited for: the probe test picks a
  syscall an idle host never makes, which is why it never hit the creation window that crashed the host,
  and covering that window meant pinning the call to the CPU whose runtime is published last. A test
  that passes because the race is rare is not covering the race;
* a test for an exactly once property runs on the path where that property is structural, and the
  header says which path and why. The same assertion on a path that can migrate CPUs mid way passes
  for the wrong reason.

A test is not done until `tests/README.md` describes it and the suite's `run.sh` runs it, a new suite
included. Same commit, or a fixup of it.

