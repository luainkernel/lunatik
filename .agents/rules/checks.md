---
paths:
  - "**/tools/**"
  - "**/.agents/**"
  - "**/.claude/**"
  - "**/.github/**"
  - "**/AGENTS.md"
---

# Checks

`tools/checks/` holds the mechanical checks: comment and LDoc style on framework files
(`module-conventions.sh`), the comment rules of `.agents/rules/comments.md` read over C, Lua and shell, the history, a
release named with what changed in it or above a table, the counterfactual, the multi-line note
inside code, the trailing comment past the width, a comment on a signature line or above an internal
`static inline` and one naming the file or function that reads a value
(`comment-style.sh`), a comment a change adds to one definition of a block whose others carry none
(`comment-siblings.sh`), a sequence of calls a change adds that another C file already makes
(`core-helper.sh`), a deferral a change adds to the core or a binding (`deferral.sh`), the
branches, argument tables, inline functions and repeated blocks the Lua style rules settle
(`lua-style.sh`), test scripts that cannot detect a failed load or a case their Lua script
skips (`test-harness.sh`), a kernel thread loop that never pauses (`kthread.sh`), cppcheck on
userspace test C (`cppcheck-tests.sh`), a typedef renamed against a sibling the change removed
(`rename-orphaned.sh`), a recursion in the Lua the kernel links that counts no C level and no bound
names (`recursion.sh`), a local, a function or a global lua-language-server reads as a slip
(`luals.sh`), the readers of a field the change keeps its own copy of
(`shadowed-readers.sh`), the classes and callers a changed core primitive reaches
(`blast-radius.sh`), the examples that use a binding the change touches, which a review runs
(`examples-touched.sh`), a commit that carries a rule or a check inside a change of its own
(`harness-mixed.sh`), the machine a tracked file carries (`machine-leak.sh`), and the trailing blank
line rule, the refusal of a staged conflict marker, of a source file without its copyright and
license header and of a string function the kernel removed (`pre-commit`). Each takes file paths and
skips what does not apply, so any editor, assistant, or CI can run them. The `Checks` workflow runs
them over a pull request's diff: `pre-commit` and
`machine-leak.sh` fail the run, the heuristic checks annotate it. Install the commit gate with:

    ln -s ../../tools/checks/pre-commit .git/hooks/pre-commit

`advisory.sh` runs the heuristic checks over a change, the file checks over the files it adds or
modifies and the commit checks over its commits: the list the `Checks` workflow annotates a pull request
with, and the one `tools/review-packet.sh` hands a review.

`core-subject.sh` reads commits rather than files, since a subject belongs to a commit: it takes
commits or a rev-range (`bash tools/checks/core-subject.sh origin/master..HEAD`) and flags one that
changes the core under a subject naming only a binding. The rule is not that core and a binding
never mix, which AGENTS.md, *Patches and commits*, sanctions, but that the subject says so.

`body-identifiers.sh` reads commits the same way and names the identifiers a body carries that appear
neither in the commit's diff nor in the code at that commit: what a folded fixup removed, the body
written before the squash still explains. A kernel symbol a body cites
for what the code does not do is named too, so the report is read, not obeyed.

`kernel-answer.sh` reads commits the same way and names one that builds a mechanism over a kernel
primitive, RCU, a lock, a reference count or deferred work, with a new function or field, in a body
that cites neither a `Documentation/` page nor one of that family's own facilities: the kernel has
usually answered the problem already, and the comparison belongs in the body where the reviewer reads:
`Documentation/RCU/whatisRCU.rst` says "Will readers need to block? If so, you need SRCU". It annotates, since
a body can cite the page and still not read it.

`terminator.sh` reads a C file for a store that terminates an array, `x[n] = '\0'`, and names it when
no call in the file that reads a C string takes that array: a byte written for one reader stays
written after the reader goes. It annotates, since the reader
can sit in another file behind a pointer the array is handed to.

