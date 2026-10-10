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
  the hunt's own reading. Its prompt names the rule each step needs and restates none, since every
  agent loads AGENTS.md and the machine's CLAUDE.local.md; what belongs to the machine, a credential or how
  it gets root, stays in the latter, and `machine-leak.sh` keeps it out of the tree.
- `notes` carries what only the session knows: what the maintainer asked for, what was already traced,
  what the issue leaves out. A rule pasted there is a copy of AGENTS.md its next change does not reach.
- `effort` has no default: an agent that names none runs at the session's default (AGENTS.md, "Skills").
- `repo` has no default either: the review is read from it when the implementer is done, and a relative
  path then resolves against the session's directory, which may be a worktree removed since or one on
  another branch. #1538's review did not run, its script not found under a worktree the session had removed.
- The review is `review.js` of the review-pr skill, run nested over the branch before any pull request
  exists, so a review runs one way whoever launches it. Its build phase is the change's one run of the
  suite and of the examples it touches, in the `lunatik-host` agent, after the hunt's fixups. A failure
  goes to a fix agent with the implementer's checkpoint, and the build runs again, twice at most; the
  fix is not reviewed again, which the hand-back says.
- The pull request opens, in the `lunatik-github` agent, only on a head that passed with every example
  the change touches, with the implementer's body, and takes the `workflow-reviewed` label. A run that
  did not pass returns its branch for the session to read.
- `machine` says how this machine gets root and authenticates gh, copied by the session from its
  CLAUDE.local.md: the host's and GitHub's agents load no CLAUDE.md, which keeps the instructions they
  start with to what their job reads, so the prompt is where they learn it.
- Where a push from an agent is refused (`push: false`), the implementer leaves its commits on the
  branch and no review runs: the session pushes, and launches `review.js` over the branch.
- Where gh is absent (`gh: false`), the agents read GitHub through curl and write nothing to it, since no
  guard reads a write through curl: the implementer opens no pull request, and the filing stage leaves
  every entry `unfiled` for the session.
- The last stage files `findings_left`, what the implementer and the review leave as issues: an entry
  opens an issue with its `severity:` label, or goes under an `Update:` line into the open issue it
  names as its home or reports again. It posts nothing on a pull request, and skips, `skipped` in
  `filed`, what the branch fixed after the entry was written, a review's commit or a fix's, and a host
  failure a fix read as fixed by an open pull request. What it neither filed nor skipped comes
  back as `unfiled`, beside the numbers of the issues that hold what it filed, and the hand-back carries
  the three, since a wrong skip is a finding no issue holds.
- A dead run is resumed as the review-pr card says, from `journal.jsonl` and `resumeFromRunId`; the
  implementer's checkpoint is `<scratch>/issue<N>/IMPLEMENT.md`, the filing stage's `FILED.md` beside
  it, which is what keeps a relaunch from filing an entry twice, and the review's its own.

