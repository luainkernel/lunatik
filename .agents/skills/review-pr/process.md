# Reviewing a pull request

A review produces two things: the comments, and a branch showing what the comments ask for. Neither
is posted before the maintainer has seen both, and the checklist below is the reviewer's own — a
review that fails it is not ready, whatever the code looks like.

The checklist runs whole on every pull request, whoever wrote it: the maintainer's own, another
session's, or this session's earlier work. Authorship shortens nothing. A change that arrives with
a rationale attached — a comment beside the line, a body that explains the choice, a prior session
that "already reviewed it" — is reviewed against the code, not against the rationale: a comment
beside `raw_cpu_ptr` about a preemptible caller that does not exist is a finding to run to ground
against the kernel's own idiom, not a reason to pass the line. Reading the rationale as the review
is how a mutex in softirq and a crash reachable from Lua were passed.

# Before the verdict

1. Check out the author's branch, build it, and run the suite. Reading the diff misses what the
   machine already knows. A change with no test of its own — an example, a script — is run directly,
   not merely built: an entry point that never fires hides a runtime crash behind a green build, and
   an approval says it ran. If it does not run, that is a hypothesis to trace, not a finding: separate
   the artifact under test from the tool exercising it — the same program the distribution's loader
   rejects may load under a current one — and exhaust the working path before writing "could not run".
   A reviewer with the machine drives it to ground rather than asking the author to confirm what the
   machine could have said. The base to diff against is `origin/master`, not the local `master`, which
   may have drifted; `git rev-list --count origin/master..master` says whether it did.
2. List every file the pull request touches (`gh pr view <n> --json files`) and read from that list.
   The patch spans the repo, not the feature's folder, so a claim that the PR contains or lacks a file
   is grounded in that changeset, never in a directory listing scoped to where you assumed it would
   live — "no README in the PR", from an `ls` of the example directory while the PR edited the
   repo-root `README.md`, is the shape of that error.
3. Read the PR's own conversation, not only its diff. An author's comment may raise a question or
   propose an alternative the review has to engage; a verdict that ignores an open author thread is
   incomplete.
4. A PR based on another branch rather than `master` is stacked: review it against its own base, and
   read the whole stack first, because what one PR seems to delete may have moved to a PR stacked on
   top of it — check there before reporting a deletion as a loss.
5. Work on `review/<pr number>`, started from the author's head. The number is what lets the author,
   and the next reviewer, find the branch; a name of your own choosing does not.

# Findings

* A finding is worded softly even when its trace is hard. A prescriptive "should" lands as a ruling
  on the author's work: say what the code does, what impression the name or contract gives, and
  offer the fix conditioned on the intent. The trace can be categorical; the phrasing is not.
* A finding names its severity from what is traced, not from what is feared. A crash is a crash only
  when a reachable path reaches it; short of that it is a contract or parity gap, said as one. A cost
  claim — "overhead", "slow", "expensive" — is a measurement, not an adjective: unmeasured, what you
  have is a duplication or an extra call, named as that, not as a hot path. When a number would decide
  the point and is not in hand, say it was not measured. A finding left as an issue carries its
  severity as the repository's label: `severity: high`, a hang or a crash a script or a user can
  reach; `severity: medium`, a leak, a silent error or an exposure without an immediate crash;
  `severity: low`, documentation, tests or cleanup.