`guard-removed.sh` names the crash guards a C file drops against `HEAD` (a checker, an
`argcheck`, a context check): removing one and running the test that covers it reproduces the
crash the guard prevents, and on the shared host that is a forced reboot. `crash-guard.sh`, wired
before a shell call like the review guard below, blocks an install, reload or run while any
worktree drops such a line, unless the command carries `CRASH_AB_OK=1`, set once the maintainer
authorized the experiment and named the machine it may take down. It reads every worktree of the
checkout, so one another session left dirty blocks this session's install too; its owner cleans it,
and a review says its run was blocked rather than overriding a guard that was not about its tree.
A guard that only moved, into a helper the methods now share, onto another index or into a
`LUNATIK_PRIVATECHECKER` that checks its class and reads the object as `private`, is paired with
the added line that took it in and not reported; both checks read `guards.sh`, where the pattern
and the pairing live.

`idioms.sh` reads a C file for idioms the tree settled: a `luaL_argerror` as the body of an `if`, which is a wrong value at an index and
`luaL_argcheck`'s; a check followed by `lunatik_throw` with nothing between, which `lunatik_try`
already spells when nothing is held; a `luaL_argcheck` condition repeated across methods, which is
one helper; and a version a feature needs written as one release, "needs a 6.10 kernel", where the
message means that release and every one after it. It also names an `is` or `has` predicate written
as a `static inline` whose body is one `return`, which the tree spells as a macro, and an `if` whose
two arms call one function, which is a ternary. It runs at edit time and over a pull request's diff.
It names an `is` or `has` predicate macro spelled
with `?:`, which reads as two rules where an `||` of the exception and the rule reads as one, and a
loop header a file spells twice, which a foreach macro names, as `lunatik_foreachruntime` does. It names
a value a function computes before a check that raises and does not read it, which decides before
validating, and a load of one mode, which refuses what `require` and `load` take. It annotates rather than fails, since the release-then-throw shape is not `lunatik_try`'s and the line
between the check and the throw is what the reader decides on.

`function-shape.sh` reads a C file for the shapes of a function that is more than one job, in the functions the diff against `CHECK_BASE` touches: a lock taken at
more than one site of one function, where the section between is a helper of its own; an allocation
and a raise in one function, where a buffer a raise passes is freed on every raise path and a
userdata the collector frees is the shape; a function past forty lines or nested past two blocks,
which is more than one job; and a per-item buffer sized by a maximum, `n * LUARCU_MAXKEY`, which is packed by each item's length. The check annotates: a lock
retaken after a wait is a shape the reader decides on, and the review answers each line it prints with
the function's jobs listed and the fixup that splits them or the reason they are one.

`core-helper.sh` reads the lines a change adds to a C file, against `CHECK_BASE`, for three in a row
inside a function whose calls another C file of the tree already makes in the same order, read with
the arguments left out: the sequence is one helper, in `lunatik.h` when its calls are the core's, as `lunatik_pushfail`
spells `lua_pushnil`, `lunatik_pusherrname` and `return 2`. It runs at edit time and over a pull request's
diff and annotates, since two encryptions that set up one request each are two callers of the
kernel's API and not a helper missing; the review answers each line it prints with the helper or
the reason the calls are the kernel's sequence.

`deferral.sh` reads the lines a change adds to the C of the core or a binding, against `CHECK_BASE`,
for a deferral: an item of `lunatik_defer`, a work, an irq_work or a tasklet. A hazard is refused in
its context before it is engineered around (AGENTS.md, *Deciding what to change*). It runs
at edit time and over a pull request's diff and annotates, since the core's deferred close is the
kernel's answer to a release in atomic context; the commit body names the refusal each line it
prints was weighed against.

