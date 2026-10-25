---
name: merged
description: After a pull request merges, the maintainer's or a harness one the session merged once an agent's review passed it, retarget the pull requests stacked on its branch to the default branch, restack them onto it, delete the merged branch, and report the queue and the issues the merge closed. Use when told a pull request was merged, or to merge a harness pull request review.js returned ready.
---

AGENTS.md, "Patches and commits", and the review-pr skill's process.md, "Comments and the verdict", are the authority; this card orders
the steps. A merge reported by the maintainer is taken as given.

# 0. Merge a harness pull request

A harness pull request the session opened merges without the maintainer (AGENTS.md, "Patches and
commits") once `review.js`, the review-pr skill's workflow, ran over it at `high` and returned it
ready, its fixups folded and pushed, and the CI passed on the head that carries them. The review's
pass goes on that head as a commit status, and the merge names the head, so a push after either is
refused, by `merge-guard.sh` and by GitHub:

    gh api -X POST repos/<owner>/<repo>/statuses/<head> -f state=success -f context=agent-review -f description='review.js: ready'
    gh api -X PUT repos/<owner>/<repo>/pulls/<N>/merge -f merge_method=rebase -f sha=<head>

A fold moves the head and not the tree: the status goes on the folded head when its tree is the one
the review returned, `git rev-parse <tip>^{tree}` against `<head>^{tree}`. What the review left as
issues is filed before the merge, as implement-issue's last stage files it. A pull request the
maintainer orders merged in his own words takes `MERGE_OK=1`. The steps below follow either merge,
and the report reaches him as it does for his own.

# 1. Read the merge

    git fetch <url> +refs/heads/master:refs/remotes/origin/master
    gh api repos/<owner>/<repo>/pulls/<N> --jq '[.merged_at, .head.ref, .head.sha] | @tsv'

The pull request merges by rebase: its commits land on master with new SHAs, and every branch
stacked on it still carries the old ones. The recorded `head.sha` is the old tip, the base every
restack below starts from. The checkout sessions start in follows the new master, with
`git merge --ff-only origin/master` there when it has no commit of its own and nothing tracked
changed; `checkout-behind.sh` names it at the next session's start when it does not.

# 2. Retarget first

    gh api "repos/<owner>/<repo>/pulls?base=<head.ref>&state=open" --jq '.[].number'
    gh api -X PATCH repos/<owner>/<repo>/pulls/<M> -f base=master --jq .base.ref

Each pull request based on the merged branch moves to master before anything else touches it.
Left on the merged branch it merges into that branch and never reaches master, which is what #1041
did one merge after #1040; and a merged branch deleted before its stacked pull requests move closes
them.

A stacked pull request opens as a draft, which GitHub does not merge; on master it is marked
ready, through GraphQL since REST has no endpoint for it:

    gh api graphql -f query='mutation($id: ID!) { markPullRequestReadyForReview(input: {pullRequestId: $id}) { pullRequest { isDraft } } }' \
        -f id="$(gh api repos/<owner>/<repo>/pulls/<M> --jq .node_id)"

# 3. Restack

In a worktree of the stacked branch, record its head, then:

    git rebase --onto origin/master <old tip of the merged branch>

The base is the recorded old tip, never `<branch>^`, which points inside a branch that carries
fixups and drops what lies below it. A chain moves in order, each branch onto its predecessor's new
head, with every old head recorded before the first rebase. A conflict stops the chain: it is
resolved hunk by hunk, never with a whole file's `--ours` or `--theirs`, and `git status` shows no
rebase in progress before anything is pushed.

Each moved branch keeps its own change: `git diff <old tip>..<old head> | git patch-id` equals
`git diff origin/master..<new head> | git patch-id`, or the difference is what master changed under
it, said in the report. Then, a command of its own:

    git push <url> <new head>:refs/heads/<branch> --force-with-lease=refs/heads/<branch>:<old head>

Both SHAs are read, never typed: the old head from `git ls-remote <url> refs/heads/<branch>` and the
new one from `git rev-parse HEAD`. A full SHA completed from its short form by hand named no commit
and failed the lease in the restack under #1879.

The report names the ref it moved and, apart, what it was rebased onto.

The body of each moved pull request is read again: a sentence that names the merged base as the one it
stacks on now names a dependency already on master, which a reviewer reads as still pending, so it goes
or says the base is in, through `gh api -X PATCH repos/<owner>/<repo>/pulls/<M> -F body=@<file>`, and the
report says the body was edited. #2119 and #2129 kept their "stacks on #N" after the retargets of
2026-10-23.

# 4. Delete the merged branch

Once no open pull request is based on it, the merged branch goes, from this repository and from the
checkout, unless a worktree holds it checked out:

    git push <url> --delete <head.ref>
    git branch -D <head.ref>

Its commits are on master under new SHAs, and GitHub keeps the old head as `refs/pull/<N>/head`. A
delete the session's permissions refuse goes to the maintainer as a script under `/tmp` and the line
that runs it (AGENTS.md, *Deciding what to change*).

# 5. Report

The new master tip; for each stacked pull request, retargeted, restacked, the patch verdict and the
push; the branches deleted, and a branch a worktree kept with whose it is; `bash tools/pr-status.sh`
for the queue that follows; and the issues the merge closed, with any it names only as "Part of" that
it finished.

