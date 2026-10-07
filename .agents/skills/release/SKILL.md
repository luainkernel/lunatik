---
name: release
description: Cut a Lunatik release: confirm its milestone, the suite and the CI on the cut commit, write the notes from the commits, draft the release, and once the maintainer publishes it rebuild the site and close the milestone. Use when asked to cut, draft or publish a release, or for its notes or its announcement.
---

AGENTS.md is the authority, *Patches and commits* for a summary derived from commits and *Comments
and the verdict* for text shown before it goes public; this card orders the steps v5.0's cut ran. The
cut is the commit the maintainer names, or master's tip when he names none, recorded by its full SHA:
every step reads that SHA, never a branch that moves under it.

# 1. The milestone

    gh api "repos/<owner>/<repo>/milestones?state=open" --jq '.[] | [.number, .title, .open_issues] | @tsv'
    gh api "repos/<owner>/<repo>/issues?state=open&milestone=none&labels=severity:%20<level>&per_page=100" \
        --jq '.[] | select(.pull_request | not) | .number'

The release's milestone has no open issue, and the second command prints nothing for `high` nor for
`medium`: every open issue of those severities is in the release or in a later milestone, by the
maintainer's word.

# 2. The suite on the cut

The whole suite runs on the cut through the lunatik-cycle skill. A pull request merged after the run
leaves it standing only when `git diff <tested> <cut>` is that pull request's patch alone, its
`git patch-id` equal to the merged pull request's, and the patch reaches nothing the build, the
install or the suite reads: every file it changes lies under `tools/checks/`, `.agents/`, `.claude/`,
`.github/` or `doc/`, or is `AGENTS.md`, or every line it changes elsewhere is a comment or a
copyright header, a shebang only moved and not changed. Anything else runs the suite again on the cut.

# 3. CI on the cut

    gh api repos/<owner>/<repo>/commits/<sha>/check-runs --jq '.check_runs[] | [.name, .status, .conclusion] | @tsv'

The runs read are the cut's own, not a pull request head's, which passed on a tree the merge then
changed. Every one completed with `success`, or the cut waits, unless the maintainer says to go on
without it, and then the report names the runs still in progress.

# 4. The notes

Written from each commit's own words since the previous release's tag, `git log --reverse <previous
tag>..<sha>`, under Highlights, Fixes, Before upgrading, Changes to existing APIs, Known issues and
Contributors. Each bullet names the pull request it was read from, `(#N)`, and says what that commit
says, not what its issue's title says: v5.0's first draft worded #1286 from its issue and called
every known issue documented while #1260 was not.

Known issues lists the open issues the release ships with, read from GitHub and not from memory, each
with what a script meets today. The notes promise nothing to come: not the API freeze, which stays
the tree's own rule (AGENTS.md, *The API a script sees*), and not the release that fixes a known
issue. Contributors are the authors of the range, `git shortlog -sn <previous tag>..<sha>`, with their
handles, and the first contributions with their pull requests. The body ends with
`**Full Changelog**: https://github.com/<owner>/<repo>/compare/<previous tag>...<tag>`, and not with
the list of pull requests GitHub generates.

`release-body.sh` reads the notes before they are shown, and `pr-body-guard.sh` runs it on the write.

# 5. The draft

    jq -n --arg tag <tag> --arg sha <sha> --arg name "Lunatik <tag>" --rawfile body <notes> \
        '{tag_name: $tag, target_commitish: $sha, name: $name, body: $body, draft: true}' > <release.json>
    gh api -X POST repos/<owner>/<repo>/releases --input <release.json> --jq '[.id, .html_url] | @tsv'

The tag does not exist until the release is published, when GitHub creates it on `target_commitish`:
before the POST, `gh api repos/<owner>/<repo>/releases/tags/<tag>` answers 404, so no release carries
it, and after it `git ls-remote <url> refs/tags/<tag>` prints nothing, so the draft made no tag.
The notes go to the maintainer whole, in the message that hands the draft over. Publishing is his
imperative, and then:

    gh api -X PATCH repos/<owner>/<repo>/releases/<id> -F draft=false -f make_latest=true

# 6. The site

The site names the release only once a tag in the built commit's history says so
(`doc/style/ldoc.ltp`, from `doc/.tags`), and `doc.yml` runs on a push to master and takes no
`workflow_dispatch`, so after the publish the push run of master's tip runs again, the run whose
`head_sha` is that tip and no other, since a listing by branch answered v5.0's cut with runs weeks older:

    gh api "repos/<owner>/<repo>/actions/workflows/doc.yml/runs?head_sha=<master tip>&event=push" \
        --jq '.workflow_runs[] | select(.head_sha == "<master tip>") | .id'
    gh api -X POST repos/<owner>/<repo>/actions/runs/<run>/rerun

Once pages deploys, the footer names the release without "development":

    curl -s https://luainkernel.github.io/lunatik/ | grep -oE 'Lunatik [0-9]+\.[0-9]+( development)?'

# 7. The milestone closes

    gh api -X PATCH repos/<owner>/<repo>/milestones/<number> -f state=closed

# 8. The announcement

Written only when the maintainer asks, as a prompt he hands on for LinkedIn and for lua-l: its facts
come from the published notes, the README and the repository's own record, each one read, and nowhere
else; it promises nothing to come, as the notes do not, and the lua-l post is plain text under
`[ANN] Lunatik <tag> released`.