`comment-siblings.sh` reads the lines a change adds, against `CHECK_BASE`, for a comment on one
definition of a block whose other definitions carry none: a run of `#define` lines, the members of a
struct or a union, or a run of Lua `local NAME <const>` lines. Either each has a reason worth a line
or none does, and the reason they share goes in the commit body. It runs at edit time
and over a pull request's diff and annotates, since a definition can hold the one constraint its
siblings do not.

`lua-style.sh` reads a Lua file for the shape rules of `.agents/rules/lua.md` a line-based read can find: an `if`/`elseif` whose branches repeat the same steps, which is a dispatch table
or a helper; one table of arguments spelled at two call sites, which is declared once; and a
function of more than one statement written inline as a table field, which is a named local
function. It runs at edit
time and over a pull request's diff and annotates rather than fails, since two registrations that
share three fields can be two different hooks. It also names a block of four lines or more that a
change adds, read against `CHECK_BASE`, and a script beside it already carries, which is a module they share.
It names a module a file requires twice, which one local holds, as `.agents/rules/lua.md` asks of `linux.genl`.

`test-harness.sh` reads a test's Lua script as well as its `.sh`, for a case the script runs under a
condition: when the condition is false the case reports nothing and the script's one KTAP line
counts it as passed, so the skip is decided in the `.sh`, where it is a `# SKIP` line. It also names a script that takes
`test` from a module other than `tests.lib`, which a merge that does not conflict leaves calling nil.
`kthread.sh` names a loop on
`thread.shouldstop()` whose body has no pause it can see; it knows a pause by its name, in the loop or in a function of the same file the loop
calls, so one behind another module reads as none, and the review decides.

`recursion.sh` compiles the objects `Kbuild` links from `lua/` with the host compiler and the
configuration `lunatic` takes, reads GCC's call graph (`-fcallgraph-info`) for its cycles, and names a
recursion that never reaches `luaE_checkcstack` or `luaE_incCstack` and that its ledger does not bound,
with what one level costs on the host; each ledger entry says what bounds a recursion, read in its
source. It runs when a change touches `lua/`, `lunatik_conf.h`, `lunatik_aux.c` or its ledger: a recursion that
compares nothing is invisible to a budget read where `LUAI_MAXCCALLS` is compared.

`luals.sh` reads the Lua files given with lua-language-server and the tree's `.luarc.json`, and names a
local or a function declared and never read and a global assigned where a local was meant; a `require` nobody reads loads its module into the kernel and keeps
it there for the runtime's life. The configuration turns off what the server infers about types the
bindings' C never declares to it, and says why beside each. It runs at edit time and over a pull
request's diff, and says so where the server is absent.

`author-email.sh` reads a rev-range and names a commit whose author email is not the one the base
uses most for that author's name: a rebase or a squash done from another checkout signs the result
with that checkout's identity. A review and a pull request's preparation run it over
`origin/master..HEAD` before anything is pushed.

A rule is what remains when nothing else can catch the mistake. Where the error is mechanical, the gate
is the answer and the rule is that gate's documentation: a pull request that only writes down what went
wrong, over rules that were already written and already broken, adds a paragraph and changes nothing.
What an investigation teaches lands here, in a skill or in a check, in the same breath as the work that
taught it; a lesson kept in one assistant's notes is one the next contributor pays for again. A rule or
a check that lands is run that day over the open pull requests it reaches, and each one it names gets
a fixup or a reason.

