---
name: implement-issue
description: Implement a Lunatik issue through agents, from the issue to a reviewed pull request. Use when asked to implement an issue with a workflow, or to dispatch an agent to one.
---

AGENTS.md is the authority; `implement.js` beside this card is the workflow that orders the work:

    Workflow({scriptPath: '.agents/skills/implement-issue/implement.js',
              args: {issue: <N>, effort: '<effort>', scratch: '<absolute dir>', notes: '<the session's words>'}})

- The implementer traces the issue, writes the smallest shape down before any other, commits and
  pushes as it goes, runs the host through `tools/lunatik-host`, and opens the pull request that
  closes the issue. Its prompt names the rule each step needs and restates none, since every agent
  loads AGENTS.md and the machine's CLAUDE.local.md; what belongs to the machine, a credential or how
  it gets root, stays in the latter, and `machine-leak.sh` keeps it out of the tree.
- `notes` carries what only the session knows: what the maintainer asked for, what was already traced,
  what the issue leaves out. A rule pasted there is a copy of AGENTS.md its next change does not reach.
- `effort` has no default: an agent that names none runs at the session's default (AGENTS.md, "Skills").
- The review is `review.js` of the review-pr skill, run nested over the pull request, so a review runs
  one way whoever launches it. The implementer's totals, core srcversion and the examples it ran go to
  it as `validated` when they were read on the head it hands over, and the review builds and runs again
  only when a fixup changed that head or an example the change touches is not among them.
- Where a push from an agent is refused (`push: false`), the implementer leaves its commits on the
  branch and no review runs: the session pushes, opens the pull request, and launches `review.js` with
  the implementer's `validated`.
- The last stage files `findings_left`, what the implementer and the review leave as issues: an entry
  opens an issue with its `severity:` label, or goes under an `Update:` line into the open issue it
  names as its home or reports again. It posts nothing on a pull request. What it did not file comes
  back as `unfiled`, beside the numbers of the issues that hold the rest, and the hand-back carries both.
- A dead run is resumed as the review-pr card says, from `journal.jsonl` and `resumeFromRunId`; the
  implementer's checkpoint is `<scratch>/issue<N>/IMPLEMENT.md`, the filing stage's `FILED.md` beside
  it, which is what keeps a relaunch from filing an entry twice, and the review's its own.

