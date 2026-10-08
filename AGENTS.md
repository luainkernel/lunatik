# Working on Lunatik

Conventions for contributors, and for AI coding assistants working on this repository. If you are
using an assistant that reads a project file automatically (`AGENTS.md`, `CLAUDE.md`, `.cursorrules`),
point it here.

Lunatik runs Lua inside the Linux kernel. A mistake here does not raise an exception, it panics a
machine. Two rules follow from that and outrank everything else in this document:

1. **Verify, do not assume.** How the kernel behaves is read in its source, not inferred from a
   measurement: which CPU a hook runs on is answered by `NF_HOOK`'s callers, and a run on one host
   confirms that reading, it does not replace it. Before using a kernel API, read its declaration in
   `/usr/src/linux-headers-$(uname -r)/include` and confirm it is exported in `Module.symvers`. A
   kernel interface read at runtime rather than linked — a `/sys` or `/proc` path and the format it
   returns, the `/dev/lunatik` protocol — is held to the same rule: confirm it against the source
   across the supported kernel range (6.6 and later), not from the one kernel you happen to run.
   Signatures and formats change between releases. If you have not checked, say so instead of
   asserting.
2. **Know your execution context.** Code that may sleep must not run from softirq or hardirq context.
   See "Execution contexts" below.

## Layout

| Path | What lives there |
|------|------------------|
| `lunatik_*.c`, `lunatik.h` | core runtime, object model, C API |
| `lua/` | the Lua fork (luainkernel/lua): upstream's git mirror plus the `_KERNEL` patch, which only modifies, `#ifndef _KERNEL` with upstream first; code the kernel side needs is added on the Lunatik side, `luac/` included, never to the fork |
| `luac/` | the luac fork (luainkernel/luac): the release tarball's `luac.c`, which the git mirror does not carry, plus the `_KERNEL` patch; a bump is an "update to Lua x.y.z" commit made from the tarball |
| `klibc/` | the klibc fork (luainkernel/klibc): upstream's tags mirrored, and per release a `klibc-x.y.z-kernel` branch, upstream's tag plus Lunatik's two setjmp patches (arm64 saves x18, x86_64 returns through the retpoline and rethunk thunks), which the fork's `lunatik` branch follows; the tree links only each architecture's `setjmp.S`, `archsetjmp.h` and `archconfig.h` and libgcc's 64-bit division helpers, so a bump is read against those files |
| `lib/lua*.c` | kernel modules, one `.ko` each, exposing a Lua module |
| `lib/*.lua`, `lib/*/*.lua` | kernel side Lua libraries, installed to `/lib/modules/lua/` |
| `autogen/` | build time generation of `linux.*` constant tables from kernel headers |
| `bin/lunatik` | userspace CLI, talks to the kernel through `/dev/lunatik` |
| `tests/` | KTAP integration tests, one directory per suite |
| `examples/` | example kernel scripts |
| `tools/` | maintenance scripts, and the mechanical convention checks in `tools/checks/` |
| `.agents/skills/` | the recurring workflows packaged as agent skills (open `SKILL.md` format) |
| `.agents/rules/` | the rules for a kind of file, loaded by the paths each one names |
| `.agents/agents/` | the agents a workflow runs a narrow job in, the host's and GitHub's |
| `doc/` | all documentation: the guide pages (`doc/guide/`), the hand written C API reference (`doc/capi.md`), design notes (`doc/design/`), the site's style (`doc/style/`), and generated LDoc output (everything else, gitignored) |
| `doc/design/` | design notes for work in progress: gap analysis, proposed APIs, verified kernel references, test strategy |

All documentation lives under `doc/`. There is exactly one documentation directory: never create a
second top level one (`docs/`, `documentation/`, and the like). A guide page goes in `doc/guide/` and in
the `topics` of `config.ld`, design notes go in `doc/design/<topic>/`, the C API reference is
`doc/capi.md`, and LDoc fills the rest of `doc/`. The README is the site's home page: what it does not
say in a few lines links to a guide page.

A module or an example that needs a second file gets a directory, not a prefixed sibling:
`examples/systrack/probe.lua` beside `device.lua`, never `systrack_device.lua` beside `systrack.lua`.

## Build, install, test

    sudo apt install linux-headers-$(uname -r)     # after a kernel upgrade
    make                                           # build every module
    sudo make install                              # scripts, modules, examples, tests
    sudo lunatik reload                            # reload the modules
    sudo lunatik test                              # run every suite
    sudo lunatik test <suite>                      # run one suite