`pr-body.sh` takes a pull request body file and fails it on more than three paragraphs, an em dash,
a "Test plan" section or an assistant's footer; `pr-body-guard.sh`, wired before a shell call like `crash-guard.sh`,
blocks a `gh` write to pulls that carries a body file the check fails on, or that `machine-leak.sh`
finds the machine in; a body it cannot read is refused rather than skipped, as in the review guard below.
A write to a pull request's reviews or comments is that guard's and not this one's, since a review body
runs past three paragraphs by design. A write to issues takes this guard too, since the implement-issue workflow
opens and edits issues from what its agents leave and its prompt asking for the checks enforced none;
`untraced.sh` stands in there for `pr-body.sh`, whose paragraphs and Closes line are a pull request's.
A release takes it as well, through `release-body.sh`, which keeps the em dash, `untraced.sh` and
`decision.sh`, adds the maintainer's rule for public notes, nothing promised of the API or of a release
to come, and drops the three paragraphs, since notes run as long as the release.
An edit is read for the lines it adds to the body GitHub has, asked with the credential the command
carries, so text a reporter posted is no edit's to rewrite. When GitHub does not answer, the whole body is read. This guard and the review
guard read a write in every spelling gh takes of it: `new` beside `create`, `-R` before the verb, `-F`
and `-b` on `gh pr` and `gh issue`, `--notes-file` and `-n` on `gh release`, a field attached to its
flag, and the JSON `gh api --input` sends,
whose other fields go through `machine-leak.sh` too; `gh issue comment` is the review guard's. A
write whose text no guard reads is refused: one through curl to GitHub's API, and a GraphQL mutation
other than the textless ones the skills run. GitHub is written through gh, and where gh is absent the
implement-issue workflow reads through curl and writes nothing. An issue a write opens is read by
`contract.sh` too, which refuses a finding whose stimulus reaches into the runtime's own bookkeeping,
out of contract by the honest-mistake bullet of AGENTS.md, *Deciding what to change*. `CONTRACT_OK=1` opens it where a script using the API as
documented reaches the same path. A new issue carries its severity as the repository's label, which
the guard refuses to open it without.

`rewrite-guard.sh`, wired before a shell call, refuses a forced push of a branch other branches are
based on, naming them: they keep the commits the push drops, and those surface later as a duplicate
of a commit that no longer exists, in a pull request nobody edited. `REWRITE_OK=1` runs it once that
list is known to be stale.

`stacked-guard.sh`, wired before a shell call, refuses opening a pull request on a base other than
`master` unless it opens as a draft. GitHub does not merge a draft, and nothing else stops a stacked
pull request merged before its base from going into the base's branch. A pull request moved onto such a
base is made a draft first, `gh pr ready --undo <n>`, which the guard asks GitHub.

`fixup-guard.sh`, wired before a shell call, refuses opening a pull request whose head, compared on GitHub
with its base, carries a `fixup!`, `amend!` or `squash!` commit: a pull request reaches the maintainer's first
review squashed, and a fixup is how he reads what changed after it. `FIXUPS_OK=1` opens one that is not the
first he reads.

`fixups.sh` names the `fixup!`, `amend!` and `squash!` commits of a rev-range, and the `Checks` workflow
fails on a pull request that carries one, so a pull request merged before its squash shows red rather
than landing its fixups on master.

`stage-guard.sh`, wired before a shell call, refuses staging the whole tree, `git add -A`, `--all`, `-u`,
`--update`, `.` or `:/`, and `git commit -a`: a commit is staged by purpose, and a tree an edit left with
several changes in it otherwise fuses them under a message that explains one. `STAGE_OK=1` stages a tree
that holds one change only.

`luals-guard.sh`, wired before a shell call, refuses a push whose tree adds, on a line its branch
introduced against the merge base with `origin/master`, what `luals.sh` reads as a slip; what the branch
inherited is not the push's to fix. `LUALS_OK=1` pushes a name that is the code's on purpose.

A check ships proved, the way a test does: run it against the mistake it is for, and against a case
it must pass. A condition that cannot fire reads as protection and is none, and nothing downstream
catches it.

