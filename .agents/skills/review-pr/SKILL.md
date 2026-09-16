---
name: review-pr
description: Review a Lunatik pull request end to end. Use when asked to review a PR or prepare review feedback.
---

The process is AGENTS.md, "Reviewing a pull request" — before the verdict, findings, fixups,
comments, after a round. Follow it whole; this card is only the GitHub mechanics.

# Reading and driving the branch

- `git fetch origin pull/<N>/head:review/<N>` brings the author's head; check it out in a worktree
  of its own (`git worktree add <scratch>/w<N> review/<N>`, then `git submodule update --init`),
  since a worktree named for a task may be another session's; build and run it with the
  lunatik-cycle skill.
- Read the pull request through the REST API, which needs no `read:org` scope. The spellings below
  assume the `gh` CLI; where the machine has none, the same call is
  `curl -sS -H "Authorization: Bearer $(cat <token>)" "https://api.github.com/<path>"`, and
  `review.js` takes `gh: false` to write them that way. Its other machine arguments — `repo`,
  `worktrees`, `tokenfile`, `sudo`, `host`, `consumers` — default to the machine it was written on,
  so a second host passes its own and runs the same phases.
  `gh api repos/luainkernel/lunatik/pulls/<N>` for the PR,
  `gh api repos/.../issues/<N>/comments` and `gh api repos/.../pulls/<N>/comments` for the
  conversation, `gh api -X PATCH repos/.../pulls/<N> -f title=... -F body=@file` to edit.

# Before the verdict

- Write the matrix the change is held to: for each guard or mechanism it adds, the operations by
  types by outcomes, and read the tests against it, cell by cell. A test set taken as given because
  it came with the branch, or with the branch a rewrite replaces, is the review not done.

# Reviewing as an agent that can die

A review that lives only in one agent's context is lost the moment the provider drops that agent,
and a long one is dropped often enough to plan for it. Three rules, and `review.js` beside this
card is the workflow that follows them (`Workflow({scriptPath: '.agents/skills/review-pr/review.js', args})`):

- Findings go to a checkpoint file as they close, one line each (`file:line | what | disposition`),
  not to the final message; the message is assembled from the file, and a successor reads the file
  first and continues from it instead of reading the branch again.
- A review is phases, not one agent: hunt the findings, check the rules and the harness, then build
  and run. Each phase returns a `schema`, so a crash loses one phase and the cache replays the ones
  that completed under `resumeFromRunId`.
- A head the suite already passed is not built again by the review: the totals, the core
  srcversion and the examples run on it go in the briefing (`args.validated`), and the build phase
  runs only when a fixup changed the code or an example the change touches
  (`tools/checks/examples-touched.sh` over the changed files, passed as `args.examples`) is not
  among them. The suite is not the examples: #795 and #837 passed the probe suite and neither ran
  systrack, whose first run on the merged code took the host down.

A fan-out of agents is bounded before it is launched, not after: one unit as a pilot and timed, a
wall-clock cap, and an inactivity monitor over the agents' own logs with the launching session left
idle so it can stop them. Report what a run cost before launching another. A survey that was never
bounded spent twelve hours and produced nothing, because the workflow runner restarts an agent from
zero on a provider error and nothing counted the restarts.

# Posting the review (only when asked; placement is decided BEFORE posting)

Each finding goes inline on its line; the review body is only the verdict, opening with the
author's @handle (AGENTS.md, "Comments and the verdict"). The posting account authors the pull
requests here, and GitHub answers 422 to `APPROVE` or `REQUEST_CHANGES` on one's own, so `event` is
`COMMENT` and the verdict is the body's first line. `tools/checks/review-post-guard.sh` refuses a
post that lacks `REVIEW_POST_OK=1`: show the exact text, get the OK, then prefix the marker to the
command.

- Review with inline comments in one shot:
  `gh api -X POST repos/.../pulls/<N>/reviews -f commit_id=<head sha> -f event=COMMENT -f body=@<verdict>` with a JSON `comments` array (`path`, `line`, `side: "RIGHT"`, `body`) — build the payload with `--input file.json`.
- A single inline comment after the fact:
  `gh api -X POST repos/.../pulls/<N>/comments -f commit_id=<head sha> -f path=... -F line=... -f side=RIGHT -F body=@file`.
- Fix a submitted review's body: `gh api -X PUT repos/.../pulls/<N>/reviews/<id> -F body=@file`.
- A submitted review cannot be deleted, only dismissed. Getting the placement wrong means
  editing the body down to the verdict and re-posting each finding inline — rework, not repair.
- Once the review is posted, label the pull request as read end to end:
  `gh api -X POST repos/.../issues/<N>/labels -f 'labels[]=workflow-reviewed'`; `tools/pr-status.sh`
  reads that label as the sign that someone read it.

