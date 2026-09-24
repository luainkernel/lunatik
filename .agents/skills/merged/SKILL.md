---
name: merged
description: After the maintainer reports a pull request merged, retarget the pull requests stacked on its branch to the default branch, restack them onto it, and report the queue and the issues the merge closed. Use when told a pull request was merged.
---

AGENTS.md, "Patches and commits" and "Comments and the verdict", is the authority; this card orders
the steps. A merge reported by the maintainer is taken as given.

# 1. Read the merge

    git fetch <url> +refs/heads/master:refs/remotes/origin/master
    gh api repos/<owner>/<repo>/pulls/<N> --jq '[.merged_at, .head.ref, .head.sha] | @tsv'

The pull request merges by rebase: its commits land on master with new SHAs, and every branch
stacked on it still carries the old ones. The recorded `head.sha` is the old tip, the base every
restack below starts from.

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

The report names the ref it moved and, apart, what it was rebased onto.

# 4. Report

The new master tip; for each stacked pull request, retargeted, restacked, the patch verdict and the
push; `bash tools/pr-status.sh` for the queue that follows; and the issues the merge closed, with
any it names only as "Part of" that it finished.

