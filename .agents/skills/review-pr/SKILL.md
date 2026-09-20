---
name: review-pr
description: Review a Lunatik pull request end to end. Use when asked to review a PR or prepare review feedback.
---

The process is AGENTS.md, "Reviewing a pull request" — before the verdict, findings, fixups,
comments, after a round. Follow it whole; this card is only the GitHub mechanics.

# Reading and driving the branch

- `git fetch origin +pull/<N>/head:review/<N>` brings the author's head; the `+` takes a head a
  squash or a rebase rewrote, which a plain fetch declines without a word, so the fetched SHA is
  checked against `gh api repos/.../pulls/<N> --jq .head.sha` before anything is diffed. Check it out
  in a worktree of its own (`git worktree add <scratch>/w<N> review/<N>`, then
  `git submodule update --init`), since a worktree named for a task may be another session's; build
  and run it with the lunatik-cycle skill. The worktree goes when the review is posted, unless the
  launching session asked to keep it: `rm -rf <tree> && git worktree prune`, since `git worktree
  remove` refuses one with submodules, and each one left behind carries a build on a disk the
  sessions share.
- Read the pull request through the REST API, which needs no `read:org` scope. The spellings below
  assume the `gh` CLI; where the machine has none, the same call is
  `curl -sS -H "Authorization: Bearer $GH_TOKEN" "https://api.github.com/<path>"`, and `review.js`
  takes `gh: false` to write them that way.
  `gh api repos/luainkernel/lunatik/pulls/<N>` for the PR,
  `gh api repos/.../issues/<N>/comments` and `gh api repos/.../pulls/<N>/comments` for the
  conversation, `gh api -X PATCH repos/.../pulls/<N> -f title=... -F body=@file` to edit.

# Before the verdict

- Write the matrix the change is held to: for each guard or mechanism it adds, the operations by
  types by outcomes, and read the tests against it, cell by cell. A test set taken as given because
  it came with the branch, or with the branch a rewrite replaces, is the review not done. A cell the
  suite leaves uncovered and the review does not fill leaves as an issue, and the review body carries
  its number.
- Run the passes, not only the rules: the simplification pass over every field, helper, wrapper and
  comment the diff adds (what does it buy over the minimal shape), the shape pass grepping the file's
  siblings for the form the tree uses, and, for a guard or a primitive added to the core, the sweep
  over every binding with the same shape. Each pass is its own read of the diff; the first round of
  #848 and #849 ran the rules and left all three for a second.

# Fixups

- One finding in the working tree at a time: edit, commit, next. Two findings edited together are
  told apart afterwards by a reset and a cherry-pick, which is where a hunk lands in the wrong
  fixup.
- `bash tools/checks/idioms.sh` over the C files the diff touches and
  `bash tools/checks/author-email.sh origin/master..HEAD` over the branch are passes of the first
  round, not of the second: #850's maintainer asked for the argcheck, the `lunatik_try` and the
  shared helper the first round had read past.
- A fixup is made on `review/<N>` and pushed onto the pull request's branch, a fast-forward:
  `git push <url> HEAD:refs/heads/<branch>`; then `gh api repos/.../pulls/<N>/commits` is what says it
  is on the pull request, since the pull request lists that branch alone. `review/<N>` left on its
  own is invisible there.
- Answer a maintainer's comment in its thread, `gh api -X POST repos/.../pulls/<N>/comments -F
  in_reply_to=<comment id> -F body=@file`, quoting the line it answers.

# Reviewing as an agent that can die

A review that lives only in one agent's context is lost the moment the provider drops that agent,
and a long one is dropped often enough to plan for it. The rules below, and `review.js` beside this
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
- A phase writes its own answer back into the checkpoint before it returns, not only the findings as
  it closes them, so an agent dropped between its last tool call and the runner's record still leaves
  the verdict on disk.
- A fixup is a commit before it is anything else. Where the host refuses a push from an agent
  (`args.push: false`), it stays a commit on `review<pr>-fixups` and the session that launched the
  review pushes it, naming the SHAs the phase reported. A refused command is written down and not
  tried again: six retries of one refused push is how a nine hour run returned nothing for the third
  pull request it was reviewing.

What a dead run left is read before it is launched again: `<transcriptDir>/journal.jsonl` carries a
`result` line for every phase that finished, the checkpoints carry what each one wrote, and the fixup
branches carry the commits. Editing only the failing unit's arguments in the persisted script and
relaunching with `resumeFromRunId` replays the rest from the cache; a phase that completed is not run
again to be safe, which is the cost the checkpoint exists to avoid.

A fan-out of agents is bounded before it is launched, not after: one unit as a pilot and timed, a
wall-clock cap, and an inactivity monitor over the agents' own logs with the launching session left
idle so it can stop them. Report what a run cost before launching another. A survey that was never
bounded spent twelve hours and produced nothing, because the workflow runner restarts an agent from
zero on a provider error and nothing counted the restarts.

# Posting the review (only when asked; placement is decided BEFORE posting)

Each finding goes inline on its line; the review body is only the verdict, opening with the
author's @handle (AGENTS.md, "Comments and the verdict"). The posting account authors the pull
requests here, and GitHub answers 422 to `APPROVE` or `REQUEST_CHANGES` on one's own, so `event` is
`COMMENT` and the verdict is the body's first line. Because that account is the maintainer's, every
text an agent posts under it, the body and each inline comment, opens with
`(posted by an agent, not by @<handle>)`, so a reader knows who wrote the words.
`tools/checks/review-post-guard.sh` refuses a post that lacks `REVIEW_POST_OK=1`, and one whose body
or inline comment lacks that line: show the exact text, get the OK, then prefix the marker to the
command.

- Review with inline comments in one shot:
  `gh api -X POST repos/.../pulls/<N>/reviews -f commit_id=<head sha> -f event=COMMENT -F body=@<verdict>` with a JSON `comments` array (`path`, `line`, `side: "RIGHT"`, `body`) — build the payload with `--input file.json`.
  GitHub resolves each `line` against the diff of `commit_id`, so a line only a fixup touches
  anchors at the head, not at the author's commit: the review of #969 answered 422 "Line could
  not be resolved" at the author's commit for a README row its fixup had changed.
- A failure the branch's suite showed is in the journal before it is in the review
  (`sudo bash tools/journal.sh "<the test's print>"`, the lunatik-cycle skill); the review names
  the mechanism or the hypothesis, and `review-post-guard.sh` refuses the word that skips both.
- A single inline comment after the fact:
  `gh api -X POST repos/.../pulls/<N>/comments -f commit_id=<head sha> -f path=... -F line=... -f side=RIGHT -F body=@file`.
- Fix a submitted review's body: `gh api -X PUT repos/.../pulls/<N>/reviews/<id> -F body=@file`.
- A submitted review cannot be deleted, only dismissed. Getting the placement wrong means
  editing the body down to the verdict and re-posting each finding inline — rework, not repair.
- Once the review is posted, label the pull request as read end to end:
  `gh api -X POST repos/.../issues/<N>/labels -f 'labels[]=workflow-reviewed'`; `tools/pr-status.sh`
  reads that label as the sign that someone read it.

