---
name: implement-issue
description: Implement a Lunatik issue through agents, from the issue to a reviewed pull request. Use when asked to implement an issue with a workflow, or to dispatch an agent to one.
---

AGENTS.md is the authority; `implement.js` beside this card is the workflow that orders the work:

        Workflow({scriptPath: '<checkout>/.agents/skills/implement-issue/implement.js',
              args: {issue: <N>, effort: '<effort>', scratch: '<absolute dir>', repo: '<checkout>',
                     notes: '<the session's words>', machine: '<how this machine gets root and gh>'}})

- The implementer traces the issue, writes the smallest shape down before any other, commits and
  pushes what builds as it goes, and drafts the pull request's title and body; it runs nothing on the
  host. Its answer's `smallest`, the shape beside the size of the diff and what each
  mechanism past it buys, goes to the review, and the hand-back of the pull request carries it with
  the reviewer's own reading. Its prompt names the rule each step needs and restates none, since every
  agent loads AGENTS.md and the machine's CLAUDE.local.md; what belongs to the machine, a credential or how
  it gets root, stays in the latter, and `machine-leak.sh` keeps it out of the tree.
- Before a launch the session runs `tools/issue-since.sh <N>`, which lists the commits master took since the
  issue was opened that touch the files it names, and reads them against the issue: one a commit already
  answers, the case it says no test covers since added, closes with that commit named, and no agent is
  launched on it. Four issues of the 2026-11-04 batch, each saying a case was missing, reached their
  groomers that way, the cases having landed days after the issues were filed. A groomer's `decline` that
  shows an issue a workflow filed answered, or its premise false, closes it the same way, with the trace
  as its comment and no decision brought to the maintainer, who ordered it so that day.
- `notes` carries what only the session knows: what the maintainer asked for, what was already traced,
  what the issue leaves out. A rule pasted there is a copy of AGENTS.md its next change does not reach.
  A shape of the API the session settled after filing goes into the issue, under an `Update:` line, before the
  launch, and the notes never restate it: the implementer reads both, and where they differ the review
  hands the difference back as a decision.
- `effort` has no default: an agent that names none runs at the session's default (AGENTS.md, "Skills").
- `agents` gives each agent its own model and effort, `{model, effort}` under `groom`, `implement`, `fix`,
  `review`, `build` and `github`. What it leaves out takes `model` and `effort`, the fix the implementer's,
  and the host's and GitHub's agents their definitions, sonnet, since they run and post and judge nothing.
- A groomer runs only when `agents.groom` names one. An issue is a request, and the groomer asks whether it
  should be done before anyone builds it: it weighs the issue's merit and its approach against the smallest
  shape and the kernel's own answer, and its verdict either settles the API in the issue under `Update:`
  and lets the implementer start (`implement`), or stops the run with another shape for the maintainer to
  decide on (`reshape`) or the reason to build nothing (`decline`). The implementer reads the settled API in
  its prompt, and the session appends it to the issue with the run's other writes.
- `repo` has no default either: the review is read from it when the implementer is done, and a relative
  path then resolves against the session's directory, which may be a worktree removed since or one on
  another branch. #1538's review did not run, its script not found under a worktree the session had removed.
- The review is `review.js` of the review-pr skill, run nested over the branch before any pull request
  exists, so a review runs one way whoever launches it. Its build phase is the change's one run of the
  suite and of the examples it touches, in the `lunatik-host` agent, after the reviewer's fixups. A failure
  goes to a fix agent with the implementer's checkpoint, and the build runs again, twice at most; the
  fix is not reviewed again, which the hand-back says.
- The implementer writes, for each test the change adds or changes, the defect it is for as a patch,
  and the build plants each once the suite passed, in a call of its own that `crash-guard.sh` reads,
  runs the test's suite and reverts it. The hand-back carries the cases each defect failed; one that
  left its cases passing is a test that does not discriminate, which the session brings back before
  the merge, and one whose patch did not apply is stale, neither of the two: the reviewer, after its
  fixups, and a fix, after its push, write again each patch that no longer applies over the head they
  leave. A defect that removes a crash guard is not written, since its test rests on the message
  it asserts.
- The pull request opens, in the `lunatik-github` agent, only on a head that passed with every example
  the change touches run, or loaded where the host cannot drive it, and on a review that kept no mechanism
  past the smallest shape without its source, and takes the `workflow-reviewed` label from the session. Its body is the
  implementer's as the reviewer corrected it against the final diff, saying of an example the host only
  loaded what the build said: the body is drafted before either reads the branch, and #1948 and #1958
  opened claiming what the review and the build had found untrue. A run that did not pass returns its
  branch and its last build for the session to read.
- `machine` says how this machine gets root and authenticates gh, copied by the session from its
  CLAUDE.local.md: the host's and GitHub's agents load no CLAUDE.md, which keeps the instructions they
  start with to what their job reads, so the prompt is where they learn it.
- Where a push from an agent is refused (`push: false`), the implementer leaves its commits on the
  branch and no review runs: the session pushes, and launches `review.js` over the branch.
- Where gh is absent (`gh: false`), the agents read GitHub through curl and write nothing to it, since no
  guard reads a write through curl: the implementer opens no pull request, and the filing stage leaves
  every entry `unfiled` for the session.
- The last stage prepares `findings_left`, what the implementer, the review, each fix and each build run
  again after one leave, as issues: an entry
  opens an issue with its `severity:` label, or goes under an `Update:` line into the open issue it
  names as its home or reports again, never the one the pull request closes, which closes with it: one
  that belongs there opens an issue of its own, and one appended there anyway comes back as `unfiled`.
  Nothing goes to a pull request, and a skip, `skip` in `prepared`, is what the branch fixed after the
  entry was written, a review's commit or a fix's, or a host failure a fix read as fixed by an open pull
  request. What it neither prepared nor skipped comes back as `unfiled`, and the hand-back carries the
  three, since a wrong skip is a finding no issue holds.
- The run's agents write nothing to GitHub but the pull request: the auto mode classifier refuses a
  workflow agent's write ("External System Writes"), as it refused every label and every groomer's
  `Update:` of #2234's, #2238's and #2240's runs. The run returns `writes`, which the session posts in
  order as soon as it returns, without asking (AGENTS.md, *Deciding what to change*), each read back
  from GitHub: `label`, the `workflow-reviewed` label on the
  pull request; `append`, a blank line and the text or the file after the issue's body as GitHub has it
  then, and for an entry the higher of the issue's severity label and the entry's; `create`, an issue with
  the title, the file as its body and `severity: <severity>`.
- A dead run is resumed as the review-pr card says, from `journal.jsonl` and `resumeFromRunId`; the
  implementer's checkpoint is `<scratch>/issue<N>/IMPLEMENT.md`, and the review's its own.

