---
paths:
  - "**/tools/**"
  - "**/.agents/**"
  - "**/.claude/**"
  - "**/.github/**"
  - "**/AGENTS.md"
---

# Checks of Lunatik

Lunatik's own checks live in its `tools/checks/`, beside the mount's, which
`harness/.agents/rules/checks.md` describes: comment and LDoc style on framework files
(`module-conventions.sh`), a sequence of calls a change adds that another C file already makes
(`core-helper.sh`), a function a change adds that spells a run of code another project wrote
(`copied.sh`), a deferral a change adds to the core or a binding (`deferral.sh`), a kernel constant
the Lua of the compiler or of `lib/` spells by hand (`hardcoded.sh`), test scripts that cannot detect
a failed load or a case their Lua script skips (`test-harness.sh`), a kernel thread loop that never
pauses (`kthread.sh`), cppcheck on userspace test C (`cppcheck-tests.sh`), a recursion in the Lua the
kernel links that counts no C level and no bound names (`recursion.sh`), the readers of a field the
change keeps its own copy of (`shadowed-readers.sh`), the classes and callers a changed core primitive
reaches (`blast-radius.sh`), the examples that use a binding the change touches, which a review runs
(`examples-touched.sh`), and the refusal of a string function the kernel removed (`pre-commit`, which
runs the mount's gate first). Each takes file paths and skips what does not apply. The `edit`,
`advisory` and `commit` keys of `.agents/harness.conf` name the ones the mount's `on-edit.sh` runs at
edit time and its `advisory.sh` over a change, and `range` the ones its `review-packet.sh` runs over a
branch. The commit gate is Lunatik's `pre-commit`, and `commit-msg` a link to the mount's, installed
with:

    ln -s ../../tools/checks/pre-commit .git/hooks/pre-commit
    ln -s ../../tools/checks/commit-msg .git/hooks/commit-msg

`core-subject.sh` reads commits rather than files, since a subject belongs to a commit: it takes
commits or a rev-range (`bash tools/checks/core-subject.sh origin/master..HEAD`) and flags one that
changes the core under a subject naming only a binding. The rule is not that core and a binding
never mix, which AGENTS.md, *Patches and commits*, sanctions, but that the subject says so.

`kernel-answer.sh` reads commits the same way and names one that builds a mechanism over a kernel
primitive, RCU, a lock, a reference count or deferred work, with a new function or field, in a body
that cites neither a `Documentation/` page nor one of that family's own facilities: the kernel has
usually answered the problem already, and the comparison belongs in the body where the reviewer reads:
`Documentation/RCU/whatisRCU.rst` says "Will readers need to block? If so, you need SRCU". It annotates, since
a body can cite the page and still not read it.

`guard-removed.sh` names the crash guards a C file drops against `HEAD` (a checker, an
`argcheck`, a context check): removing one and running the test that covers it reproduces the
crash the guard prevents, and on the shared host that is a forced reboot. `crash-guard.sh`, wired
before a shell call as the mount's guards are, blocks an install, reload or run while any
worktree drops such a line, unless the command carries `CRASH_AB_OK=1`, set once the maintainer
authorized the experiment and named the machine it may take down. A command line that writes a C
source or header, by a redirection onto it or a `sed -i`, `git checkout` or `git restore` naming
it or its directory, and installs or runs in the same call is blocked under the same marker, since
the worktrees are read before the call runs: the edit goes in a call of its own, and the install
after it is read against the tree the edit left. A write a script file makes is not on the line, and
the line is all the guard reads. A line that installs reads the tree its `make install` runs in,
the cwd moved by each `cd` and by make's own `-C`, for the install and the runs after it on the line,
since under `harness/tools/lunatik-host`'s lock they run what it just installed. A line that only runs what is
installed, one that runs before its first install, one whose tree is not resolved and one that moves
a directory by another spelling, `pushd`, `env -C`, `sudo -D` or a make option such as `-sC` or
`--dir=`, read every worktree of the checkout, so one another session left dirty blocks this session's run; its owner
cleans it, and a review says its run was blocked rather than overriding a guard that was not about its
tree.
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
loop header a file spells twice, which a foreach macro names, as `lunatik_foreachruntime` does, and so
is a helper of the file that steps a loop through out parameters, the shape #1896's `luaset_next` took
past that check; and two functions whose one statement returns the same call with another argument,
a pair a macro generates, as `LUABPF_OPENER` does. It names a static function of two statements, a call
and the return of another call handed the function's parameters, a wrapper whose step runs ahead of the
helper's checks, as #2493's `luacrypto_aead_finish` ran `crypto.aead`'s move of its result before
`luacrypto_pushbuffer` checked the request's return; the step is an argument of the helper. It names
a guard on a kernel option that holds a whole unit, with no `#else` arm, opened after the includes, as
#2385's `luacrypto_rng.c` and #2360's `luacrypto_kpp.c` first opened theirs: `linux/kconfig.h` is
force-included, so the guard opens the file. It names
a value a function computes before a check that raises and does not read it, which decides before
validating, and a load of one mode, which refuses what `require` and `load` take. It names a refusal
raised with the family's wording as a literal, `luaL_error(L, "not allowed ...")`, whose message is a
`LUNATIK_ERR_*` constant and whose check a `lunatik_check*` helper beside the family, which
`guards.sh` counts, and a local array a copy fills only for `lua_pushstring` or `lua_pushlstring` to
read, which copy the string themselves. It annotates rather than fails, since the release-then-throw shape is not `lunatik_try`'s and the line
between the check and the throw is what the reader decides on.

`core-helper.sh` reads the lines a change adds to a C file, against `CHECK_BASE`, for three in a row
inside a function whose calls another C file of the tree already makes in the same order, read with
the arguments left out: the sequence is one helper, in `lunatik.h` when its calls are the core's, as `lunatik_pushfail`
spells `lua_pushnil`, `lunatik_pusherrname` and `return 2`. It runs at edit time and over a pull request's
diff and annotates, since two encryptions that set up one request each are two callers of the
kernel's API and not a helper missing; the review answers each line it prints with the helper or
the reason the calls are the kernel's sequence.

`copied.sh` reads the functions a change adds or edits in a C file, against `CHECK_BASE`, for a run of
16 tokens or more, comments and literals left out, that a function of `lua/`, `luac/` or klibc spells
too, made of sequences no other C file of the tree spells: code another project wrote is reused, not
copied (AGENTS.md, *Deciding what to change*), and #2347 copied 22 tokens of `project()` under no note.
A sequence the tree spells elsewhere is its own idiom, a call of the Lua API or of the kernel's, and a
function under a note `based on <function>() @ <path>` follows that function on purpose; neither is named.
It runs at edit time and over a pull request's diff and annotates, since a copy spread over two files of
the tree reads as the tree's own idiom, and one that renames a local it repeats reads as none, as #2347's
does with `lim` renamed; it reads nothing where the submodules are not checked out.

`deferral.sh` reads the lines a change adds to the C of the core or a binding, against `CHECK_BASE`,
for a deferral: an item of `lunatik_defer`, a work, an irq_work or a tasklet. A hazard is refused in
its context before it is engineered around (AGENTS.md, *Deciding what to change*). It runs
at edit time and over a pull request's diff and annotates, since the core's deferred close is the
kernel's answer to a release in atomic context; the commit body names the refusal each line it
prints was weighed against.

`hardcoded.sh` reads the lines a change adds to the Lua of `bin/luaebpf` and of `lib/`, against
`CHECK_BASE`, for a kernel constant spelled by hand: a number beside a comment that names a kernel
symbol or a C source, trailing the line or heading a run of top-level lines with no blank between,
`local MAXSTACK <const> = 512 -- MAX_BPF_STACK`, and constants picked by name beside a comment naming
the C source that defines their set, as #2223's XDP range named `action.ABORTED` and `action.REDIRECT`
beside `lib/luaxdp.c`. `autogen/` generates the kernel's tables, and `autogen/specs.lua` takes the
header of one it lacks. A symbol of the Lua the kernel links, `OP_CALL` or `LUAL_BUFFERSIZE`, is not
the kernel's and is not read, nor a number on a line that reads a table's constant, `1 << flag.AUTHORIZED`.
It runs at edit time and over a pull request's diff and annotates, since a number counted in the
comment's own terms, a width in bytes beside `BPF_B`, is no copy of the kernel's.

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

`contract.sh`, which the mount's `pr-body-guard.sh` runs over an issue a write opens, refuses a finding
whose stimulus reaches into the runtime's own bookkeeping, out of contract by the honest-mistake bullet
of AGENTS.md, *Deciding what to change*. `CONTRACT_OK=1` opens it where a script using the API as
documented reaches the same path. `examples-named.sh`, which the same guard runs over a pull request a
write opens, fails a body that leaves unnamed an example `examples-touched.sh` lists for its change
(AGENTS.md, *Before opening a pull request*, item 4), and `EXAMPLES_OK=1` opens one whose body says of
each what it did. Both bind a write to this repository or a fork of it.

`empty-units.sh` reads a tree after `make` and names an object of the tree's own C that defines no
symbol: a unit wholly under a guard the kernel it built against leaves unset compiles to nothing, and the
build passes without it. The build workflow runs it in every cell and fails one that leaves a unit empty:
`lib/luacrypto_kpp.c` sits under `IS_REACHABLE(CONFIG_CRYPTO_ECDH)`, which no defconfig the job builds
sets, and an earlier push of #2360 compiled `crypto.kpp` on no kernel of the matrix. The cell's options
set what such a guard asks for, and a unit a kernel of the range cannot build keeps an arm that refuses,
as `luascx.c` does without `CONFIG_SCHED_CLASS_EXT`, rather than nothing.

`bundled.sh` reads a rev-range and names one whose files take a C binding of `lib/`, a `.c` or a `.h`
at its top, and the compiler under `bin/luaebpf` together, whatever commit each one sits in: the
binding is a pull request of its own and the compiler's is stacked on it (AGENTS.md, *Patches and
commits*), since #2235 carried `lib/luadata.c` under a TC read and the maintainer asked to split it.
The `Checks` workflow fails a pull request it names, over the range from its base, so the stacked one
passes; the review's packet runs it over the branch, and the
implement-issue workflow's groomer and implementer split a change it would name before the branch exists.