`lunatik-lock.sh`, wired before a shell call, refuses a command that touches the device, an install, a
reload, a run, a `list`, `-V`, the REPL on a pipe or with `-e`, or a suite, while another operation is on
it, naming the processes it found; a process in
D state among them is the wedged device, which no waiting clears. `LUNATIK_LOCK_OK=1` overrides it once
what it lists is known to be stale. What a command runs is read by `commands.sh`, which the command
guards share: a CLI verb, `make install`, a test script or `watchdog.sh` counts when it is the command,
read through `sudo` and `env` with their options, `tools/lunatik-host` and a shell's `-c` string, and
not when it is handed to `git`, `grep` or a check, to a shell's `-n`, which reads it and runs nothing,
or written into a file by a heredoc. The post guards read through it too, the `gh` command that writes and not the raw input; the approval marker counts only in the command. A cycle a script file runs names nothing a
text can read, so it goes through `tools/lunatik-host`, whose lock orders it against the cycles that
take it too.

`tools/watchdog.sh` runs a script and stops it when the host loses the connectivity it had before the
run, comparing against the loopback and the default route's gateway and holding nothing against the
script that was already unreachable; a stop that does not return is a wedged device, which it reports
and only a reboot clears. `example-guard.sh`, wired before a shell call, refuses `lunatik run` and
`spawn` of anything under `examples/` that does not go through it, unless the command carries
`NETWORK_LOSS_OK=1`: an example arms real hooks on the machine that runs it, and one that cuts the
network off cannot be stopped afterwards, because the command that would stop it has nowhere to be
typed. The guard keys on loading an example, not on the name of one already known to misbehave.

`consumers.sh` names the out-of-tree scripts that load a binding the changed files touch, reading the
clones listed in `LUNATIK_CONSUMERS`; `consumers-guard.sh`, wired before a shell call, blocks opening or
editing a pull request that changes such a binding until the command carries `CONSUMERS_OK=1`, set once
those scripts were read. A product built on Lunatik is a consumer this tree cannot grep. A failure reported from a consumer's
build is read from that build's own configuration before any mechanism is theorised.

`examples-touched.sh` and `consumers.sh` read what a change reaches through `modules.sh`: the module a
file defines, read from the base when the change deletes it, and every module a script reaches it
through without requiring it, a library that requires it, as `netlink` reaches `netlink.rt.route`, and
a binding that builds its objects for a callback, as `netfilter` and `tc` hand an `skb`. A change to the
runner adds the examples a README starts with the CLI verb whose function it touches, and one to autogen
the `linux.*` tables its specs feed. The CI annotation reads the files a pull request adds or modifies, so a deleted module is named by the guard
and the pull request's preparation, which read the whole diff.

`machine-leak.sh` reads a tracked file for what belongs to the machine it was written on: an absolute
path in a home directory, a password handed to sudo, a credential read out of a file or carried inside a
URL, a literal shaped like a token, and the name of a private repository, which it takes from
`LUNATIK_CONSUMERS` and never spells itself, so that rule is silent where the variable is unset. It is a
gate and not a nudge, so it fails the commit and the run rather than annotating them: what is committed
is read by everyone who clones, and a credential committed once is a credential rotated. It reports the
file, the line and the rule, never the text it matched, which would otherwise reach a terminal and a CI
log. What belongs to one machine lives in that machine's environment or in its untracked
`CLAUDE.local.md`, and reaches the tree as an argument whose default names no host.

`tools/pr-status.sh` prints the open pull requests as GitHub has them: base and whether it still merges,
commits and how many are unsquashed fixups, the size, the CI conclusion, and the labels; `--ready` keeps
the ones a maintainer can pick up. What GitHub cannot see is whether anyone read one, so the review
workflow labels what it finished with `workflow-reviewed`, and a pull request without that label has
had no second reader. Which pull requests are open, reviewed or ready is read from it, not from memory.

