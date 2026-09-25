# Control path: a session on the device, the command line, and netlink for what it buys

The plan for #1089. Read at Lunatik master `1bfa2da57` and at the kernel this host runs, Ubuntu
HWE 6.8.12, with the exports checked in its `Module.symvers`; a kernel line is 6.8's, with the
v6.6 and v7.2 lines beside it where the fact rests on them. Nothing here is code: the
recommendation ends with the first pull request.

## What the control path is today

The `lunatik_run` module creates the `driver` runtime at load (`lunatik_run.c:24`), whose script
makes `/dev/lunatik` with `device.new` (`driver.lua`). The CLI (`bin/lunatik`) manages everything
through one function, `dostring(chunk)`: it opens the device, writes a Lua chunk, closes, opens it
again and reads the result. Every command is a chunk: `lunatik.runner.run("x", "softirq", true)`,
`lunatik.runner.stop("x")`, `return lunatik.runner.list()`, `lunatik.runner.startup()`, the REPL's
lines and `return _LUNATIK_VERSION`. The kernel side is `driver:write`, which `load`s and
`pcall`s the chunk under the driver runtime's mutex, the one `lunatik_run` takes for every file
operation, and stores the result for the next `read`.

Three properties follow, and they are the defects the question is about:

1. **A request and its reply are two opens with no session.** Two clients interleave: one's
   `read` takes the other's result. This is why AGENTS.md says never to run two `lunatik`
   operations at once and why `tools/lunatik-host` exists.