`capi-entries.sh` takes headers of `lib/` and names each identifier of a header's own prefix,
`lua<name>_` or `LUA<NAME>_`, its comments and its include guard left out, that no C block of
`doc/capi.md` carries, and the `Checks` workflow fails on a pull request that leaves one in
`lib/*.h`: the reference is written by hand, and until #1931 gave the headers their sections a module
that called `luadata_reset` read the `.c` for what it raises, the context it runs in and who owns what
it takes. It catches a name missing, not an entry that no longer says what the code does.

`layout.sh` reads the tree from its top and names a top-level directory the Layout table of AGENTS.md
does not list, a tracked directory named as the directory that holds it, a file the Makefile installs
into `SCRIPTS_INSTALL_PATH`, or into a variable defined over it, from outside `lib/`, `examples/`,
`tests/`, `autogen/`, `common/` and the root files the table lists, and a file it installs or links into
the host's Lua path, `LUA_PATH`, `LUA_CPATH` or a variable defined over them, from `lib/`, `examples/` or
`tests/`, which run only in the kernel; the `Checks` workflow fails on any. Code lives and installs where
it runs (AGENTS.md, *Layout*), and the luaebpf compiler, which runs only in the CLI's Lua, reached review
after review at the root of the tree, installing into `/lib/modules/lua/`; once in `bin/`, it required
`class` from `lib/` through a copy installed in its own root, from a package at `bin/luaebpf/luaebpf/`. A
source spelled through a variable is not read, so a table the build writes under a variable's name passes
unread, and so does a link whose source is an installed copy, as `lunatik/config.lua`'s is. It also
names, in a tracked C file, a libgcc helper defined outside `lunatik_libgcc.c` and a C source of klibc
included: the compiler's runtime a module of the tree calls lives in the core, klibc's objects `Kbuild`
links into `lunatik.ko` and `lunatik_libgcc.c`, which exports them, and #2132 first took klibc's helpers
into `lib/lualinux.c` and defined `__divmoddi4` in `lunatik_aux.c`.