Use `sudo make install`, not the partial `*_install` targets. Use `sudo lunatik reload`, never
`rmmod`: the CLI knows the dependency order and unloads cleanly. What the shared host does to a cycle,
a module that will not unload, a wedged device, a stale install, is the lunatik-cycle skill's.

Never run two `lunatik` operations at once. Concurrent operations wedge `/dev/lunatik` and leave
processes in D state. `ps` answers for the instant it ran, which is no help when another session
starts a second later, so a build-install-run cycle takes the lock instead:

    bash tools/lunatik-host sudo lunatik test
    bash tools/lunatik-host bash tools/watchdog.sh examples/systrack/device

It runs the command with the lock held, names the holder while it waits, and releases on exit
however the command ends. The installed tree under `/lib/modules/lua` is shared too: a suite run
whose totals do not match the tests in your own worktree is a mixed install, one session's modules
against another's scripts, and it measures neither.

A worktree named for a task may belong to another session on the same machine. Check
`git worktree list` and the branch a worktree holds before a checkout or a reset there, and never
reset a branch checked out elsewhere. A review, or a build of a branch not your own, runs in a
worktree created for it (`git worktree add`, then `git submodule update --init`) and removed at the
end, with `rm -rf` and `git worktree prune`, since `git worktree remove` refuses a tree with
submodules. Each one left behind carries a build on the disk every session shares, and a build that
stops halfway on a full disk leaves the previous install in place for the suite to measure:
`tools/checks/disk.sh` fails below a free-space threshold and names the largest worktrees, and
`tools/lunatik-host` runs it as a warning before every cycle. A `git checkout` carries what is
uncommitted onto the new HEAD, where an edit made against the old base reads as a change to the new
one: switch branches in a tree with nothing pending, or read the other branch in a worktree of its
own. `git stash` has no place here at all: the stack belongs to the repository and not to the
worktree, so `stash@{0}` is usually another session's work and the pop that follows spreads its
conflicts over your tree. Set work aside with a commit, and compare two revisions with a worktree or
`git show <ref>:<path>`. What a worktree holds built and not run is code nobody ran: a cycle run in
a worktree not your own installs its author's untested edit, and an edit left built while its author
waits on a question is a crash any session can trigger. An edit is built, installed and run in one
step, or reverted before the session pauses. A session's scratch worktrees live under `scratch/wt/`, since the
reboot such a crash forces clears `/tmp` and every tree it held, and a script a cycle reruns lives
under `scratch/` for the same reason; `tools/lunatik-host` names one it runs from `/tmp`.

A tree with a conflict pending (`git status` showing `UU`) is not a test subject: a suite run over a
half-applied rebase or cherry-pick measures neither side. Resolve and commit, then build.

### Checks

`tools/checks/` holds the mechanical checks, and `.agents/rules/checks.md` says what each one reads, the
mistake it is for and the guard it backs.

### Skills