2. **The requester's task runs the request under the runtime's mutex.** A chunk that does not
   return holds the mutex, and every later operation waits in D state on it: the wedge only a
   reboot clears. Its stimulus, a body that never returns, is out of contract (AGENTS.md,
   "Deciding what to change": root loaded it on the machine it breaks). What stays in contract
   is a `stop` whose close waits on a lock another task holds, RTNL or `cb_lock`, which the
   requests behind it wait out: a wait, not a wedge; the cycles a netdevice callback's task can
   close are refused on that task (#1045, the release-context phases of #1120), not here.
3. **The request is Lua source.** The device node's mode is the whole permission model, the
   command set is whatever `runner` exports, and a reply is a string the CLI parses (#1083).

The device lifetime defects the issue lists, #1071 to #1074, #1076 and #1084, are closed, through
#1079, #1091, #1093 and #1100: they no longer weigh on this choice.

## The deciding fact

A generic netlink `doit` runs on the requesting task with `cb_lock` held for reading and, unless
the family sets `parallel_ops`, `genl_mutex` (`genl_rcv`, `genetlink.c:1216`; `genl_op_lock`,
`:55-58`; at v6.6 `:1074` and `:55-58`, at v7.2 `:1217` and `:57-60`). A runtime's close runs
every release of its state on the task that closes it, and a `netlink.channel`'s release is
`genl_unregister_family` (`lib/luanetlink.c:42`), which takes `cb_lock` for writing
(`genl_lock_all`, `:43-47`, from `:855`; at v6.6 `:43-47` from `:716`, at v7.2 `:45-49` from
`:852`): a `doit` that closes such a runtime, or that waits for another task to close it, waits on
itself, on every kernel in the range. The maintainer has declined deferring
releases to a worker (#1124, closed), so the close stays synchronous on the task that runs it.

So the task that runs a `doit` cannot be the task that closes runtimes, and cannot wait for it.
The request has to leave the `doit` at once, run elsewhere, and answer later. That is what a
family costs before anything it buys: a queue and a worker, which the device does not need.

## Shapes, smallest first

1. **Keep the device, make an open a session.** `write` stores the request on the file
   (`f->private_data`), `read` on the same descriptor returns its result. Fixes property 1,
   the transport's one defect in contract. A dozen lines in `luadevice` and `driver.lua`, and
   the CLI's `dostring` reads on the descriptor it wrote; the status in the reply is the
   command line's (below); property 2's remainder, a wait, stays a wait.
2. **A request queue and a driver thread, over the device.** A thread body holds its runtime's
   lock for as long as it runs (`luathread_func`, `lib/luathread.c:53`; AGENTS.md, "Kernel
   threads"), and a device's every fop takes the lock of the runtime that made it
   (`luadevice.c:177-178`), so the body runs in a runtime of its own beside `driver`: it loops on
   a `fifo` of requests both reach through `lunatik._ENV`, runs each through `runner`, and
   stores the result where the requester reads it. The file operation only enqueues, wakes the
   thread and waits for the result with a bounded wait, holding no runtime lock. Fixes property
   2: one request at a time by construction, and a request that never returns leaves the driver
   thread stuck in a stack `/proc/<pid>/stack` shows, with the requester timing out and reporting
   it, and every later request timing out behind it until a reboot, instead of a task in D.
   Property 1 stays: the reply is read on a second open (`bin/lunatik:17-24`), which takes
   whatever the slot holds by then, so routing it to its requester is shape 1's session, or a
   slot keyed by the requesting task.
   The wait has to sit outside the lock `lunatik_run` takes around every fop
   (`luadevice.c:177-178`), so it is a change to the device binding's `write`, or a fop of the
   driver's own, not a primitive a script calls; the shape with no C has `write` enqueue and
   return, and the CLI poll `read` until the reply, which carries its status once the command
   line lands, is there.
3. **A generic netlink family, with the queue of shape 2.** `lunatik_run.c` registers the
   family `lunatik` with operations `EVAL`, `RUN`, `SPAWN`, `STOP`, `LIST`, `STATUS`, each
   attribute-checked by the core's policy; the core refuses a request from a namespace other
   than the initial one before any `doit`, since the family is not `netnsok` (`genl_rcv_msg`,
   `:1166`; v6.6 `:1024`, v7.2 `:1167`); the `doit` checks `netlink_capable(skb,
   CAP_SYS_MODULE)`, copies the request with its `snd_portid` and `nlmsg_seq` into the queue,
   wakes the driver thread and returns. The thread answers by `genlmsg_unicast` to that port
   and sequence, through a reply primitive the module exposes to the driver runtime, so the
   requester's socket receives the reply of its own request and nothing else. Fixes all three
   properties. Costs: the CLI is Lua over file I/O and the tree has no userspace netlink for Lua,
   so the client is a C tool (`tests/netlink/channel_subscriber.c` is the shape, 116 lines) the
   CLI runs, or a userspace module the CLI loads; the family, its policy and the reply primitive
   in C; `tools/lunatik-host` is a `flock` and `tools/checks/lunatik-lock.sh` keys on the
   `lunatik` process and the test scripts by name (`:21-23`), neither on the device, so both
   keep working; and the consumer's `ExecStart=lunatik spawn` and `lunatik unload` keep working
   only if the CLI's surface stays.
4. **A generic netlink family dispatched to Lua.** A binding that hands a `doit` to a script,
   the way `notifier` hands events. Rejected by the deciding fact: the script runs under
   `cb_lock`, and the request is Lua again.

## Recommendation

Shape 1 first, as its own pull request, with the reply that keeps its status: the transport's
one defect in contract, a dozen lines, and nothing a later shape retires. The command line
beside it, as a track of its own (below), since the transport needs of it only the status in
the reply. Shape 2 has no defect of its own to answer once the body that never returns is out
of contract: it is what shape 3 costs, so it is built only when shape 3 is chosen, and in its
form with no C, `write` enqueues and the CLI polls `read`, which lands nothing shape 3 retires.
Shape 3 is chosen or declined on a comparison written into this note first: what it buys is a
capability read from the requesting socket and a typed reply, against a device node whose mode
already admits root alone and a reply that carries its status after shape 1; what it costs is
the family, the reply primitive, the worker and a C client for a CLI that is Lua over file
I/O. Declining it is an outcome this plan allows, said as such when the comparison is written.

## The command line, a track of its own

Read at `bin/lunatik` as of `0dcef10e7`, `driver.lua` and `lib/lunatik/runner.lua`, against POSIX
XBD 12.2, the [Utility Syntax Guidelines](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap12.html),
the GNU Coding Standards'
[Command-Line Interfaces](https://www.gnu.org/prep/standards/html_node/Command_002dLine-Interfaces.html),
the standalone interpreter of the Lua the tree vendors (`lua/lua.c`), and the tools an
administrator of a kernel already types: [`ip(8)`](https://man7.org/linux/man-pages/man8/ip.8.html),
[`bpftool(8)`](https://github.com/libbpf/bpftool/blob/main/docs/bpftool.rst),
[`nft(8)`](https://www.netfilter.org/projects/nftables/manpage.html),
[`modprobe(8)`](https://man7.org/linux/man-pages/man8/modprobe.8.html),
[`systemctl(1)`](https://man7.org/linux/man-pages/man1/systemctl.1.html),
[`luarocks`](https://github.com/luarocks/luarocks/blob/main/docs/luarocks.md), Docker's
[1.13 regrouping](https://www.docker.com/blog/whats-new-in-docker-1-13/) and the
[CLI Guidelines](https://clig.dev/).

### What the CLI is today

`lunatik [load|unload|reload|status|test|list] [run|spawn|stop <script>] [percpu] [compile
<arguments>]`, and the REPL with no command. What departs from the references:

1. **The modifiers of `run` are bare words after the operand.** `options()` (`bin/lunatik:170`)
   reads every word after the script as the context unless it is `percpu`, in either order, and
   sends it as it is: `lunatik run x foo` answers `bad argument #2 to 'runtime' (invalid option
   'foo')` from the kernel (`luaL_checkoption`, `lunatik.h:196`) on stdout with exit 0, and
   `spawn x softirq` creates the runtime that `thread.run` then refuses (`lib/luathread.c:219`).
   Guidelines 4 and 9: an option carries `-` and precedes the operands.
2. **No `-h`, `--help` or `--version`.** A wrong invocation prints the usage line on stdout and
   exits 1 (`bin/lunatik:228`); the version is the REPL's banner, read from the kernel. GNU: every
   program takes `--help` and `--version`; `lua` takes `-v`.
3. **`run`, `spawn`, `stop` and `list` exit 0 whatever the kernel answered.** The driver's
   `result(pcall(chunk))` (`driver.lua:16-28`) drops the status and joins the values with tabs,
   so the CLI holds a string, `lunatik/runner.lua:62: x is already running` among them, prints it
   on stdout and exits (`bin/lunatik:236`); AGENTS.md says so under "Running a script", and the
   tests assert on output for that reason (`tests/lib.sh:41-49`). `load`, `unload`, `reload`,
   `status` and `test` raise instead, which the interpreter prints with a traceback on stderr,
   exit 1; `test` exits with its suite's status since #1092, `compile` with `lunatic`'s. `ip`
   exits 0, 1 on a syntax error and 2 on an error the kernel reported; `lua` exits `EXIT_FAILURE`
   on an error in the chunk (`lua/lua.c:792`).
4. **`stop` of a name nothing runs is silent, exit 0** (`runner.stop`, `runner.lua:96`).
   `rmmod`, `kill`, `systemctl stop` and `docker stop` fail on a name they do not find. 167
   cleanups in `tests/` run `lunatik stop <script> 2>/dev/null`; none reads the status.
5. **`list` is one line, the names joined by `, `** (`runner.list`, `runner.lua:105`). `lsmod`,
   `ls`, `luarocks list` and `ip -o` print one item a line; fourteen reads in nine tests match a
   name as a substring, which one name a line satisfies, and one pattern reads the comma
   (`*"$SCRIPT,"*`, `tests/runtime/percpu.sh:45`).
6. **The REPL prints its banner and prompts whether or not stdin is a terminal.** `lua` prints
   the banner and prompts only on a tty and otherwise reads stdin as a chunk (`lua/lua.c:765-770`);
   `nft -f -` and `ip -b -` read commands from stdin. There is no `-e`, and nothing in the tree
   drives the REPL, which #845 asks a suite for.
7. **What is settled and stays.** A script is a name under `/lib/modules/lua/` without `.lua`
   (`LUA_ROOT`, `lunatik_core.c:229`), `modprobe`'s model and not `insmod`'s, and the REPL covers
   a chunk that is not installed. The verbs are `runner`'s (`run`, `spawn`, `stop`, `list`) and
   the module set's (`load`, `unload`, `reload`, `status`); no abbreviation is accepted, which the
   CLI Guidelines name as what keeps a later verb from breaking a script, where `ip` takes
   `ip a`. `test` and `compile` are the developer's, as `luarocks test` sits beside `install`.

### Verb first, not object first

`ip`, `bpftool` and Docker since 1.13 put the object before the verb; `nft` (`add table`, `list
ruleset`), `systemctl`, `luarocks`, `git`, `tmux` and `lua` put the verb or the option first.
Docker's reason was forty top-level commands; `ip` has thirty objects. Lunatik manages two
things, the module set and the runtimes, with eight verbs that do not collide, and each verb is
one operation of the family shape 3 registers: `lunatik module load` and `lunatik runtime stop`
buy a second word on every call and a grouping the help text gives on its own. Verb first stays.
`run` over `start`, since it is `runner.run` and what `lunatik.runtime` does; `list` over `show`
and `ps`, since it is `runner.list` and what the tests read.

### The shape

    lunatik [-h | -V]
    lunatik [-i] [-e <chunk>]                                the REPL, or a chunk
    lunatik load | unload | reload | status
    lunatik run [-c process|softirq|hardirq] [-p] <script>
    lunatik spawn <script>
    lunatik stop <script>...
    lunatik list
    lunatik test [<suite>]
    lunatik compile [<lunatic argument>...]

with `--context=`, `--percpu`, `--help`, `--version`, `--interactive` and `--eval=` as the long
spellings, which the tests and the documentation use. What each line changes:

- **Options carry `-` and precede the operand.** `run -c softirq -p x`; `spawn` takes neither,
  since its thread is a process runtime (AGENTS.md, "Kernel threads") and `percpu` is what
  `runner.spawn` refuses from the kernel today; a context outside the set is a usage error, exit
  2, with the three values in the message. The bare words after the script stay accepted for one
  release with the same meaning and a line on stderr naming the option: the README taught them
  and an out-of-tree script may carry them, though the consumer's do not (its unit runs
  `lunatik spawn dome/daemon` and `lunatik unload`, its script `stop`, `spawn` and `unload`). The
  tree's 30 call sites in 20 files move in the same pull request.
- **Exit status 0, 1 when the operation failed, 2 on a usage error.** 1 is `EXIT_FAILURE`, the
  value every reference shares and the one a script tests; 2 for usage is the shell's own
  [builtins' value](https://www.gnu.org/software/bash/manual/html_node/Exit-Status.html) and
  `ip`'s numbering inverted, so it is a choice, written down as one. The kernel's refusal
  reaches the CLI as a status the driver keeps: `driver:write` stores the pair `pcall` returns
  and the reply carries the status before the values; `runner` raises at level 0, so a message
  carries no `runner.lua:62:`; the CLI prints an error as `lunatik: <message>` on stderr. The
  consumer's unit is `Type=oneshot`, so a `spawn` that fails fails `systemctl start`, where today
  the unit goes active with the error on stdout; its `reload` script reads no status. This is
  property 3 of the device, and the pair is the one shape 1's `read` and shape 3's reply carry:
  written once, in the driver, and every transport carries it.
- **`stop` of a name nothing runs fails**, `lunatik: x is not running`, exit 1, as `rmmod` does:
  `runner.stop` answers whether it found the script, and the CLI reads the answer. It does not
  raise: `ifquarantine`, `spyglass` and `systrack` stop from the kernel side a child they ran
  (`examples/systrack/device.lua:35`), and a child the CLI stopped first stays a silent no-op
  there. The cleanups discard the status; `tools/watchdog.sh:43` reads it for a `stop` of the
  script it ran, which runs. `stop` takes several names, as `rmmod` and `systemctl stop` do,
  one device round trip each.
- **`list` prints one name a line**, split from `runner.list`'s reply in the CLI, and the one
  pattern moves with it. Columns (context, percpu, thread) and `--json`, which `ip`, `bpftool`
  and `nft` take and `systemctl` spells `--output=json`, wait for the family, whose `LIST` reply
  carries the attributes a renderer needs and today's `runner` does not keep.
- **The REPL is `lua`'s.** The banner and the prompts only when stdin is a terminal; otherwise
  the lines are read to the end with no banner, which is the pipe #845's suite writes.
  `-e <chunk>` runs a chunk in the driver runtime and prints its values tab-separated, exit by the
  status; `-i` enters the REPL after it; `-V` prints `LUNATIK_VERSION` (`lunatik.h:20`) as the
  kernel reports it, and `lunatik: not loaded` when it cannot.
- **`-h` and `--help` print the usage on stdout, exit 0**; `lunatik help <command>` and
  `lunatik <command> -h` print that command's, as `bpftool <object> help` and `git help` do. A
  wrong invocation prints the usage on stderr, exit 2.

Not changed, and why: `test` and `compile` stay, one developer's command each, since the tree has
no second tool to hold them; the script stays a name and not a path, the kernel's `LUA_ROOT` being
the policy; no abbreviation; the kernel-side `runner` keeps its signature, `run(script, context,
ispercpu)`, since the family's `RUN` is what changes it, if anything does.

### What it costs

`bin/lunatik`'s parser, written by hand: a dozen options need none of `lua-argparse` (packaged,
0.6.0), which would be the CLI's first hard dependency where `lua-readline` is optional.
`driver.lua` keeps the status, `runner.stop` answers, `runner`'s errors lose their position. The
README's `lunatik` section, AGENTS.md's "Running a script" and its contexts table, the
lunatik-cycle skill and the four design notes that spell `lunatik run <script> softirq` or
`percpu`; the 30 call sites; `percpu.sh:45`'s pattern; `tools/watchdog.sh`, whose usage line and
`"$@"` (`:10`, `:31`) forward the bare words and whose stdout check (`:32`) stands in for the
status; `tests/lib.sh:41-49`, which reads the output for the same reason; and `Makefile:190`,
whose `tests/$$d/*.lua` fails the install of a suite with no `.lua`, #845's one thing in the
way, unless `tests/cli` carries one. The guards keep matching, since the verbs do not move
(`lunatik-lock.sh:15`, `crash-guard.sh:17`, `example-guard.sh:14`), and `-e` joins the REPL as
a request none of them keys on; `commands.sh` learns the options between the verb and the
operand, which `example-guard.sh` reads as `(run|spawn) examples/`. And `tests/cli`, the suite
#845 asks for, is the CLI's own: usage on stderr with exit 2; `-h` on stdout with exit 0; `run`
of a script exit 0 with nothing on stdout, with `-c softirq` and with `-p` the same, of a
missing script exit 1 with the message on stderr and nothing on stdout, and of a script that
errors at load the same; `run -c foo` exit 2; a second `run` of the same script exit 1, already
running; `spawn` exit 0 and listed, and `spawn -c softirq` exit 2 with nothing sent to the
device; `stop` of a running script exit 0 and gone from `list`, of a name nothing runs exit 1,
and of two names with one unknown, whose status the shape does not settle yet; `list` one a
line, and empty with exit 0 when nothing runs; `-V` the version on stdout with exit 0, and with
the modules unloaded; `--` before a script taken as an operand;
`-e 'return 40 + 2'` prints `42`, exit 0, and `-e 'error("x")'` exit 1 with `x` on stderr; a
piped session with no banner; the deprecated spelling accepted with its line on stderr. That
suite is what the phases after it are measured against: a transport that changes no behaviour
of the CLI is proved by the same suite passing.

### Its own track

The transport needs one thing of the command line, the status in the reply, which shape 1's
pull request carries in `driver.lua`; everything else here, the options, the exit status, `stop`
and `list`, the REPL on a pipe, `-e`, `-h` and `-V`, is the CLI's own and answers the family of
#845 and #1083, so it goes as a track of its own, one pull request or a short stack, userspace
and two Lua files, and blocks on nothing. The family's `RUN` and `LIST`, if they come, are named
after the options that then exist, `context` and `percpu`, and the suite that pins the surface
exists before any transport moves under it.

## Phases

1. **A session per open, and the reply keeps its status** (shape 1). `luadevice`'s `write`
   stores the request on the file and `read` on the same descriptor returns its result;
   `driver.lua` stores the pair `pcall` returns, the status before the values; the CLI's
   `dostring` reads on the descriptor it wrote and exits by the status. Tests, a new
   `tests/control` suite: two clients issuing `list` at once each get their own reply; a `read`
   on a descriptor that wrote nothing returns nothing; a refused `run` exits 1. Depends on
   nothing.
2. **The command line**, as the section above shapes it: `bin/lunatik`'s parser and exit
   status, `runner.stop` answering, the 30 call sites, the one `list` pattern and the
   documentation moved, `tests/cli` with the cases listed, which is the suite #845 asks for.
   Userspace and `runner.lua`; the status in the reply is phase 1's when that lands first.
3. **The comparison**, written into this note: what shape 3 buys after phases 1 and 2, a
   capability read from the socket and a typed reply, against what it costs, the family, the
   reply primitive, the worker and a C client. It ends in a choice, build or decline, and the
   two phases below exist only on build.
4. **The queue and the worker** (shape 2), on build. A worker runtime beside `driver` on a
   `fifo` both reach through `lunatik._ENV`; `write` enqueues and returns, the CLI polls `read`
   for the reply, so nothing lands that phase 5 retires; `runner.shutdown` drains the queue
   before the runtime stops. Tests in `tests/control`: a `run` of a script whose body sleeps
   past the CLI's bound leaves the requester with a timeout and exit 1, the worker's
   `/proc/<pid>/stack` naming the script meanwhile, and the next request answered once the body
   returns, since a body that never returns keeps the thread inside it until a reboot on the
   host that runs the suite (AGENTS.md, "Build, install, test"), and is shape 2's statement
   rather than a case; a `stop` of a runtime holding a `netlink.channel` completes, since it
   runs off `cb_lock`. `lunatik-lock.sh:29` stops naming a task in D state, since the requester
   times out; its process match (`:21-23`) and `lunatik-host`'s `flock` read nothing of the
   device.
5. **The family**, on build: `EVAL` first, carrying the same chunk the CLI sends today, so the
   CLI changes its transport and nothing else; the C client; then `RUN`, `SPAWN`, `STOP`,
   `LIST`, `STATUS` as attributes, each a pull request; then the device retires from
   `driver.lua`.

## The locks, traced

| Path | Task | Holds | Reaches |
|------|------|-------|---------|
| `doit` (shape 3) | requester | `cb_lock` read, `genl_mutex` without `parallel_ops` | the queue and a wake-up: nothing that waits |
| driver thread | kthread | nothing of the kernel's | `lunatik_stop`'s `lua_close`: `genl_unregister_family` (`cb_lock` write, `genl_mutex`), `unregister_netdevice_notifier` (RTNL), `sock_release` (RTNL for a membership) |
| file operation (shape 2) | requester | the device's lock, never the runtime's | the queue and the bounded wait |
| a `doit` in flight while the thread unregisters a family | requester | `cb_lock` read for the length of an enqueue | the writer waits that long and no longer |

The cycle #1055 names, a reader holding `cb_lock` while it waits on RTNL against a writer that
holds RTNL, needs a `doit` that waits: this one does not.

## What is not decided here

Whether shape 3 is built at all, which phase 3 decides; the client's language for it, C tool or
a userspace module; whether `EVAL` and `-e` stay once the typed commands exist, which is the
REPL's question; whether `CAP_SYS_MODULE` or
`CAP_SYS_ADMIN` gates a request; whether the policy is the family's, which the 5.4 kernel a
consumer builds on has, or per operation, `genl_ops.policy` since v5.10
(`include/net/genetlink.h`), a floor AGENTS.md asks to be named here; whether `--json` and the
columns of `list` come with the family or with a `runner` that keeps each runtime's context and
percpu flag; and at which release the bare-word spellings of `run` are dropped, which the README
says when the CLI lands. Each is one line to settle when its pull request opens.