`example-guard.sh`, wired before a shell call, refuses `lunatik run` and `spawn` of anything under
`examples/` that does not go through `harness/tools/watchdog.sh`, unless the command carries
`NETWORK_LOSS_OK=1`: an example arms real hooks on the machine that runs it, and one that cuts the
network off cannot be stopped afterwards, because the command that would stop it has nowhere to be
typed. The guard keys on loading an example, not on the name of one already known to misbehave.

`consumers.sh` names the out-of-tree scripts that load a binding the changed files touch, reading the
clones listed in `LUNATIK_CONSUMERS`; `consumers-guard.sh`, wired before a shell call, blocks opening or
editing a pull request that changes such a binding until the command carries `CONSUMERS_OK=1`, set once
those scripts were read. The change is the pull request's, from the base to the head the write names, as
`pr-body-guard.sh` reads its examples, and an edit's head and base are the ones GitHub has, since a
retarget moves none of its commits: the HEAD of the directory a command ran in held a stacked pull request
for the branch below it, and let one opened from a checkout on another branch through. A change the
checkout cannot read is refused.
A product built on Lunatik is a consumer this tree cannot grep. A failure reported from a consumer's
build is read from that build's own configuration before any mechanism is theorised.

`examples-touched.sh` and `consumers.sh` read what a change reaches through `modules.sh`: the module a
file defines, read from the base when the change deletes it, and every module a script reaches it
through without requiring it, a library that requires it, as `netlink` reaches `netlink.rt.route`, and
a binding that builds its objects for a callback, as `netfilter` and `tc` hand an `skb`. A change to the
runner adds the examples a README starts with the CLI verb whose function it touches, and one to autogen
the `linux.*` tables its specs feed. The CI annotation reads the files a pull request adds or modifies, so a deleted module is named by the guard
and the pull request's preparation, which read the whole diff. `examples-touched.sh` and `consumers.sh`
read the change from `CHECK_BASE` in the working tree, where the preparation, the review and the CI hold
its head, or, when `CHECK_HEAD` is set, at that commit through git: `consumers-guard.sh` and
`pr-body-guard.sh` set the two to the merge-base and the head of the change they listed, since the
checkout a hook runs in holds another branch, whose working tree read a spec the head changes as
unchanged and a binding it adds as absent.

