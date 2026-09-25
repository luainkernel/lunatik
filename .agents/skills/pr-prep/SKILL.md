---
name: pr-prep
description: Prepare a branch for a pull request and draft its title and body. Use when a branch is ready for a PR or when asked for a PR title and description.
---

Run AGENTS.md, "Before opening a pull request" (every item) and the pull request prose rule
under "Patches and commits": title and body say what and why, nothing the commits already say,
no "Test plan" section, no em dashes. On top of it:

- A fix answers a finding a script using the API as documented reaches; one whose stimulus is a
  script out of contract (AGENTS.md, "Deciding what to change") closes as not a defect instead.
- When a doc block, `@type`, `@treturn` or `config.ld` changed, run `make doc-site LUA=lua5.5`, the
  CI target, and read its exit status: LDoc quits on a module it cannot place with a line that
  says neither "warning" nor "error", so a grep for those passes a failed run. Then check the links
  land on types, not functions.
- Compare `git diff` against `git diff -w` for stray whitespace; `bash tools/checks/pre-commit`
  covers the trailing blank line on staged files.
- `bash tools/checks/idioms.sh` over the C files the diff touches, and
  `bash tools/checks/author-email.sh origin/master..HEAD` over the branch after any rebase or
  squash, which signs the result with the checkout's own identity.
- Fixup commits stay unsquashed unless squashing was explicitly requested; the maintainer
  reviews them before they are folded.
- Every function the diff touches is re-read whole before the hand-back: is a new branch this
  function's job or its caller's; is a condition with stack juggling a predicate helper; did the
  new shape leave a guard redundant.
- The hand-back lists the findings of your own review the change does not apply, each with its
  reason; none is dropped in silence.
- The hand-back names, for each mechanism the change adds, the smaller shape that was considered
  and why it was not taken; a fix whose smaller shape was never written down is not ready.
- The hand-back carries the test matrix: for each guard or mechanism the change adds, operations
  by types by outcomes, each cell with its test or the reason it is not covered.
- Every example that uses a binding the change touches is run through its own `setup.sh` and
  `cleanup.sh`, and the hand-back says of each whether it ran, only loaded, or was not run, and why.
- The body opens with the failure or the need in one plain sentence, then what the change does,
  then what it depends on: three short paragraphs at most; `bash tools/checks/pr-body.sh <file>`
  before posting it.
- A pull request that finishes a phase of an epic carries `Closes #<phase issue>` on a line of its
  own, and one that finishes none says `#<epic>, which it does not close`: a body that only says it
  is part of the epic, or answers an issue, closes nothing when it merges, and `pr-body.sh` fails it.
- A push, forced or not, is a command of its own, after the rebase before it is read as finished
  in `git status`; chained after one that stopped on a conflict, it publishes the base as the branch.
- After any force-push, re-read the title and body against the branch as it now stands.
- A pull request on another pull request's branch opens as a draft (`-F draft=true`), which GitHub
  will not merge before its base; `stacked-guard.sh` refuses one that does not.

