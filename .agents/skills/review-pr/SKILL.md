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
- Read the pull request through the REST API, which needs no `read:org` scope:
  `gh api repos/luainkernel/lunatik/pulls/<N>` for the PR,
  `gh api repos/.../issues/<N>/comments` and `gh api repos/.../pulls/<N>/comments` for the
  conversation, `gh api -X PATCH repos/.../pulls/<N> -f title=... -F body=@file` to edit.

# Before the verdict

- Write the matrix the change is held to: for each guard or mechanism it adds, the operations by
  types by outcomes, and read the tests against it, cell by cell. A test set taken as given because
  it came with the branch, or with the branch a rewrite replaces, is the review not done.

# Posting the review (only when asked; placement is decided BEFORE posting)

Each finding goes inline on its line; the review body is only the verdict, opening with the
author's @handle (AGENTS.md, "Comments and the verdict"). `tools/checks/review-post-guard.sh`
refuses a post that lacks `REVIEW_POST_OK=1`: show the exact text, get the OK, then prefix the
marker to the command.

- Review with inline comments in one shot:
  `gh api -X POST repos/.../pulls/<N>/reviews -f commit_id=<head sha> -f event=REQUEST_CHANGES -f body=@<verdict>` with a JSON `comments` array (`path`, `line`, `side: "RIGHT"`, `body`) — build the payload with `--input file.json`.
- A single inline comment after the fact:
  `gh api -X POST repos/.../pulls/<N>/comments -f commit_id=<head sha> -f path=... -F line=... -f side=RIGHT -F body=@file`.
- Fix a submitted review's body: `gh api -X PUT repos/.../pulls/<N>/reviews/<id> -F body=@file`.
- A submitted review cannot be deleted, only dismissed. Getting the placement wrong means
  editing the body down to the verdict and re-posting each finding inline — rework, not repair.