`.agents/skills/` packages the recurring workflows — the build/test cycle, a new binding, a new
test suite, preparing a pull request — as agent skills in the open `SKILL.md` format
([agentskills.io](https://agentskills.io)), discovered by any compatible assistant. Each one
defers to this file as the authority and orders the steps; none replaces reading it.

For Claude Code, `CLAUDE.md` imports this file, `.claude/settings.json` runs the command guards
and the file checks as hooks, and `.claude/skills/` links to `.agents/skills/`; nothing there holds
logic of its own. Those files, and an untracked `settings.local.json` beside them, bind every
session opened on the checkout rather than the one that wrote them: a `permissions.deny` added
there to sandbox one session's agents denied another session's commands, with no hook error to
point at the cause. A sandbox belongs in an agent definition, or in a session started with its own
permission mode. The checkout sessions start in is what every session and every agent it launches
loads, this file, the skills and the guards, so it follows master: `checkout-behind.sh`, which
`.claude/settings.json` runs as a session starts, prints how far its HEAD is behind `origin/master`
and the `git merge --ff-only origin/master` that brings it level, and the session runs that merge
when the checkout has no commit of its own and nothing tracked changed. It fetches nothing, since the
remote-tracking ref is shared by every worktree's fetch.

An agent that works on this tree runs through the Workflow tool, whose `agent()` takes the model and
the reasoning effort, and the maintainer's opt-in to workflows stands here: the Agent tool takes a
model and no effort, so what it launches runs at the default effort whatever was asked. `agent-guard.sh`, wired before the Agent tool, refuses every type but a read-only search
and the Claude Code guide; `workflow-effort-guard.sh`, wired before the Workflow tool, refuses a script
whose `agent()` calls never name an effort. An agent a running workflow waits on is not messaged: the
message resumes a copy of it from its transcript, which runs beside the original in its worktree and on
the host.
`send-guard.sh`, wired before SendMessage, refuses one whose run's journal holds no result for it; what
its report asks for is done outside it, on the host or in an issue, or by stopping the workflow and
relaunching it with notes.

An issue goes to agents through the implement-issue skill's workflow: an implementer commits the
change, review-pr's workflow runs over the branch nested, so a review runs one way whoever launches it,
and its build is the one run on the host, in an agent of its own, before the pull request opens. An
agent's context is paid for on every turn it takes, so the work that only waits on the host, or only
writes to GitHub, runs in the agents `.agents/agents/` defines, which load no CLAUDE.md and run on a
smaller model. The implementer's prompt names the rule a step needs and restates
none: every agent loads this file, and a rule pasted into a prompt is a copy the next change here
does not reach.
What the implementer and the review leave as issues, their `findings_left`, the workflow files as its
last stage, each under its severity label or appended to the open issue it belongs to, so no finding
waits on a session to copy it out and the numbers come back with the result. An entry quotes the
contract its severity was read against, which the issue carries as a `Contract:` line. The implementer's
answer and the review's hunt each carry the smallest shape beside the size of the diff and what every
mechanism past it buys, and the hand-back shows it.

### Running a script

    lunatik run [--context=softirq|hardirq] <script>   # one shot
    lunatik spawn <script>                             # in a kernel thread, always sleepable
    lunatik stop <script>
    lunatik list

Scripts are resolved under `/lib/modules/lua/`. The CLI loads the kernel modules a script needs by
itself, through `require()`. Never tell a user to `modprobe lua*` by hand.

`lunatik run`, `spawn`, `stop` and `list` exit 1 when the kernel refuses them, with `lunatik:` and
its message on stderr and nothing on stdout, and a wrong invocation exits 2 with the usage on stderr.

## Execution contexts

A runtime is created in one of three contexts, and this decides what its code may do:

| Context | How | Allocation | Lock | May sleep |
|---------|-----|-----------|------|-----------|
| process | default, and always for `spawn` | `GFP_KERNEL` | mutex | yes |
| softirq | `lunatik run --context=softirq <script>` | `GFP_ATOMIC` | `spin_lock_bh`; `spin_lock_irqsave` with IRQs already off | no |
| hardirq | `lunatik run --context=hardirq <script>` | `GFP_ATOMIC` | `spin_lock_irqsave`, always | no |

Netfilter and XDP hooks need a softirq runtime, kprobes a hardirq one: a kprobe fires wherever the
probed code runs, an interrupt handler included, and there it would spin forever on a runtime lock
its own CPU holds unless that lock turns interrupts off.
A softirq object reached with IRQs already off, as an `rcu.table` written from a kprobe handler is,
locks with `spin_lock_irqsave`: a bottom-half unlock there runs the pending softirqs inline, inside
the probe.

The script body itself runs once at runtime creation, in process context, before the runtime is armed.
So registering hooks at the top level of a `softirq` script is legal and may sleep. Everything that
runs later, from a hook, may not.

Use `lunatik_cannotsleep(L, ...)` to reject a sleeping entry point called from an IRQ context runtime
rather than letting it deadlock the machine.

Which runtime of a percpu script a callback reaches is the CPU it fires on, and nothing else ties a
flow to one of them: the packets of one connection reach several. State that must see a whole flow
belongs in what the runtimes share, the runtime holds what is per-CPU. Which CPU each path lands on
is traced in `doc/guide/03-percpu.md`.

### Kernel threads

A script for `lunatik spawn` must return the thread body, poll for a stop request, and yield.
Violating any of these hangs the machine:

    local thread = require("thread")
    local linux  = require("linux")

    return function()
        while not thread.shouldstop() do
            -- non blocking work only
            linux.schedule(100)
        end
    end

The thread body runs holding the runtime lock, and `stop()` waits for it to return. A stop ends a wait
that reads signals: `kthread_stop()` sets `TIF_NOTIFY_SIGNAL` on the task before it wakes it, so a
`sock:receive()` with no timeout returns `ERESTARTSYS`, a `linux.schedule()` returns early, and a wait
for another runtime's lock, in `resume`, `stop`, `thread.run` and every monitored method, raises
`EINTR`. One thing it does not end, and it makes the thread unstoppable: a wait that goes back to
sleep without reading a signal, the lock a `device` file operation or a kernel call takes among them.
The runtime that calls `thread.run()` keeps the thread and stops it as it ends, so a worker another
body starts and drops ends with that body's runtime, as `examples/echod`'s workers do; an end made
on the thread's own body leaves the thread to run until that body returns.

A body that races another thread, a stress, pauses once per slice of its running rather than once
per turn: `linux.schedule()` sleeps until a timer fires whatever the timeout, 0 included, so a pause
per turn starves the race the stress is for.

## Rules by path

The rules for a kind of file live in `.agents/rules/`, each opening with the paths it governs, and Claude
Code loads one when a file it reads or edits matches, through `.claude/rules`, which links there. Another
assistant reads the ones whose paths match the files it touches.

## Deciding what to change

Code on `master` is not settled. When a new design makes an existing mechanism simpler, or subsumes
it, change or remove it. Working around it to keep a diff small leaves two mechanisms doing one job,
and every later change has to serve both. Authorship is not a reason to keep code, and neither is how
recently it was merged; a commit that removes or subsumes something already on `master` names it in
the body.

The first shape of a fix is the smallest change that makes the observed defect unreachable, and
every mechanism past it is named with what it buys that the small one does not. A structural
answer the kernel offers is not the smaller one by being structural: four lines that decline a device
of another namespace in the handler fixed #797, where moving the netdevice block to the per-namespace
chain took a macro signature, two wrappers and an API newer than the tree's floor. Write the
small shape down first, even when the larger one is chosen, so the choice is a comparison and not a
default.

The comparison starts in the kernel. Before a mechanism is written over a kernel primitive, the
kernel's own answer to the same problem is read, `Documentation/` for the family and the primitive's
users under `lib/` and `kernel/`, and the commit body names the facility the shape was compared with,
or the page that offers none: a reader that must block has SRCU, a walk that drops the lock has the
contract the comment on `rhashtable_walk_enter` states, and a deferral of frees while readers sleep,
written by hand, is SRCU again. `tools/checks/kernel-answer.sh` names a commit whose body carries no
such comparison.

Reshaping or renaming an API means updating every consumer, grepped for — including consumers in
stacked or sibling pull requests that will rebase onto the change. A caller left on the old shape
compiles against a Lua module and only fails when its code path runs. The grep is taken on the
branch's own base when the change is written, not from a read made earlier in the session. Every example
`tools/checks/examples-touched.sh` lists for the changed files is named in the pull request body
with what it did, ran, only loaded or not run and why; `tools/checks/examples-named.sh` fails a
body that leaves one unnamed, and `pr-body-guard.sh` runs it when a pull request opens.

The same holds for a value, not only a name. A change that keeps its own copy of something another
field carries, because the kernel rewrites the original, has decided the two can differ:
`luaprobe_t` keeps the address the script gave in `requested` because `register_kprobe` rewrites
`kp.addr`, on x86 with IBT past the ENDBR. From then on every reader of the original is a decision,
which of the two it wants. Grep the readers of what the change
duplicates and settle each one, and read an architecture the host cannot run for every use, not only
the one the diff touches. `tools/checks/shadowed-readers.sh` lists the readers.

A primitive every class inherits, the lock, the allocator, the context check, is changed for the
caller that needs it, in the arm that caller takes. Widening it to every arm because that is simpler
is a contract change for the callers that were already correct, and it belongs in the first line of
the commit body, naming what moves, never in a footnote of the pull request. A kprobe handler writing an
`rcu.table` needs interrupts off, and #891 keyed that on `irqs_disabled()`, the kernel's own rule,
leaving netfilter and XDP under bottom halves. `tools/checks/blast-radius.sh` lists what a changed
primitive reaches, on the file it left as well as the file it arrived in. A bound on what every
script shares, the kernel stack the C budget prices among them, is measured over the forms the tree's
own tools ship a script in as well as over the suite as installed: chunks `lunatic` compiles, which
`BYTECODE=1` installs, and modules `tools/shade.sh` encrypted, required in chains. It holds where the
resource is spent, not where the bound is read: a recursion that consults nothing is outside it
whatever the measurement showed, and `tools/checks/recursion.sh` lists the ones in the Lua the kernel
links.

The kernel a consumer builds on bounds what a change may use, and not every consumer sits inside
the range this file declares: a product built on Lunatik can ship on an older vendor kernel. An API newer than a known consumer's kernel is a decision taken here, with the floor it sets
named, not one discovered at that consumer's build.

* Do not land an implementation you already intend to replace. A guarantee that holds only on some
  paths is not a guarantee: make it structural or do not offer it. Merging a half measure and opening
  a follow up that deletes it pollutes the history across pull requests the same way a commit that
  undoes another one pollutes a branch.
* Removing a check as redundant is verified, not asserted: trace the invariant to whoever establishes
  it and confirm every path that sets the value does. `invoke`'s type check is redundant because
  `attach` validates the callback first, so it is always a function there; a `pcall` that would catch
  a bad value anyway is a second reason, not the trace. A binding's Lua half establishes invariants
  the same way: where it guarantees a precondition, the C takes it, and what stays in C is the check
  whose absence crashes the kernel. That is what the split is for, and re-validating in C undoes it.
  A context that makes a family of refusals unreachable removes those it covers, route by route, and
  keeps the ones its rule leaves open; a mechanism a removal makes necessary is the removal going past
  what the trace showed. `guards.sh` counts the context checks, `lunatik_checkarmed`,
  `lunatik_checkrtnl`, `lunatik_checkowner` and `lunatik_checkirqs`, so `guard-removed.sh` names one
  a change drops.
* A function's contract — that it only reads, that it never sleeps, what it returns — is read from its
  body, not inferred from its name or its place in a method table. `connmark` reads and writes through
  one overloaded method despite sitting among read-only accessors; calling it read-only from where it
  sits is a guess, not a trace.
* Refusing is a legitimate outcome. When a combination has no sound semantics yet, refuse it where it
  is registered, with an error that names the reason, rather than shipping an approximation. Lifting
  the refusal afterwards is one line and a test. The reason is written where the refusal is made, so
  the change that removes it finds the refusal and lifts it; `tools/checks/idioms.sh` names a load of
  one mode.
* A hazard is refused before it is engineered around. Where a context makes an operation unsafe, the
  operation is refused in that context, and a context is made where none names it yet; a deferral, a
  queue or a worker that keeps the unsafe call working buys a capability, and is weighed as one against
  the refusal that makes the hazard unreachable. A netdevice callback runs under RTNL, and a softirq
  runtime closes that family: nothing in it sleeps, so nothing waits on RTNL, and `lunatik_checkarmed`
  refuses under RTNL the replay the registration delivers before the runtime is armed.
* A prohibition and a capability are two things. Where the safe form of an operation needs a facility
  a later kernel adds, the binding refuses the operation where the facility is missing and uses it
  where it exists, behind a version guard, and does not reimplement it: a copy of the kernel's answer
  written here is a mechanism every later change serves, and it outlives the releases it was written
  for. `print` under the runqueue lock is refused, not buffered and flushed from a worker, since no
  release through 6.17 exports `printk_deferred` to modules.
* A guard keys on a property that is true by construction where it is enforced, never on a proxy that
  merely correlates. That a registration is global is such a property. A netfilter hook number is not:
  the same hook runs in softirq or in process context depending on the path the packet took.
* A refusal is written for the resource, not for the entry point that showed the hang: the matrix it
  is held to lists every route from Lua to the lock or the call it protects, found by grepping what
  acquires it, `lunatik_lock`, `lunatik_closeprivate`, `lunatik_run` or the kernel call, and each
  route names its refusal or why it needs none. A refusal of `runtime:stop()` for the
  runtime's own lock covers `runtime:resume()`, `percpu:resume()` and `thread.run` too, which take
  it. The routes are everything the path runs while it holds the lock, the binding's own calls among
  them, not only what a script calls: a raise the dispatch logs is a printk under that lock.
* A guard in the core is for the honest mistake: the wrong object at an index, a size no binding can
  serve, a call that sleeps from a hook. The registry, a class metatable and an object's `__gc` are
  the runtime's own bookkeeping, and a script that reaches into them, `obj:__gc()`,
  `debug.getregistry()`, `getmetatable(obj).__gc = nil`, is out of contract, as one that spins in a
  hook is: root loaded it on the machine it breaks, and no guard closes that. A finding whose stimulus
  is such a script closes as not a defect, whatever it traces from there.
* A change that puts a route out of contract, a prohibition the binding's documentation now states,
  reads the open issues filed on that route in the same breath: one whose stimulus the prohibition
  covers is a capability and not a defect, relabelled or closed with the reason.
* A decision taken with the maintainer is not reversed alone. When the investigation that follows points
  the other way, that is a question to bring back, not a conclusion to announce. Bring the finding, say what it would change, and wait.
* A decision brought to the maintainer, in a reply as in an issue, a review or a pull request, is one
  he takes in one read: `Decision:` and the question in a line, the options lettered `A)`, `B)`, each
  with what it changes, and `Recommendation:` with the option and its reason; "the maintainer's call"
  names who decides and not what. The options include the smallest change that makes the defect
  unreachable, and each larger one says what it buys over it.
* A question from the maintainer is answered, and the turn changes nothing: what the answer
  recommends is proposed with its decision, not done. "What is left?" asks for the list, not for the
  work on it; `.claude/hooks/on-prompt.sh` reminds a turn that reads a question.
* A fact the maintainer states is taken as given and acted on, not verified back: "#736 is merged"
  ends a question rather than opening one, and re-arguing the point it settles spends the exchange
  on what is already decided. A state you assert yourself is the other way round, and rule 1 governs
  it: read it before writing it.
* A call the conventions here already settle is made, not escalated: decide it, note it in a line, and
  move on. A question is for a genuine fork — where the answer changes the outcome and no rule,
  precedent, or test resolves it. Asking whether to add a comment the tree's macros never carry spends
  the maintainer on a call this document already made.
* "The tree does it" is a fact about the tree, not a reason. A choice is defended by what it buys and
  what it costs; prevalence says whether it is common, never whether it is right, and a tree can be
  wrong in a hundred places. When the only support for a line is a precedent, say so and judge it
  again.
* The core and its bindings are not shaped by a consumer or by an example. An example that cannot
  be written, or that reaches what it needs through a channel no contract states, is evidence of a
  gap in the API; what fills that gap is decided from what the binding is for, and the commit and
  the pull request argue it that way.

## Patches and commits

* Small, auditable, incremental commits. Each one stands alone and adds value.
* A commit is one change and everything that change entails, even across modules: a new core check
  adopted by four bindings is one commit. It is staged by purpose, the files of that change named and
  `git diff --cached` read against the message, never the whole tree an edit left behind;
  `tools/checks/stage-guard.sh` refuses `git add -A` and its kin. Independent fixes are separate commits, even when a single
  review finding uncovered them all; the finding is the reviewer's unit, not the committer's.
* A change to a function is read against the whole function, not the lines it touches: re-read it
  and take the simplification the change enables. A guard left standing that the new shape made
  redundant — `!cond || check(cond)` where the call now sits inside `if (cond)` — is a partial fix.
* A change that removes the last reader of a value removes what was written for it, as the NUL
  terminator and its byte go with the last read of a key as a C string. For every read the diff removes, ask what was stored, sized or kept only for that
  read; `tools/checks/terminator.sh` names the NUL case.
* Read the commit before pushing it, not only the working tree: `git show` the diff that is about to
  be published. Instrumentation added while debugging — a `pr_err`, a hardcoded branch — is invisible
  in a passing test and lands in the pull request.
* After resolving a rebase or a merge, `git grep -n '^<<<<<<< '` before committing. `git add -A`
  stages a conflict marker without complaining, and `git rebase --continue` runs no pre-commit hook,
  so the markers reach the branch and surface far from the resolution.
* Change only what the task requires. Do not reformat untouched lines, do not move code, do not
  rename variables in passing. Compare `git diff` against `git diff -w` before committing to catch
  stray whitespace.
* No dead or unnecessary code. A branch that cannot execute — a nil check on a call that raises
  instead of returning nil — is noise that misstates the API's contract.
* No cosmetic changes inside a feature or fix commit, not even a blank line.
* Never remove an existing comment unless the change made it factually wrong.
* Restoring something that was removed puts it back exactly where and how it was.
* Subject line says what changed and why, not how. A body only when there is something the diff does
  not say: a new API, a behaviour change, a non obvious rationale. No bullet list of every detail.
* A pull request title and body follow the same rule: what and why, nothing the commits already say.
  No "Test plan" section, and no em dashes.
* The body opens with the failure or the need in one plain sentence — what a script can do today,
  what breaks, what has nowhere to live — then says what the change does, in a few lines, and what
  it depends on. Three short paragraphs at most. How the problem was found, what was measured and
  what was tried belong in the commits; a body a reviewer has to study is not a summary.
  `tools/checks/pr-body.sh` holds a body file to this.
* A pull request that replaces another says so in the body, `Alternative to #N`, and the merge of
  the replacement closes #N in the same breath: one left open is a claim about the queue nobody made.
  `tools/pr-status.sh` marks an open pull request a merged body names that way as superseded and
  keeps it out of `--ready`.
* A pull request is one mechanism, read in one screen of diff and one paragraph of body. A body that
  needs a section per mechanism describes several pull requests: stack them, each on the one below.
  The harness is the exception: the checks, rules and skill steps one incident produces travel in one
  pull request, because they carry one reason and the CI line that runs them is one push. They travel with
  each other, never inside an implementation: a rule that rides in a feature's commit lands unread,
  and a maintainer who wants the fix and not the rule has nothing to pick.
  `tools/checks/harness-mixed.sh` names a commit that mixes them.
* No session links or assistant footers in a commit or a pull request beyond the `Co-Authored-By`
  trailer. The project settings turn the link off; one that slipped in is removed with a reword.
* A root cause named in a commit body or a pull request rests on a captured stack or a source-traced
  chain, not a correlated log line or a plausible mechanism. Until it is traced it is a hypothesis,
  labelled as one; a fix may land on the observed behaviour without naming a cause it has not proven.
  A release note, a changelog or any summary derived from commits is held to the same rule against
  its source: read each commit and use its words.
* A pull request reaches the maintainer's first review squashed: until he has read it, a correction
  folds into the commit it corrects, `git commit --fixup=<hash>` and `git rebase -i --autosquash` at
  once, and the branch goes up with `--force-with-lease`. After his review, a correction is
  `git commit --fixup=<hash>`, not a standalone "address review comments" commit, so what changed
  since he read it is a commit of its own. Never fixup a commit that is already on `master`; that
  becomes a new commit on a new branch.
* A fixup after the maintainer's review is pushed as soon as it is made, onto the pull request's own
  branch. It adds a commit, so it
  fast-forwards the branch and moves nothing a reviewer already read; what waits for the maintainer is
  the squash, and a rewrite is said out loud. A fixup that lives only on the machine that wrote it is
  outside the review, and a cleared worktree or a reboot takes it; one that lives only on `review/<n>`
  is outside it too, since the pull request lists its own branch's commits and nothing else, and
  "the fixups are on the pull request" is said after `gh api repos/.../pulls/<n>/commits` lists them,
  not before. The same holds for work handed to a reviewing agent: telling it not to push leaves the
  push owed by whoever gave the instruction.
* Work an agent does for a workflow outlives the agent. Its branch is pushed at each commit, pull
  request or not, and what it measured and decided goes to a checkpoint file, a line per step, that
  the agent relaunched in its place reads before anything else; the workflow then resumes with the
  finished agents from its cache and the unfinished ones from their branch and checkpoint.
* If a branch adds something in one commit and removes it in another, the second is a fixup of the
  first.
* After squashing, re read the comments, the commit bodies and the identifiers so they describe the
  final state rather than the path taken. A name is a residue as easily as a sentence: a type renamed
  to tell it apart from a sibling keeps that name after the sibling goes, and then the noun tells it
  apart from nothing. For every name the branch introduces or changes, ask what it distinguishes from
  in the final tree, and whether master already had a name for the same thing;
  `tools/checks/rename-orphaned.sh` catches the typedef case, and `tools/checks/body-identifiers.sh`
  the paragraph that still explains a mechanism a folded fixup removed.
* Naming an existing literal is done by visiting every call site of what carries it: sweep for the
  function's callers or the field's users, not for the literal, which misses positional arguments.
* Changing the value of a field visits every reader of it, in the code and in the field's doc, and
  asks what each does with the value: `class->name` is the type name a type error quotes and the
  name every context error prints. A reader that merely compiles
  against the new value is not accounted for.
* A force-push that restructures a branch is not done until the pull request title and body are
  re-read against it. They describe the branch; a rewrite that drops or replaces a mechanism turns
  them into fiction the reviewer reads first.
* A report of a push names the ref it moved and, separately, what it was rebased onto. "Force-pushed
  onto current master" reads as the one thing nobody may do, and a reader who has to parse a sentence
  to find out whether `master` was rewritten has already been alarmed for nothing. Say which branch
  took the push; the base is a different clause.
* Do not commit directly to `master`.
* Copyright years: a new file carries the current year; a modified file extends its range to include
  it; and a file that factors code out of another carries that file's first year, found with
  `git log -S` on the moved lines. `lib/class.lua` took the `:new` that `lib/socket/inet.lua` had
  carried since 2023. Every source file opens with `SPDX-FileCopyrightText` and
  `SPDX-License-Identifier`, the holder being who created it, and a file that cannot carry a header,
  Markdown, data or a font, is declared in `REUSE.toml`; `pre-commit` refuses a source file staged without one.

## Reviewing your own change

The conventions in this document and in `.agents/rules/` are a checklist to run against your own diff before showing it, not
reference to reach for after a reviewer objects. Code shown without that pass makes the reader the
reviewer, and the deviations they then find — a prefix nothing else in the file uses, a comment on a
body the file leaves bare, a handle closed by hand where the file uses `<close>` — were already rules
here. The failure is not the missing rule; it is not running the ones that exist.

Before presenting a change to an existing file, read the file as the authority and measure the
addition against it — naming, comment density, idioms, resource handling, duplication — then prove
the behaviour on the operation in isolation, not a round trip that hides a partial result: `unload`
reaching zero, not `reload` returning to a full set. The pass covers the prose the change ships with,
too: after any rewrite or force-push, the commit message and the pull request body go through the
same review against the final code — a claim the code does not support, a mechanism the branch
dropped or a rationale its call sites contradict, is caught there, as *Patches and commits* requires.
Saying the prose matches is not the check; showing the claim-to-code mapping is. A change shown
without that pass is not done.

Before the hand-back, every function the diff touches is re-read whole, not by its changed lines:
a new branch is asked whether it is this function's job or its caller's, a condition with stack
juggling is asked whether it is a predicate helper, and a guard the new shape made redundant is
removed. The maintainer reading a function and finding it dirtier than before is the pass not run.

The hand-back lists each finding of your own review that the change does not apply, with the
reason. A finding dropped in silence is found again by the maintainer, who then doubts the whole
review; and "few sites" is not a reason against a rule that collapses a repeated pattern.

A review comment names a principle, not a token. Read the words as written, say which principle they
invoke, and fix that: a note that an `enum` is formatted inline asks for the formatting, not for a
`#define`, and changing both leaves the reviewer to undo one.

## Before opening a pull request

1. `make` is clean, with no new warnings, and a change that touches a `__percpu` pointer, or any
   other address-space annotated one, is clean under `make C=1` too: sparse models the annotation as
   an address space, as GCC 14 on x86 does for `__percpu` (`__seg_gs`), so a `void *` holding one, or
   a cast between the two, is a warning here and a build error there;
2. `sudo make install && sudo lunatik reload && sudo lunatik test` passes;
3. new API is documented and listed in `config.ld`, and `make doc-site LUA=lua5.5`,
   the CI target, exits zero: a C file that contributes to a module another file declares carries
   `@module` with the same name, which `merge = true` in `config.ld` folds, since `@submodule`
   deduces its section name from a path under `lib/`;
4. new tests are wired into their suite and described, and the hand-back carries the matrix the
   change is held to: for each guard or mechanism it adds, the operations by types by outcomes,
   each cell naming its test or saying why it is not covered. Wiring is what a check confirms; the
   matrix is what a rewrite inherits from the branch it replaces unless it is written down;
5. error paths audited: for each raise, everything already acquired is released;
6. every example that uses a binding the change touches is run, not only loaded, through the
   example's own `setup.sh` and `cleanup.sh` where it has them, and the hand-back says of each
   one whether it ran, only loaded, or was not run, and why. A loaded script that never fired
   its hook is the green build the review rule warns about;
7. commits are small, ordered, and none of them undoes another;
8. every helper the change introduces has a caller. A helper extracted to remove duplication but
   left unused, while the duplication it replaces still stands, is the refactor half-done. Grep the
   new symbols for a caller before sending.
9. the branch is handed back merge-ready, not as a working scratch: the session's commits grouped into
   a clean history that none of them undoes, nothing left to squash, the pull request title and body
   describing the final state. On a harness or docs pull request you author, tidy it before returning
   it, unasked — what comes back is reviewed and merged, not tidied first.
10. the simplification pass, before sending. For each helper, collection, loop, or mechanism the
   change adds, a registration path, an argument on an API, a name for a literal, name what it buys
   over the minimal shape — weighing the whole cost, not the line count at one call site.
   A loop that vanishes locally by generating a build-time list can add more surface than it removes
   (an extra argument, an emitted table, a file to keep in sync); prefer the ground truth the system
   already exposes — the kernel's own "Used by" list, a field already on the struct — over a structure
   invented to encode it, and keep a loop that is doing honest work. The same holds for a comment: one
   non-obvious reason, one line, at the site that needs it — not spread over two, not repeated wherever
   the feature is touched.

## Reviewing a pull request

The process is `.agents/skills/review-pr/process.md`, which the review-pr skill opens with.

