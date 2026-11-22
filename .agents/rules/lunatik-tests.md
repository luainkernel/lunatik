---
paths:
  - "**/tests/**"
---

# Tests of Lunatik

Beside `harness/.agents/rules/tests.md`:

* a case that carries an object to a runtime of another context, by a clone or an `rcu.table`, calls
  its methods there: one that receives it and calls nothing proves the route and not the use, as
  `tests/runtime/require_cloneobject` does on #2378 of the `crypto` classes it lets into a softirq
  runtime;
* a test that wedges the host when the fix is absent, rather than failing, checks before its stimulus
  that the loaded module carries the fix, by a symbol only the fixed build has in `/proc/kallsyms`,
  or, where the check is inline and has no symbol, by its message read from the module file
  (`grep -aF "$REFUSAL" "$(modinfo -n <module>)"`), and skips when it does not: `lunatik reload`
  refuses a module it could not replace, but a test run by hand runs against whatever is loaded. A
  comparison of `srcversion` alone proves that the loaded module is the installed file and nothing
  about the file, so a checkout ahead of its install runs the case against the old module.
  `tools/checks/test-harness.sh` names a skip that reads `srcversion` and nothing else.