* A symptom seen while poking by hand is not a finding until a clean run reproduces it. Reload to a
  fresh slate, run once, apply one stimulus, read the result — that is authoritative; a scratch
  fighting leftover state is not. An absence of errors counts only if you exercised the path that
  raises them: zero because the code never ran is not zero because it ran clean. A "serious bug"
  escalated from stale-environment noise and nearly filed against someone's PR is the failure this
  guards against. Non-determinism is the tell: a symptom that shows on one run and not the next, from
  the same inputs, is environment state, not a code path — the variable is the leftover, so control it
  (a fresh reload, a pinned CPU, the program cut down to the one call under test) rather than theorise
  a bug. The converse is a tell as well: a symptom that reproduces on every run is the code's, and the
  first code to read is the change's own, before the runtime, the kernel or the way it was invoked. The
  minimal isolating reproduction settles in one run what reading the noisy end-to-end path
  never does. When the variable is a stimulus the host may or may not supply — a stray packet in a
  window — supply it yourself and reproduce the signature on demand, and log what the hook actually
  saw before naming the packet. A mechanism proved by injection is reported as that, not as the
  trigger of the run that failed, which was not captured. A failure the suite showed once is read in
  the journal before anything runs again: the KTAP line carries an errno and the test's own prints
  say how far it got, and the window around them, every unit and not only the kernel
  (`tools/journal.sh`), shows who else acted on what the test created. `nl80211_station` failed
  with `ENOENT` after "added" and before "authorized", and the journal had NetworkManager
  registering the AP interface the test had brought up and wpa_supplicant taking it down, which
  flushes the station; a rerun that passed had wpa_supplicant arriving after the test deleted the
  interface. A rerun measures the rerun; the word for a failure nobody read is what
  `untraced.sh` refuses.
* A defect found on the way is fixed, not reported and left: a pre-existing one, in code the change
  does not touch, becomes a commit of its own, or a pull request of its own when it stands apart, and
  the hand-back says which. Asking whether to fix it is asking the maintainer to decide what the
  rules already decide. "It is not this pull request's" names where the fix goes, never whether it is
  owed: the finding leaves with a branch or an issue and the report carries its number, since a defect
  handed back as prose is a defect nobody owns. Before the fix is written, `tools/pr-status.sh` says
  whether an open pull request already carries one: a second fix of the same defect collides with the
  first and is dropped, and #976 wrote two of them, at a review round each.
* A finding is resolved, not parked. When something looks wrong, run it to ground — reproduce it, find
  the cause, then fix it or dismiss it. "I'll flag it to the author", "let's look into it separately",
  or asking whether to investigate is dropping it, not handling it. Deferral is for work that belongs
  in another pull request, captured as an issue linked from the comment that defers it — not for the
  hard half of the finding in hand. A dismissal is held to a finding's own standard: runs that came
  back clean do not dispose of a symptom that appeared once, because an absence measures the runs and
  not the code. Either the mechanism is traced to why it cannot happen, or it is still a finding and
  leaves as one. Handing a call back to the maintainer is a deferral like any other and takes the same
  issue: a design costed in a review thread, with its trade written out and no number on it, is lost
  the day the pull request is merged, and the next reader pays for the analysis again.
* Cover the whole change, and flag across all of it — the author's code and your own fixups alike.
  "It is the author's code" or "my line, not the feature" is never a reason to pass over a defect;
  what is scoped is the fixup, which touches only what a finding requires, not the finding. A review
  that reads the one file it expected the bug in and skips the rest is half a review, and the half it
  skipped is where the reader assumes it looked.
* A review runs the passes of AGENTS.md, *Before opening a pull request*, over the diff as passes of its own, not
  only the rules it can cite: the simplification pass, field by field and helper by helper, asking
  what each buys over the minimal shape, and the shape pass, grepping the file's own siblings for the
  form the tree uses. The first round on #848 and #849 ran only the rules and left for a second round
  a predicate written as a function in a header of macros, a comment on one member of a struct whose
  members carry none, a wrapper a vararg made unnecessary, and a frame field the accessor could read
  from `current`. A guard added to the core for one binding is read against every binding with the
  same shape before the verdict, module by module, and a consumer found leaves as an issue: `device`
  dispatches its file operations the way `fsnotify` dispatches events, and #959 says so.
