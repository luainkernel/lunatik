---
name: pr-prep
description: Prepare a branch for a pull request and draft its title and body. Use when a branch is ready for a PR or when asked for a PR title and description.
---

Run AGENTS.md, "Before opening a pull request" (every item) and the pull request prose rule
under "Patches and commits": title and body say what and why, nothing the commits already say,
no "Test plan" section, no em dashes. On top of it:

- When a doc block, `@type`, `@treturn` or `config.ld` changed, run `make doc-site LUA=lua5.4`, the
  CI target, and read its exit status: LDoc quits on a module it cannot place with a line that
  says neither "warning" nor "error", so a grep for those passes a failed run. Then check the links
  land on types, not functions.
- Compare `git diff` against `git diff -w` for stray whitespace; `bash tools/checks/pre-commit`
  covers the trailing blank line on staged files.
- Fixup commits stay unsquashed unless squashing was explicitly requested; the maintainer
  reviews them before they are folded.
- Every function the diff touches is re-read whole before the hand-back: is a new branch this
  function's job or its caller's; is a condition with stack juggling a predicate helper; did the
  new shape leave a guard redundant.
- The hand-back lists the findings of your own review the change does not apply, each with its
  reason; none is dropped in silence.
- The hand-back carries the test matrix: for each guard or mechanism the change adds, operations
  by types by outcomes, each cell with its test or the reason it is not covered.
- Every example that uses a binding the change touches is run through its own `setup.sh` and
  `cleanup.sh`, and the hand-back says of each whether it ran, only loaded, or was not run, and why.
- The body opens with the failure or the need in one plain sentence, then what the change does,
  then what it depends on: three short paragraphs at most; `bash tools/checks/pr-body.sh <file>`
  before posting it.
- After any force-push, re-read the title and body against the branch as it now stands.