`tools/issues.sh <epic>` prints the issues an epic tracks as GitHub has them: the epic and each issue
whose body says it is part of it or that the epic's task list names, its state, and the pull
requests whose body names it with what each does to it, flagging an open issue a merged pull
request names and a merged pull request that closes none. An issue closes, and its card on the
project board moves to Done, only when a merged pull request
says `Closes #N` or someone closes it by hand. A pull request that finishes a phase carries `Closes #<phase
issue>`, one that finishes none says `#<epic>, which it does not close`, and `pr-body.sh` fails a body
that says Part of, Top of, Bottom of, Answers or reported as and does neither. After the maintainer
reports a merge, the session runs `tools/issues.sh` over the epic, closes what the merge finished and
GitHub left open, an issue the pull request only named or an epic whose issues are all closed, and
hands him in the same message what closed and what stays open; the board moves a card with its issue.
What a release still lacks is read from the same report, the epic's task list included.

`review-post-guard.sh` reads the tool command on stdin instead of a file, for an assistant wired
to run it before a shell call (`PreToolUse`): it blocks a `gh` write to reviews or comments on a
pull request the posting account did not open unless the command carries the `REVIEW_POST_OK`
marker, set once the exact text has been shown to the maintainer and approved, or when the text
gives a fixup reference as a backtick'd SHA, which renders as code and does not link. The marker
forces the show-then-post step; it cannot check that the text was shown, only that it was set on
purpose. A pull request the posting account opened is the maintainer's own, and its review needs no
marker: the guard asks GitHub who opened it, with the credential the command carries, and asks for
the marker whenever it cannot tell. The text goes through `machine-leak.sh` before
the marker is read, since the marker approves the wording and not what the wording carries, and text
the guard cannot read, passed inline or on stdin, is refused rather than skipped. Every text it lets
through opens with `(posted by an agent, not by @<handle>)`, the review body and each inline comment
alike, since the account is the maintainer's and an inline comment stands alone in the conversation. A post it holds for
the marker is recorded for the session, and `pr-body-guard.sh` refuses an edit that adds text other
than a task to the body of the same issue or pull request until the marker is set, so the approval is not skipped by another route. A
comment given to gh's `close` or `reopen` is refused as text no file carries, since that route has no
file to read.

`untraced.sh` reads a text about to be published, a review, a comment, a pull request body, for the
word that names a failure nobody read: a failure that comes and goes is read in the journal around the
failing run, `tools/journal.sh` prints every unit's lines in that window, and the text names the
mechanism or carries a hypothesis with what was not captured. `pr-body.sh`, `review-post-guard.sh`
and, on an issue body, `pr-body-guard.sh` run it.

`decision.sh` reads the same texts, where the same three run it, for a decision handed to the
maintainer without the question, two options and a recommendation (AGENTS.md, *Deciding what to change*): it
keys on the phrase that hands one over, "the maintainer's call", "é decisão sua", "levo isso a
você", and asks the text around it for the three. A reply in the session is where the maintainer
read "é decisão sua", so `.claude/hooks/on-stop.sh`, the Stop hook, runs it over the reply a turn
ends on and sends one that fails back once, passing the stop after it (`stop_hook_active`). A decision reported as taken, "foi decisão sua", "por decisão sua", hands nothing over and passes.

`reboot-capture.sh` reads the same reply in the same hook, for a request for a reboot the checkout
holds no capture for. `tools/prereboot.sh` saves what a reboot erases for every session on the host,
and the others learn of the reboot when it is done, so the session that asks runs it. It
keys on the phrase that asks, "preciso que você reinicie", "can you reboot"; one that says what only a
reboot clears, "só um reboot resolve", "needs a reboot", counts only while the host is stuck, a module
`pinned.sh` names or a `lunatik` process in D state, since on a sound host it describes what a bug
would leave. It passes when `scratch/reboot-*` holds a capture taken in the last hour.

`push-guard.sh`, wired before a shell call, refuses a `git push` in a command that also runs a
rebase, a merge, a cherry-pick, an am or a revert, and one from a tree with any of those in progress:
the one that stops on a conflict leaves HEAD on the base with the branch's commits still to apply,
and a push chained after it publishes that base as the branch. The push is a command of its own, after `git status` has
been read; `PUSH_OK=1` overrides the guard for a push meant while a rebase stays paused in another
tree.