* A review holds new code to the conventions AGENTS.md and `.agents/rules/` record; it does not impose preferences beyond
  them. Where the tree itself is inconsistent and a style seems worth settling, that is an exclusive
  pull request that fixes the whole tree and records the convention here — never a finding on someone's
  feature work. That pull request is opened, not named: moving a finding out of the review is where it
  goes, not whether it happens, and a round that names one without opening it, or an issue without
  filing it, dropped the finding it was carrying. A name that deliberately mirrors a kernel symbol keeps its spelling: `TC_H_MAKE` ported
  from the kernel macro stays upper-case though Lua functions are lower-case, because the recognition
  is the point. Check what a name mirrors, and read the author's stated reason, before calling it a
  violation.
* A new module is read for its shape, not only its logic. How a module of its kind returns, names its
  handle field, constructs, and documents is measured against the nearest existing sibling —
  `socket.inet` for a wrapper, `bpf.map`'s `view` for a proxy — and correct code in a shape the tree
  does not use is a finding. That a form conforms is found in the tree by grepping for the peer that
  uses it, not felt.
* The base can be the outdated one. When new code diverges from it, check which side is right before
  aligning — pulling the new code down to match a sibling that is itself behind is the wrong fix.
  `tc`'s BPF programs were right to declare `Dual MIT/GPL`; the `xdp` ones still on `GPL` are what a
  separate cleanup fixes.
* Missing tests are a finding of their own, written as such, not a remark appended to another comment.
  The review writes the matrix the change is held to and reads the tests against it; a test set
  taken as given because it came with the branch is the review not done.
* A contract the author documented is not redesigned by the review. An ergonomics preference, `nil`
  against an object whose methods raise, is stated with its trade-off and left to the maintainer;
  shipped as a fixup, it asks the author to un-decide.

# Fixups

* A code finding ships as the fixup that makes it, not as a paragraph in the imperative — "use
  `set.labeled`", "name these offsets", "please follow that" hands the author work you could have done
  and shown, and is the review half-done. The prose points at the fixup and says why; the fixup is the
  change. A code finding with no commit behind it is not ready to post, and a review posted as comments
  with no branch is the lazy half of the two the review owes.
* One fixup per finding, `git commit --fixup=<the author's commit>` — not one per file, and not one
  per target commit: a comment pointing at a commit that does three unrelated things cannot be accepted
  in parts, and the author is the one who autosquashes what they accept. A fixup touches only what the
  pull request introduced; check the symbol's provenance first, since one already on `master` is a
  separate change on its own branch, and a design note under `doc/design/` that mentions the old
  shape is a snapshot of a plan, not the API's documentation, and stays out. A fixup is the
  reviewer's code with no reviewer, so it gets the pass the author's code got. A consistency fix on
  the branch's own code is done now, not deferred.
* A script or command handed to the author is one you ran, not one you syntax-checked or copied from a
  doc. `bash -n` passing is not the script working, and "it is the README's own command" is not "it
  runs here". If the environment cannot verify it — a stale module, a skewed signature in the way —
  the verdict is "unverified", said plainly, not "it works".
* Rebase the review branch when `master` moves under it, so the fixups still apply to what the author
  will rebase onto. A linked fixup's SHA is a published reference the moment the comment posts;
  amending or rebasing after that leaves the link pointing at the superseded version, so leave the
  branch be once posted, and when a change is unavoidable, refresh the SHAs in the comments it moved.

# Comments and the verdict

* Draft the comments and hand them over. The repository's public voice is the maintainer's; a reviewer
  writes, the maintainer posts. Do not comment on a pull request or an issue unless asked, and having
  offered earlier is not authorization. Being told to post is not a license to post words the
  maintainer has not read: show the exact text, get the go-ahead on it, then post — the approval is of
  the wording, and "post it" or "where is it?" asks for the draft, not for it to already be public.
  The exact text goes in the message that asks, whole and every round, never as a path to a file or
  as "unchanged from the last one": what is not in front of the maintainer was not shown. The
  round is for another author's pull request: on one the maintainer's account opened, his or an
  agent's under it, a review he asked for is posted as written, since the words land on his own work.
