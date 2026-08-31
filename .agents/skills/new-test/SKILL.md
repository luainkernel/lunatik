---
name: new-test
description: Write or extend a Lunatik KTAP test suite under tests/<suite>/. Use when adding or materially changing tests.
---

The rules are AGENTS.md, "Tests" (shape, dmesg marking, cleanup in a trap, host independence,
the coverage matrix, proving the test discriminates, the docs and run.sh wiring) plus the
exit-0 blind spot under "Running a script". This skill is the mechanics:

- Source `tests/lib.sh` and use `run_script`/`run_test` instead of open-coding the run; they
  fail on any output, which is what catches a script that never loaded. `tests/bpf/run.sh` is
  the reference shape.
- `bash tools/checks/test-harness.sh <file>` flags a harness blind to a failed load.
- Tests are installed by `sudo make install` only (`scripts_install` does not install them);
  run the installed suite with `sudo lunatik test <suite>` (see the lunatik-cycle skill).