* A code finding is posted inline, anchored on the line it addresses; the review body carries the
  verdict and addresses the author by handle. A finding in the body, away from its line, makes the
  reader hunt for where it applies — and a submitted review cannot be deleted, only dismissed, so the
  placement is decided before posting, not repaired after.
* Each comment links its fixup as a full commit URL — never a backtick'd SHA, which renders as code and
  does not link. A reply to an author's comment @-mentions the author and quotes the line it answers
  under the opening that says an agent wrote it: an issue comment does not thread and need not even
  notify them, so the @-mention reaches them and the quote makes it a reply, not a stray remark. A
  request for changes is not a place for praise; padding buries the change being asked for.
* Write a finding plainly and no longer than it needs to be: the defect, the fix, and the trace,
  without metaphor, restatement, or throat-clearing. Padding buries the finding the way praise does.
* A claim that rests on source outside the diff — a kernel accessor, a sibling module, a spec — links
  that source the way a fixup is linked: a stable, line-anchored URL at a pinned ref, a commit or tag
  blob, never a moving `master` link that drifts off the line. The reference is the evidence; a finding
  that names an accessor or a pattern without a link asks to be trusted, not checked.
* The verdict states whether the pull request can merge as it stands: a finding that must be folded is
  a request for changes, however small; a comment review is for observations that do not gate. Once it
  is clean, the verdict is an Approve, not a comment — a comment saying it looks good leaves an earlier
  request-for-changes standing and the gate closed. Say it plainly and flip the state. A pull request
  the posting account authored takes neither state: GitHub answers 422 to an approval or a request
  for changes on one's own, so that review is a comment whose first line is the verdict.
* A further request-for-changes, when the PR already carries your changes-requested, does not surface:
  GitHub stores it and the API shows it, but the conversation gains no new item because the gate did
  not move — so it "posted" by every check you can run and is still invisible. When the gate is already
  closed and there is more to say, comment. And feedback lives in one artifact: when you fall back to a
  comment, or correct or move a comment, edit or supersede the one that carries it — never leave two
  copies to drift.
* A stacked pull request is merged after its base, never before: GitHub merges it into the base
  branch, the base pull request grows a commit nobody reviewed there, and the stacked one closes
  as merged with nothing on `master`. A verdict on a stacked pull request says "after #N", and until
  then it stays the draft it opened as, which the merged skill marks ready once it retargets it. After its
  base merges it waits too, until it is retargeted: GitHub leaves it on the merged branch, and
  #1041, merged seconds after #1040, landed there and not on `master`. `tools/pr-status.sh` names
  a base that merged, and the merged skill retargets and restacks what a merge leaves behind.
* Approving is the reviewer's to state; merging is the maintainer's to trigger. Even a clean, approved
  PR is not merged on the reviewer's initiative — pushing or merging to `master` is irreversible and
  public, and the click is the maintainer's alone. A question about state — "can we merge?", "is it
  ready?", "what's the status?" — asks for the readiness, the way "where is it?" asks for a draft, not
  for the merge. Wait for the imperative, "merge it"; report the state and stop.

# After a round

* Re-read your own review before it goes out, against the exact branch: the overstated severity, the
  file left unopened, the fixup whose comment drifted from what it does. The self-audit the code gets
  is owed to the review too.
* A re-review re-fetches the author's branch and reads what changed there — not the review branch you
  built last round. A head rewritten by a squash or a rebase is fetched with a forced refspec,
  `+pull/<n>/head:refs/pr/<n>`: a plain fetch declines the non-fast-forward without a word and leaves
  the old head in place, and every comparison after it reads the wrong commit, so the fetched head is
  checked against the pull request's before any diff. Diff the author's new head against what you
  last saw: re-reading your own fixups reviews your work, not theirs, and misses what they folded
  wrong, spelled differently, or left out. Confirming that prior findings were folded and the build is
  green is where a re-review starts, not where it ends.

