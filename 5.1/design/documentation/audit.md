# Documentation audit

The audit of the documentation against the code at `85d9a1c1c`, from which [plan.md](plan.md) works.
Six auditors read one slice each against the implementation, and every accuracy finding cites the
code that proves it; a second reader per slice tried to refute each one, and the two it refuted are
left out. What a finding cites is the tree at `85d9a1c1c`; a line may have moved since.

Each finding has an identifier a pull request names when it closes it: `G` the README and the guide,
`C` the C API, `MC`, `MN` and `MS` the module docs, `E` the examples and the tests README.

## Coverage

Each unit a reader meets, rated good, adequate, poor or missing, with what it lacks.

### README and guide

| Unit | Rating | What it lacks |
|------|--------|---------------|
| guide as a whole (missing units) | missing | There is no first-script walkthrough (write, install to /lib/modules/lua, run, read dmesg, stop). Also missing: a troubleshooting page (context mismatch, 'not allowed after module load', 'already running', 'loaded from another build', 'missing module BTF', 'couldn't create /dev/lunatik' after a kernel upgrade), a security model (/dev/lunatik and /lib/modules/lua are root code execution in the kernel; binary chunks are loaded unverified, per lua/lundump.c:29-30 empty luai_verifycode and driver.lua:26 load(buf) accepting binary), a concepts page (runtime, object, context, _ENV), and a how-to-write-a-binding guide for users. |
| doc/guide/01-getting-started.md | poor | Deps and build lines only. It lacks btf_install, kernel config requirements, an install check, rebuild after a kernel upgrade, and uninstall. The postinst hook is described without its side effects, and the Arch list is questionable. |
| doc/guide/04-lua.md | poor | Misses the biggest behavioural differences: `/` is floor division, `^` and float literals are gone, print goes to dmesg, and io is absent in IRQ runtimes. It also omits the stub `lunatik` table, the require-after-arm refusal, the reduced math and string.format/pack, and the 200-slot stack. The io error-message claim is wrong for io.open. |
| README.md (landing) | adequate | Clear pitch, a working-looking example and a short quick start. The example needs a manual file placement it does not state, and the quick start skips btf_install, which the eBPF modules need. |
| doc/guide/02-running-scripts.md | adequate | The CLI reference matches bin/lunatik's usage string and exit codes. Missing: the spawn body contract, where output and errors go (dmesg), the REPL chunk and local semantics, context per binding with its error messages, and the side effects of reload and unload. `default` is listed as if it were a verb. |
| doc/guide/03-percpu.md | adequate | Accurate, source-traced dispatch explanation. It lacks a usage example of shared state and the list of bindings that refuse percpu, and its prose is dense for a newcomer. |
| doc/guide/06-development.md | adequate | Test commands are correct. It does not warn that `lunatik test` stops every running script, and it has no pointer to writing a binding (capi.md, the new-binding workflow) beyond AGENTS.md. |
| doc/guide/07-resources.md | adequate | A plain link list; no link was fetched, so reachability is unverified (the google-melange archive link is likely stale). |
| doc/guide/05-examples.md | good | The index matches the 21 example directories and their READMEs. It lacks the run-name convention, eBPF build prerequisites and network-disruption flags. |

### C API (doc/capi.md)

| Unit | Rating | What it lacks |
|------|--------|---------------|
| capi.md: Locking (lunatik_lock/unlock/trylock/closeprivate) | missing | No section, although five bindings lock objects directly and the execution-context rules hinge on it. |
| capi.md: Values (lunatik_value_t, checkvalue, pushvalue) | missing | Exported and used by luarcu; not mentioned. |
| capi.md: eBPF helpers (lunatik_ebpf.h) | missing | A whole macro framework used by tc/xdp/sched with no documentation. |
| capi.md: Types (lunatik_class_t) | poor | Omits the `opener` field (which cloneobject/require depend on), lunatik_object_t, lunatik_opt_t, OPT_IRQ/PERCPU/NONE; `release` timing is wrong; never says a class needs `__gc`. |
| capi.md: Object Lifecycle | poor | newobject lists no raises or preconditions; createobject's gfp rule is misstated; the cloneobject example has a wrong refcount comment and would raise outside a protected call; pushobject, closeprivate, closeobject and deleteobject are missing. |
| capi.md: Object Access | poor | lunatik_toobject is documented as NULL-safe but dereferences NULL; checkshareable/testobject are missing; PRIVATECHECKER(S) is accurate. |
| capi.md: Runtime | adequate | lunatik_runtime/stop/run/cpcall are well explained with a real example, but it lacks the calling context of stop and run, the not-ready -ENXIO case, IRQ-runtime library differences, lunatik_handle's missing safeguards, and lunatik_setruntime/checkcontext/cannotsleep. |
| capi.md: percpu (lunatik_percpudata, LUNATIK_PERCPUDATA) | adequate | Accurate, with a real example, but pin/unpin, getcpu/hascpu, checkpercpu and lunatik_percpu_class are undocumented, and the two headings share one anchor. |
| capi.md: Registry and Attach/Detach | adequate | Flags and register/unregister are precise; registerobject misdescribes what it stores and its stack precondition; the pattern block is pseudo code that uses the unchecked toobject. |
| capi.md: Error Handling | adequate | try/tryret/errmsg match the code; errmsg's last clause is confusing; lunatik_pusherrname and the 'unknown' fallback are absent. |
| capi.md: Table Fields | adequate | The three macros are right apart from optinteger's silent 0; checkfield, optcfunction, checkbounds and checkinteger, which bindings use for input validation, are missing. |
| capi.md: Module Definition | adequate | CLASSES/NEWLIB are clear, with good context notes, but there is no end-to-end binding (opener, __gc, module_init/exit) and no pointer to lib/luaskel.c. |
| capi.md: Memory | adequate | malloc/realloc/free are accurate but omit which gfp is used and the raising allocators (checkalloc/checkzalloc/enomem). |
| capi.md: Runtime guards (isowner, isrtnl, checkarmed, checkrtnl, checkowner) | good | Accurate against the code and states purpose, messages and limits; dense prose, but a reader can act on it. |
| capi.md: Symbols (lunatik_lookup) | good | Accurate: context, cost, failure modes and config dependencies. |

### Core and utility modules

| Unit | Rating | What it lacks |
|------|--------|---------------|
| util | missing | Installed and used by lighten and the tests, but not in config.ld, so it has no page. |
| lunatik.runner | poor | run omits hardirq, claims 'current context' and returns 'table'; spawn hides its context/ispercpu params; nothing ties it to the CLI verbs that call it. |
| linux.* constant modules (autogen stubs) | poor | Every top-level page shows a non-existent `constants` table, lists no constant names, and never states the prefix-stripping rule or a require/usage line; scx does not say it can be empty. |
| signal | poor | One-line module doc; kill's permission/sig-0 claim is wrong; sigstate 'pending' misses process-directed signals; there is no context restriction despite sigprocmask being process-only. |
| data | poor | Most accessors have no description. Byte order, the lifetime of kernel-backed views, the checksum algorithm and the absence of a usage example all go unstated. |
| mailbox | poor | Timeout unit (jiffies vs ms) and the return-vs-raise contract are wrong, capacity is described in messages rather than bytes, the page structure is wrong (phantom table, constructors as methods), and there is no cross-runtime example. |
| lighten | poor | Omits that the key comes from a `light` module and how shade.sh produces it and the ciphertext; following the page, require fails. |
| crypto (module) | poor | Empty page: the constructors crypto.shash/skcipher/aead/rng/comp are not listed, there are no links to the class pages, and neither the process-only restriction nor the errno-named errors are stated. |
| lunatik (lunatik_core.c + lunatik_percpu.c) | adequate | Lifecycle and @raise are thorough, but there is no @usage. The resume protocol is misdescribed (the script must return a function, and the first resume calls it), and it is not said that IRQ runtimes get a stub with only cpu/_ENV and no io. |
| thread | adequate | Good raise detail and a shouldstop usage, but module functions render as methods (thread:run), messages are paraphrased, and there is no complete spawn-script example or context note. |
| linux | adequate | Most functions have usage, but the module blurb is outdated (constants moved out). schedule lacks its sleep/context restriction, lookup its CONFIG_KPROBES requirement, and ifindex/ifaddr the init_net scope. |
| cpu | adequate | Functions listed with params, but the num_* entries have no summaries, stats omits its unit (ns), and there is no usage or relation to linux.numcpus. |
| task | adequate | Methods described, but current() renders as a method; comm/prio ranges are slightly wrong; the meaning of current() inside IRQ callbacks is unstated. |
| fifo | adequate | Usage and bounds are documented, but push/pop render as module functions, 'lockless' and the close/__gc alias are inaccurate, and cross-runtime sharing is not shown. |
| byteorder | adequate | Each function is described, but there is no module purpose, usage or truncation note. |
| struct | adequate | Good module usage, but the constructor and the size field are not rendered, and methods show without a receiver. |
| class | adequate | Clear blurb and usage; the returned function and the __close wiring are not rendered. |
| darken | adequate | Purpose is clear, but the text-only chunk requirement, the process-only context and the exact argcheck messages are missing. |
| crypto_shash | adequate | Methods documented, but the constructor is shown as crypto_shash:new, algname is undocumented, and errors are not named. |
| crypto_skcipher | adequate | Methods documented, but the constructor is shown as :new, algname is undocumented, and the blocksize-multiple input constraint is missing. |
| crypto_aead | adequate | Good description of the tag and AAD layout, but the constructor is shown as :new, algname is undocumented, and the IV error is EINVAL rather than the text given. |
| crypto_rng | adequate | generate misdescribes its seed as a reseed, algname is undocumented, and the constructor is shown as :new. |
| crypto_comp | adequate | States the 6.15 removal, but the constructor is shown as :new and nothing says crypto.comp is nil on newer kernels. |
| crypto.hkdf | adequate | RFC reference and a usage example are present, but the close/GC claim is wrong, the 255*HashLen limit is not stated, and it does not say it is process-only through shash. |
| completion | good | Purpose, usage and returns are clear; only the 'runtime context mismatch' raise is missing. |

### Networking modules

| Unit | Rating | What it lacks |
|------|--------|---------------|
| socket.raw | poor | One function with no guidance on sending or on the AF_PACKET address shape, and a usage whose names contradict the description. |
| netfilter | poor | A one-line module doc with no usage. It omits the softirq requirement, the callback signature and return contract, that `mark` is a filter, that the hook is init_net only, and that register must run in the script body. register renders as a method of netfilter_hook. |
| skb | poor | Methods are listed, but it never says where an skb comes from or how long it is valid (`skb is not set`). data() layer semantics are wrong in TC, the CONFIG requirement for connmark is missing, resize and checksum preconditions are absent, and there is no usage. |
| netlink.rt (route, link, addr, rule, object) | poor | Record fields and address byte formats are undocumented, there is no @raise on add/del, the constructor and its pid appear on no subclass page, and `:new` is presented as the constructor. |
| socket (lib/luasocket.c) | adequate | Detailed per-method docs and usages, but the per-family address contract is wrong for AF_PACKET and AF_NETLINK. It says nothing about blocking or process context, the usages cite a nonexistent `.sk` field, and it claims constants it does not export. |
| socket.inet | adequate | Clear constructor usage and method set. The receive varargs are described loosely, there is no namespace or blocking note, and `:new` is shown as a constructor. |
| socket.unix | adequate | Abstract-name and autobind semantics are documented well. It overstates where the stored path is reused and has no @usage for a full stream or dgram exchange. |
| net | adequate | Purpose and usage are present; it lacks input-validation behaviour and a byte-order note for use with netlink attributes. |
| skb.attr | adequate | The purpose is clear. The constructor renders as a method, and there is no @usage and no mention of the unknown-key error. |
| xdp | adequate | Good mechanism overview and usage, but the usage's runtime key is wrong (.lua). The context rule says non-sleepable where it means softirq, and BTF/bpftool requirements are missing. |
| tc | adequate | Same shape and gaps as xdp; the skb it hands out starts at L2, which the skb docs contradict. |
| netlink | adequate | A namespace index; fine as a hub but has no overview usage tying channel, rt and genl together. |
| netlink.channel | adequate | Context rules and raises are well stated. It never names the `lunatik` multicast group userspace must join, the init_net-only unicast, or gives a usage. |
| netlink.session | adequate | The transaction discipline and namespace pid are documented. The RTNL refusal, the unbounded blocking receive and the error-name format are missing. |
| netlink.genl | adequate | The API is documented, but the family raise message differs from the doc and there is no usage. |
| netlink.message | adequate | The codec functions are documented; it does not say that parsed keys keep the NLA_F_* bits or how to parse nested attributes. |
| netlink.nl80211 (ap, interface, station, wiphy, object) | adequate | The parameter tables are listed. The constructors (call with pid) show only on the object page, the cfg80211 requirement is unstated, and there are no usages. |
| generated pages (doc/modules, doc/classes for this slice) | adequate | They render all modules; the problems are netfilter register rendered as a method, skb.attr new rendered as a method, and type cross-links that point at missing anchors. |
| notifier | good | The context per constructor, the netdevice replay, namespaces and RTNL are stated. It lacks the raising-callback outcome and complete @raise lists. |

### Tracing, device, eBPF, filesystem and data-structure modules

| Unit | Rating | What it lacks |
|------|--------|---------------|
| lunatik_ebpf.h (C helper for xdp/tc/sched kfuncs) | missing | It has no doc block and no entry in doc/capi.md. The runtime-key contract (script name without .lua, key size includes the NUL, process-context runtimes not dispatched) is stated only partially in sched. |
| sched (lib/luasched.c) | poor | The context is wrong (says non-sleepable, the code needs hardirq), the kfunc key example does not match, BTF and the no-CONFIG behaviour are missing, the signature renders broken and it cites an example that does not exist. |
| probe (lib/luaprobe.c) | poor | `new` is detailed, but the module doc is one line and has no usage. It never states the hardirq requirement or what handlers may do, and `new` renders as a method. |
| hid (lib/luahid.c) | poor | One-line module doc, and the callbacks, their arguments and fields, the softirq requirement, the lifetime, the usage and example pointers are all missing. `register` renders as a method. |
| bpf (lib/luabpf.c) | adequate | Every method is documented with types and has a usage. It lacks the requirements (BPF_SYSCALL, pinned maps, linux.bpf flags), the next/restart caveat and complete @raise lines. |
| syscall (lib/luasyscall.c) | adequate | Has a purpose and a usage. The nil return claim is false, and it does not warn that the address is a pt_regs wrapper when probing. |
| syscall.table (lib/syscall/table.lua) | adequate | Clear purpose and usage. It could state that keys are `__NR_` names with the prefix removed and that it inherits syscall's caveats. |
| device (lib/luadevice.c) | adequate | Callback contract and EDEADLK/ECANCELED behaviour are good. The process-context requirement is missing, the usage never reaches EOF, release(2) is wrong and `new` renders as a method. |
| rcu (lib/luarcu.c, lib/luarcu.h) | adequate | The SRCU/RCU semantics of reads, writes and map are precise. rcu.map is documented and rendered as a method, which fails. SINGLE objects being refused is not stated, and LUARCU_MAXKEY is given without its value. |
| generated pages doc/modules/{bpf,bpf.map,sched,probe,syscall,syscall.table,fsnotify,device,hid,rcu,set}.html | adequate | They build, but constructors without @within render as methods on probe, device, hid, set and rcu.map. The sched kfunc signature loses its asterisks to markdown, and the linux.* constant pages carry no constant names. doc/classes has no pages for these modules; they all render under doc/modules. |
| bpf.map (lib/bpf/map.lua) | good | Clear model, spec rules and usage. It misses array delete raising EINVAL, the iteration restart caveat and the interrupt-context rule it inherits from bpf. |
| fsnotify (lib/luafsnotify.c) | good | Thorough: purpose, delivery context, permission verdicts, kernel version and CONFIG gates, @raise matching the code, and usage on every method. Only the linux.fs bit names are missing from the site. |
| set (lib/luaset.c) | good | Clear cost model, semantics and usage. Only rendering problems: new and labeled appear as methods, and __len as a module function. |

### Examples and tests README

| Unit | Rating | What it lacks |
|------|--------|---------------|
| examples/dnsdoctor/README.md | poor | setup.sh blocks in the foreground, needs python venv and pip, and rewrites the host's resolv.conf; none of that is said. Cleanup unloads every module, and the hardcoded addresses are not pointed to. |
| examples/echod/README.md | poor | One-line purpose, no stop command, and no word on the worker-thread model or the port. |
| examples/filter/README.md | poor | Dangling 'cf. above' and LUNATIK_DIR text, a typo'd object path, a duplicate pin load in the docker section, a wrong line anchor, no mention of clang or BTF, and no teardown. |
| examples/gesture/README.md | poor | The VM configuration is incomplete: it turns PS/2 off and adds no USB input. The device the driver actually decodes (16-bit absolute X) is unclear. Typos, and no stop. |
| examples/cpuexporter/README.md | adequate | Usage works. The format claim (OpenMetrics) does not match the output: timestamps are in µs and there is no # EOF. HTTP /metrics mode and the stop step are undocumented. |
| examples/dnsblock/README.md | adequate | Commands and context are right. It does not say the filter is IPv4/UDP only, where the blacklist lives, how to test or stop it, or that the two run lines are alternatives. |
| examples/keylocker/README.md | adequate | Context is stated correctly. Missing: CONFIG_VT, console-only input, and how to recover with lunatik stop. |
| examples/lldpd/README.md | adequate | ip link commands have no sudo. No stop or teardown. The interface is hardcoded and the 30 s interval is unsaid. |
| examples/shared/README.md | adequate | Protocol usage is correct. Missing: stop, the one-client-at-a-time limit, that a stop waits on a connected client, and the key/value character set. |
| examples/sniclassify/README.md | adequate | Setup and cleanup scripts are right. Wrong policy anchor, bpftool and clang unstated, the root qdisc replacement is not warned about, the verify command misses the egress filter, and there is no traffic stimulus. |
| examples/spyglass/README.md | adequate | Runtime split and contexts are right. CONFIG_VT, console-only input and the stop step are missing. |
| examples/systrack/README.md | adequate | Flow and output are right. 'Every system call' overstates it, since aliases are skipped, and the kprobes requirement is unsaid. |
| examples/tap/README.md | adequate | Minimal but correct. No stop, and the output columns (hex MACs without leading zeros) are not explained. |
| examples/tcpreject/README.md | adequate | Clear mechanism. Test commands have no sudo, and cleanup forces forwarding off on the host, which is not said. |
| examples/xiaomi/README.md | adequate | Purpose and context are right. The conflict with the in-tree hid-xiaomi driver and the Bluetooth-only match are not mentioned. |
| doc/guide/05-examples.md | adequate | Accurate index with working links (rewritten to GitHub in the generated site), covering all 21 examples. It lacks a per-example context, verb and requirements view and any word on host impact. |
| examples/dropreason/README.md | good | Clear purpose, context, REPL usage and kernel-version behaviour. Only CONFIG_KPROBES and CONFIG_HAVE_FUNCTION_ARG_ACCESS_API are missing. |
| examples/execguard/README.md | good | Thorough on scope, limits, failure modes and both usage flows. The default allowlist is named only by example ('true'); stating 'true' and 'false' and where to edit them would help. |
| examples/fsmonitor/README.md | good | Purpose, limits, full usage with sample output, and an explanation of the double modify event. |
| examples/ifquarantine/README.md | good | Architecture, contexts, replay semantics and control-device usage are all covered. It could warn that denying the uplink cuts the host off. |
| examples/linkflap/README.md | good | Complete runnable flow with the subscriber build, expected output and teardown. |
| examples/netfailover/README.md | good | Explains why there are two runtimes and gives a full flow with expected route output. How to receive the channel announcements is not documented. |
| tests/README.md | good | Every suite and every test script run by each suite's run.sh is described, and all 30 suites are wired in tests/run.sh. Gaps: the crypto algorithm tests are not described, the unix/abstract peer is said to need python3 when it needs gcc, there is no consolidated optional-tool list, and one sentence is history. |

## Findings

### README and guide

#### G-01 · `doc/guide/01-getting-started.md:38` · missing · high

The build steps (and the README's Get started) are `make && sudo make install`, with no `sudo make btf_install` before `make`. Only examples/filter/README.md and examples/sniclassify/README.md mention btf_install.

*Evidence.* Makefile:243-244 `btf_install:` / `cp /sys/kernel/btf/vmlinux ${BTF_INSTALL_PATH}`. Without vmlinux in the build dir the kernel skips module BTF (linux scripts/Makefile.modfinal:39-40 `if [ ! -f vmlinux ]; then printf "Skipping BTF generation...`). The eBPF modules' init is only the kfunc registration: lunatik_ebpf.h:141-145 `static int __init lua##subsys##_init(void) { return register_btf_kfunc_id_set(prog_type, ...); }`, used by lib/luaxdp.c:255, luatc.c and luasched.c. The kernel then refuses it: kernel/bpf/btf.c:7973 `pr_warn("missing module BTF, cannot register kfuncs\n")`. bin/lunatik:36-38 runs `modprobe` for each module and ignores failures, so `lunatik load` still succeeds while xdp, tc and sched stay unloaded.

*Fix.* In 01 'Compile and install' and in the README's Get started, run `sudo make btf_install` before `make`. Add one sentence: without it, xdp and tc (and sched on a kernel with sched_ext) fail to load with `missing module BTF, cannot register kfuncs` in dmesg, `lunatik load` still succeeds, and `sudo lunatik status` lists them as not loaded.

#### G-02 · `doc/guide/02-running-scripts.md:29` · missing · high

The `spawn` bullet says only 'spawn a thread to run the script'. It does not say the script must return the thread body, that the body must poll `thread.shouldstop()`, or that blocking calls must be bounded. A body that never returns makes `lunatik stop` hang.

*Evidence.* lib/lunatik/runner.lua:72 `The spawned script is expected to return a function, which will then be executed in the new thread.` lib/luathread.c:71-73 `luathread_shouldstop ... kthread_should_stop()`. runner.lua:96-99 stop stops the thread before the runtime, and kthread_stop waits for the body to return.

*Fix.* After the spawn bullet, add the minimal body (`local thread = require("thread"); local linux = require("linux"); return function() while not thread.shouldstop() do ... linux.schedule(100) end end`) and the rule: return the body, poll `thread.shouldstop()`, and bound every blocking call with a timeout, or `lunatik stop` never returns.

#### G-03 · `doc/guide/01-getting-started.md:42` · unclear · medium

'the `debian_kernel_postinst_lunatik.sh` script from tools/ may be copied into /etc/kernel/postinst.d/: this ensures lunatik ... will get compiled on kernel upgrade'. The sentence hides several side effects: the script builds from its own clone of master in /opt/lunatik rather than the reader's checkout; it replaces /usr/sbin/bpftool; it downloads kernel sources; it copies the running kernel's BTF, not the new kernel's; and it exits 1 if a dpkg package named `pahole` is missing, although the guide installs `dwarves`. tools/Readme.md also renames it to `zz-update-lunatik`, which the guide omits (Debian's run-parts skips names containing a dot; that rule was not verified on this host).

*Evidence.* tools/debian_kernel_postinst_lunatik.sh:3 `LUNATIK_DIR="/opt/lunatik"`. :38 `git pull --ff-only`. :21 `dpkg --get-selections | grep 'pahole\s' | grep install || exit 1`. :22 `cp /sys/kernel/btf/vmlinux "/usr/lib/modules/${KERNEL_RELEASE}/build/"` (the running kernel's BTF during the new kernel's postinst). :34 `mv /usr/sbin/bpftool /usr/sbin/bpftool.orig`. The kernel package runs the directory with `run-parts --report --exit-on-error` (linux debian/templates/image.postinst.in:56-57). tools/Readme.md:9 `sudo cp ... /etc/kernel/postinst.d/zz-update-lunatik`.

*Fix.* Point 01 at tools/Readme.md for the exact install command (the zz-update-lunatik name). State what the hook does: it clones and builds master under /opt/lunatik, builds resolve_btfids, bpftool (replacing /usr/sbin/bpftool) and xdp-loader, and a failure aborts the kernel package's postinst. File an issue for the script copying the running kernel's BTF, and reading the running kernel's version, during the new kernel's postinst.

#### G-04 · `doc/guide/01-getting-started.md:50` · missing · medium

The guide has no rebuild-after-kernel-upgrade step (without the hook), no uninstall, and no install check. The modules are installed per kernel release, so after an upgrade `sudo lunatik` fails.

*Evidence.* Makefile:37 `MODULES_RELEASE_PATH := ${MODULES_PATH}/${KERNEL_RELEASE}`, Makefile:43 `MODULES_INSTALL_PATH := ${MODULES_RELEASE_PATH}/kernel`. bin/lunatik:39-41 `if not probe() then error("couldn't create " .. device, 0)`. Makefile:256 `uninstall: scripts_uninstall modules_uninstall examples_uninstall tests_uninstall`.

*Fix.* Add 'After a kernel upgrade': install the new headers, then run `make clean && sudo make btf_install && make && sudo make install`. Add 'Uninstall': `sudo lunatik unload && sudo make uninstall`, and remove the postinst hook if one was installed. Add 'Check the install': `sudo lunatik status` and `sudo lunatik -V`.

#### G-05 · `doc/guide/02-running-scripts.md:21` · missing · medium

The load/unload/reload/status bullets omit several behaviours: reload's refusal of a module loaded from another build, status's 'is not the installed build' line, unload stopping all scripts, and load ignoring a module that fails to load.

*Evidence.* bin/lunatik:98-101 `error("couldn't replace " .. table.concat(stale, ", ") .. ": loaded from another build", 0)`. bin/lunatik:108-110 `print(m .. " is not the installed build")`. bin/lunatik:36-38 `sh("modprobe $MODULE", m)` with its result unchecked, and only /dev/lunatik is checked (39-41).

*Fix.* unload: "stops every running script, then removes the modules". reload: "...and fails with `couldn't replace <modules>: loaded from another build` when a loaded module is not the installed file". status: "also names a loaded module that is not the installed build". load: "a module that fails to load is skipped silently; check `lunatik status` and dmesg".

#### G-06 · `doc/guide/02-running-scripts.md:31` · missing · medium

The REPL entry does not say that each line is a separate chunk, so `local` variables do not survive to the next line while globals do. It also omits that the REPL runs in the process-context `driver` runtime shared by every CLI session, so a softirq hook cannot be registered from it directly.

*Evidence.* driver.lua:25-27 `function driver:write(buf, off, file) local chunk, err = load(buf) ...` (one load per write). bin/lunatik:221 `dostring(expr and ("return " .. chunk) or chunk)` sends one chunk per line or continuation. lunatik_run.c:24 `lunatik_runtime(&runtime, "driver", LUNATIK_OPT_NONE)`.

*Fix.* Add to the REPL bullet: "Each entry is its own chunk, so a `local` is gone on the next line; use a global, or one multi-line entry. Every `lunatik` invocation shares one process-context runtime, so register a softirq or hardirq hook from a script started with `lunatik run <script> softirq`."

#### G-07 · `doc/guide/02-running-scripts.md:47` · missing · medium

The page names only netfilter, XDP (softirq) and kprobes (hardirq). It does not give the context for the other hook bindings, or the error a mismatch raises.

*Evidence.* lib/luatc.c:240 `lunatik_checkruntime(L, LUNATIK_OPT_SOFTIRQ)`. lib/luasched.c:247 `lunatik_checkruntime(L, LUNATIK_OPT_HARDIRQ)`. lib/luahid.c:77 `.opt = LUNATIK_OPT_SOFTIRQ | LUNATIK_OPT_SINGLE` with setruntime at :301. lib/luanotifier.c:202,226 keyboard and vt use `luanotifier_hardirq_class`, netdevice uses the process class (:175). lib/luabpf.c:380 HARDIRQ. lunatik.h:193 `LUNATIK_ERR_RUNTIME "runtime context mismatch"` and lunatik.h:192 `"process-context class in interrupt-context runtime"`.

*Fix.* Replace the sentence with a table of binding and required runtime: netfilter, xdp, tc and hid need softirq; probe, sched, notifier.keyboard and notifier.vterm need hardirq; notifier.netdevice, fsnotify, device, completion waits, socket and thread need process. bpf maps are usable from any runtime. Add: "a hook registered from the wrong context raises `runtime context mismatch`; a process-only object created in an IRQ runtime raises `'<class>': process-context class in interrupt-context runtime`."

#### G-08 · `doc/guide/03-percpu.md:20` · unclear · medium

The page says 'State that must see a whole flow therefore belongs in something the runtimes share, a table published in `lunatik._ENV`' but gives no way to publish one table exactly once, although each body runs once per runtime. It also does not list which bindings refuse to load in a percpu runtime.

*Evidence.* lunatik_percpu.c:225-230 `for_each_possible_cpu(cpu) { if (lunatik_newruntime(...)` runs the bodies one after another in the caller. lunatik_percpu.h:71-76 `LUNATIK_ERR_PERCPU "not allowed in a percpu runtime"`. lunatik_checkpercpu is called by lib/luadevice.c, luahid.c, luafsnotify.c, luanetlink.c and luanotifier.c. lunatik_percpudata is used by luanetfilter.c and luaprobe.c only.

*Fix.* Add an example to 03: `local env = lunatik._ENV; env.flows = env.flows or rcu.table()`, which is safe because the bodies run one after another, then the lookup in the hook. Add one line naming device, hid, fsnotify, netlink and notifier as raising `not allowed in a percpu runtime`, while netfilter hooks and kprobes are registered once and shared. Say that one runtime is created per possible CPU.

#### G-09 · `doc/guide/04-lua.md:9` · missing · medium

The page says only that floats and the `__div`/`__pow` metamethods are unsupported. It does not say that the `/` operator is floor (integer) division, that `^` is not an operator, or that a float literal does not parse.

*Evidence.* lua/lparser.c:1331-1336 (submodule at 74f1f100) `#ifndef _KERNEL case '^': return OPR_POW; case '/': return OPR_DIV; #else /* _KERNEL */ case '/': return OPR_IDIV;`. lua/llex.c:268-269 `#else /* _KERNEL */ if (lisxdigit(ls->current))`: '.' does not continue a numeral, so `1.5` raises 'malformed number' (llex.c:281-282).

*Fix.* Under 'Floating-point numbers' add: "Numbers are 64-bit integers. `/` is floor division, the same as `//`, so `7 / 2 == 3`. `^` is not an operator. A literal with a decimal point or an exponent (`1.5`, `1e3`) is a syntax error. Use fixed point where a fraction is needed."

#### G-10 · `doc/guide/04-lua.md:18` · inaccurate · medium

'The `math` library is present but all floating-point functions are absent — only integer operations are supported.' This implies that every integer-valued function remains. In fact `math.random`, `math.randomseed`, `math.floor`, `math.ceil`, `math.fmod`, `math.type`, `math.pi` and `math.huge` are all absent.

*Evidence.* lua/lmathlib.c:720-770 the kernel table keeps only `abs`, `tointeger`, `ult`, `max`, `min`, `maxinteger` and `mininteger`. random/randomseed/floor/ceil/fmod/type are under `#ifndef _KERNEL`.

*Fix.* "`math` keeps `abs`, `max`, `min`, `tointeger`, `ult`, `maxinteger` and `mininteger`. Everything else is absent, including `math.random` (use `linux.random`), `math.floor` and `math.type` (use `type(x) == "number"`)."

#### G-11 · `doc/guide/04-lua.md:21` · missing · medium

The page presents the io library as supported and never says it is absent from softirq and hardirq runtimes. It also omits that the `lunatik` table there is a stub, and that `require` of a Lua file fails once an IRQ runtime is armed.

*Evidence.* lunatik_core.c:241-247 `if (!(lunatik_isirq(...))) { luaL_openlibs(L); luaL_requiref(L, "lunatik", luaopen_lunatik, 0); } else { luaL_openselectedlibs(L, ~LUA_IOLIBK, 0); luaL_requiref(L, "lunatik", luaopen_lunatik_stub, 0); }`. lunatik_core.c:184-187 the stub holds only `{"cpu", lunatik_cpu}`. lunatik_aux.c:42-44 `if (unlikely(lunatik_cannotsleep(L, lunatik_isready(...)))) { lua_pushfstring(L, "cannot load file on non-sleepable runtime");`. tests/io/softirq.lua:7 `assert(io == nil, "io must not be available in softirq runtime")`.

*Fix.* Add a section 'Softirq and hardirq runtimes': "`io` is nil. `lunatik` carries only `cpu()` and `_ENV`, so `lunatik.runtime` and `lunatik.percpu` are unavailable. `require` Lua libraries at the top level of the script, because loading a file from a hook raises `cannot load file on non-sleepable runtime`."

#### G-12 · `doc/guide/04-lua.md:27` · inaccurate · medium

'On failure, error messages always read "I/O error" regardless of the underlying errno.'

*Evidence.* include/errno.h:9 `static __maybe_unused int errno;` is never set by the VFS-backed FILE in include/stdio.h. lua/liolib.c:276-278 io_open sets `errno = 0;` and returns `luaL_fileresult(L, 0, filename)`. lua/lauxlib.c:257 `msg = (en != 0) ? strerror(en) : "(no extra info)";` then `lua_pushinteger(L, en)`. So `io.open` fails with `nil, "<name>: (no extra info)", 0`. Only raising paths such as `io.lines` (liolib.c:266 `strerror(errno)`, include/string.h:11 `#define strerror(n) "I/O error"`) read "I/O error".

*Fix.* "On failure no errno is reported: `io.open` returns `nil, "<file>: (no extra info)", 0`, and the functions that raise (`io.lines`) say `I/O error`. The cause (ENOENT, EACCES) is lost." The auditor's alternative of setting errno in include/stdio.h would not reach lauxlib.c, which has its own static copy: errno has to become one shared object first, which is a code change with an issue of its own.

#### G-13 · `doc/guide/04-lua.md:29` · missing · medium

The page does not say where `print` and `warn` output goes. A newcomer running `print` in a script or at the REPL sees nothing on the terminal.

*Evidence.* lunatik_conf.h:22-24 `#define lua_writestring(s,l) printk(KERN_CONT "%s",(s))` / `#define lua_writeline() pr_cont("\n")` / `#define lua_writestringerror(...) printk(KERN_ERR KERN_CONT __VA_ARGS__)`. Thread body errors also go to the log: lib/luathread.c:~36 `pr_err("[%p] %s\n", thread, lunatik_errmsg(L))`.

*Fix.* Add to 'Lunatik modifies': "`print` writes to the kernel log (`dmesg -w` or `journalctl -k -f`), not to a terminal, and `warn` writes at KERN_ERR. Errors raised in a spawned thread are logged there too. At the REPL and with `-e`, only returned values come back to the terminal."

#### G-14 · `doc/guide/04-lua.md:29` · missing · medium

The Lua stack limit is not mentioned. It is 200 slots instead of upstream's 1,000,000, so deep recursion or a large `table.unpack` raises 'stack overflow'.

*Evidence.* lunatik_conf.h:76-77 `#undef LUAI_MAXSTACK` / `#define LUAI_MAXSTACK  200`.

*Fix.* Add a bullet: "A coroutine's Lua stack holds at most 200 slots (LUAI_MAXSTACK). This bounds recursion depth and the number of values `table.unpack` and varargs can carry; going past it raises `stack overflow`."

#### G-15 · `doc/guide/06-development.md:13` · missing · medium

The page says `lunatik test` reloads the modules before the run and unloads them afterwards. It does not say that this stops every running script, because the reload runs the runner shutdown.

*Evidence.* bin/lunatik:131-134 `reload_modules() ... unload_modules()`. bin/lunatik:85-88 `unload_modules` runs `dostring("lunatik.runner.shutdown()")`. lib/lunatik/runner.lua:116-118 `rcu.map(env.runtimes, runner.stop)`.

*Fix.* In 06, add: "`lunatik test`, `reload` and `unload` first stop every running script, so do not run the suites on a machine whose scripts must stay up." In 02, say the same on the unload and reload bullets.

#### G-16 · `README.md:17` · unclear · low

The passwd example says only `-- /lib/modules/lua/passwd.lua` and `sudo lunatik run passwd`. It does not say the reader must create that file (no example installs it), how to stop the device, or that `make install` must have run first.

*Evidence.* ls examples/ has no passwd directory. Makefile:195-203 installs only examples/*/ into /lib/modules/lua/examples/. lib/lunatik/runner.lua:59-67 runs `/lib/modules/lua/<script>.lua`.

*Fix.* Under the snippet, add: "Save it as /lib/modules/lua/passwd.lua (as root), then run `sudo lunatik run passwd` and `head -c 16 /dev/passwd`, and stop it with `sudo lunatik stop passwd`."

#### G-17 · `README.md:63` · unclear · low

The Lua copyright link points at `lua.h#L530-L556` on the moving `lunatik` branch. In the pinned submodule the notice sits at lines ~545-574, so the anchor drifts.

*Evidence.* lua/lua.h:548 `* Copyright (C) 2020-2026 Ring Zero Desenvolvimento de Software LTDA.` and :551 `* Copyright (C) 1994-2026 Lua.org, PUC-Rio.` at submodule commit 74f1f100 (lua.h is 574 lines).

*Fix.* Link `https://github.com/luainkernel/lua/blob/74f1f100cb58a23b4ff7625a99715394540beba9/lua.h#L546-L571`, or the file with no line range.

#### G-18 · `doc/guide/01-getting-started.md:13` · unclear · low

The Arch package list includes `build2`, a C++ build toolchain that the Makefile does not use, and omits `base-devel` (cc, make) and `pahole`, which the kernel's module BTF step needs. Nothing on the page says the CLI needs `/usr/bin/lua5.5`, which the Arch `lua` package is not shown to provide (not verified).

*Evidence.* Makefile:61 `HOSTCC ?= cc`. Makefile:111 `${MAKE} -C ${MODULES_BUILD_PATH} M=${PWD}`. Makefile:47 `LUA ?= lua5.5`. bin/lunatik:1 `#!/usr/bin/lua5.5`. linux scripts/Makefile.modfinal:42 `$(PAHOLE) -J ... --btf_base vmlinux`.

*Fix.* Replace `build2` with `base-devel pahole libelf`. Add: "the CLI runs under `/usr/bin/lua5.5` and the build calls `lua5.5`. Where the distribution installs Lua 5.5 under another name, build it from source as below or pass `LUA=` to make."

#### G-19 · `doc/guide/02-running-scripts.md:18` · unclear · low

'`-e <chunk>`: run the chunk in the kernel and print what it returns'. Unlike REPL lines, the chunk is not prefixed with `return`, so `lunatik -e 1+1` is a syntax error.

*Evidence.* bin/lunatik:247-251 `eval(chunk)` → `dostring(chunk)`. The REPL's `try_as_expr` at bin/lunatik:201-203,221 applies only to REPL lines.

*Fix.* "`-e <chunk>`: run a chunk in the kernel and print what it returns, e.g. `sudo lunatik -e 'return _VERSION'`."

#### G-20 · `doc/guide/02-running-scripts.md:21` · broken-link · low

On the generated page, the verb `load` is linked to the Lua manual's `load` function, and the `-o` option is linked to a nonexistent anchor `02-running-scripts.md.html#dumbo`. On 01-getting-started, `lunatik` (the CLI) and `xdp` (xdp-tools) are linked to the `lunatik` and `xdp` Lua modules.

*Evidence.* doc/topics/02-running-scripts.md.html:163 `<a href="https://www.lua.org/manual/5.5/manual.html#pdf-load">load</a>: load Lunatik kernel modules`. :239 `<a href="../topics/02-running-scripts.md.html#dumbo">-o</a> output`. doc/topics/01-getting-started.md.html:185 `<a href="../modules/lunatik.html#">lunatik</a> (and also the <a href="../modules/xdp.html#">xdp</a> needed libs)`.

*Fix.* Keep CLI verbs, options and tool names out of LDoc's backtick auto-linking. Either use <code> or fenced blocks for them, and write 'xdp-tools' rather than `xdp`, or set `backtick_references = false` in config.ld and use @{} where a link is wanted, after checking the API pages that rely on backticks.

#### G-21 · `doc/guide/02-running-scripts.md:28` · inaccurate · low

The run bullet reads '`run [process|softirq|hardirq] [percpu]`' and leaves out the script argument, which the synopsis (line 9) and the CLI both require.

*Evidence.* bin/lunatik:305 `scripted = {run = true, ...}`; bin/lunatik:353-355 `if takes and script == nil then misuse(verb .. " takes a script")`.

*Fix.* Write the bullet as '`run <script> [process|softirq|hardirq] [percpu]`'.

#### G-22 · `doc/guide/02-running-scripts.md:29` · missing · low

The spawn bullet does not say that spawn takes no context and no percpu. The context table's 'always for spawn' implies it, but the CLI refuses both.

*Evidence.* bin/lunatik:307-310 `if verb ~= "run" and select("#", ...) > 0 then misuse(verb .. " takes no context and no percpu")`; lib/lunatik/runner.lua:79-81 `error("spawn does not support percpu scripts", 0)`.

*Fix.* Add to the spawn bullet: 'always in process context; it takes no context and no percpu'.

#### G-23 · `doc/guide/02-running-scripts.md:31` · inaccurate · low

'`default`: start a REPL...' is listed among the commands, but `default` is not a verb.

*Evidence.* bin/lunatik:342-344 `if verb == nil then return start_repl() end`. bin/lunatik:349-351 `local takes = scripted[verb]; if takes == nil then misuse("unknown command " .. verb)`. `lunatik default` exits 2.

*Fix.* Rename the bullet to "no command (`sudo lunatik`)".

#### G-24 · `doc/guide/02-running-scripts.md:75` · inaccurate · low

'`BYTECODE=1 make install` installs...' is shown without sudo, but the target writes to /lib/modules and installs as root.

*Evidence.* Makefile:58 `INSTALL = install -o root -g root`. Makefile:44 `SCRIPTS_INSTALL_PATH := ${MODULES_PATH}/lua`.

*Fix.* `sudo make install BYTECODE=1` (after `make`).

#### G-25 · `doc/guide/04-lua.md:16` · missing · low

The string library's float formats and pack options are not mentioned.

*Evidence.* lua/lstrlib.c:1338-1356 `#ifndef _KERNEL case 'a': case 'A': ... case 'f': ... case 'e': case 'E': case 'g': case 'G':` are removed from string.format. lua/lstrlib.c:1529-1535 `#ifndef _KERNEL case 'f': ... case 'd': ... #else case 'n': *size = sizeof(lua_Number); return Kint;`.

*Fix.* Add: "`string.format` has no `%a %e %f %g` conversions. `string.pack`/`unpack` have no `f` or `d` options, and `n` packs a 64-bit integer."

#### G-26 · `doc/guide/04-lua.md:33` · unclear · low

'require: only supports built-in or already linked C modules' is correct but not actionable. It does not say that the CLI's `load` (or its first use) modprobes every configured module, or which message a module disabled at build time gives. `_LUNATIK_VERSION` is also undocumented.

*Evidence.* bin/lunatik:35-38 `for _, m in ipairs(modules) do sh("modprobe $MODULE", m) end` with modules from autogen/lunatik/config.lua (autogen.lua:430-440). lunatik_conf.h:63 `"%s not found in kernel symbol table"`. Makefile:86-87 `# CONFIG_LUNATIK_SYSCALL := n`. lunatik_core.c:35-38 `lua_setglobal(L, "_LUNATIK_VERSION")`.

*Fix.* "`require("x")` finds a Lua file on package.path, or the C opener `luaopen_x` exported by a Lunatik module already loaded. The CLI loads every module that was built (set `CONFIG_LUNATIK_<X> := n` in the Makefile to leave one out); a missing one raises `luaopen_x not found in kernel symbol table`. The global `_LUNATIK_VERSION` holds the Lunatik release."

#### G-27 · `doc/guide/05-examples.md:3` · unclear · low

The index does not say how an installed example is named when run (`examples/<dir>/<script>`), which ones need `make ebpf`, `sudo make ebpf_install` and btf_install, or which ones arm hooks that can cut the host's network.

*Evidence.* Makefile:197-203 installs into `${SCRIPTS_INSTALL_PATH}/examples/$$d`. Makefile:183-190 `ebpf:` / `ebpf_install:` build and install only filter and sniclassify. examples/filter/README.md:17 and examples/sniclassify/README.md:12 `sudo make btf_install`.

*Fix.* Add a line: "Run an example as `sudo lunatik run examples/<dir>/<script> [softirq|hardirq]`; its README names the context." Mark filter and sniclassify as needing `sudo make btf_install && make && make ebpf && sudo make ebpf_install`. Flag the examples that change the host's traffic (ifquarantine, tcpreject, dnsblock, dnsdoctor), and point at tools/watchdog.sh for running them.

### C API (doc/capi.md)

#### C-01 · `doc/capi.md:391` · inaccurate · high

The cloneobject example calls `lunatik_cloneobject(L, obj)` directly inside a `lunatik_run` handler, with the comment `/* pushes userdata, increments refcount */`, followed by `lunatik_getobject(obj)`.

*Evidence.* lunatik_obj.c:57-70 lunatik_cloneobject only pushes: it takes no reference (`*pobject = object;`), and it can raise: `luaL_error(L, "'%s': %s", class->name, LUNATIK_ERR_SINGLE);` (61-62), `lunatik_checkclass(L, class);` (64), `lunatik_newpobject` allocation and `lunatik_setclass` -> "metatable not found" (lunatik.h:254-255). lunatik.h:56-72 lunatik_run calls the handler with no protected call, and capi.md:201-202 itself says "a raise with no handler is a `BUG()`". lunatik.h:312-316 `lunatik_pushobject` is exactly clone + getobject. Every core caller clones under a pcall (lunatik_val.c:152-177 lunatik_pushvalue, lunatik_core.c:97-121).

*Fix.* Correct the comment to `/* pushes userdata; takes no reference */`, and show the push under a protected call: the lunatik_run handler calls `lunatik_cpcall(L, l_use, obj)`, and `l_use` does `lunatik_pushobject(L, lua_touserdata(L, 1));` and then the work that uses the object (lunatik_cpcall drops f's results, so the object is used inside `l_use`, or stored before it returns). Document lunatik_pushobject (clone plus the reference the new userdata's __gc drops) beside cloneobject, and list what cloneobject raises: `'<name>': cannot share SINGLE object`, `'<name>': process-context class in interrupt-context runtime`, `'<name>': metatable not found`, and out of memory.

#### C-02 · `doc/capi.md:438` · inaccurate · high

lunatik_toobject "Returns `NULL` if the value is not a userdata" (and the registry pattern at line 483 uses it on the value read back from the registry).

*Evidence.* lunatik.h:299 `#define lunatik_toobject(L, i)		(*(lunatik_object_t **)lua_touserdata((L), (i)))` - lua_touserdata returns NULL for a non-userdata and the macro dereferences it, so a non-userdata oopses on a NULL read; a userdata that is not a Lunatik object yields whatever its first word holds. No binding under lib/ uses it (grep -rlw lunatik_toobject lib/ is empty); lunatik.h:451-455 lunatik_getregistryobject is the checked form.

*Fix.* Replace capi.md:438-439 with: "Returns the pointer stored in the userdata at `i` without any check. The value must be a Lunatik object's userdata: a non-userdata dereferences NULL, and any other userdata returns whatever its first word holds. Use `lunatik_checkobject`, or `lunatik_getregistryobject` for a value read from the registry." In the registry pattern (capi.md:482-483) replace the getregistry + toobject pair with `lunatik_object_t *o = lunatik_getregistryobject(L, obj->field);` (it pushes and checks in one call) followed by a NULL check.

#### C-03 · `AGENTS.md:545` · outdated · medium

Object model: "`.pointer = true` means `object->private` is a pointer Lunatik does not own" and "`lunatik_cloneobject`, which requires `.shared = true`" (line 553). Outside the capi.md slice, but it contradicts capi.md and misleads binding authors.

*Evidence.* lunatik.h:76-82 lunatik_class_t has no `pointer` or `shared` field; lunatik.h:28 `LUNATIK_OPT_EXTERNAL` carries the not-owned private (lunatik_obj.c:79-80), and lunatik_obj.c:61-62 cloneobject refuses only `LUNATIK_OPT_SINGLE`.

*Fix.* "`LUNATIK_OPT_EXTERNAL` in the class `opt` means `object->private` is a pointer Lunatik does not own and will not free..." and "...`lunatik_createobject` plus `lunatik_cloneobject`, which refuses a `LUNATIK_OPT_SINGLE` object."

#### C-04 · `doc/capi.md:1` · missing · medium

The object lock API is not documented: lunatik_lock, lunatik_unlock, lunatik_trylock, lunatik_closeprivate (named only in passing), lunatik_getstate and lunatik_gfp.

*Evidence.* lunatik_lock.h:31-67 `static inline void lunatik_lock(lunatik_object_t *object)` / `lunatik_unlock` / `lunatik_trylock` (mutex, spin_lock_irqsave when HARDIRQ or irqs_disabled(), otherwise spin_lock_bh; trylock returns 1 without locking on a non-MONITOR object). lunatik_obj.c:83-95 `void lunatik_closeprivate(lunatik_object_t *object)` EXPORT_SYMBOL. lunatik.h:44 `lunatik_getstate(runtime)`, lunatik.h:142 `lunatik_gfp(runtime)`. Used by lib/luadevice.c, luathread.c, luasocket.c, luarcu.c, luadata.c (lock); luafsnotify.c, luathread.c (getstate); 5 files (gfp).

*Fix.* Add a "Locking" section: lunatik_lock/lunatik_unlock (mutex for a process object, spin_lock_irqsave for HARDIRQ or with IRQs off, spin_lock_bh otherwise; they record the owner; a raise between them skips the unlock), lunatik_closeprivate (takes the lock, detaches the private, runs `release` outside it; how `close`/`stop` end an object), lunatik_getstate and lunatik_gfp. Leave lunatik_trylock out: it has no caller, which is a cleanup for the code rather than an entry for the doc.

#### C-05 · `doc/capi.md:9` · missing · medium

The Types section documents only lunatik_class_t; lunatik_object_t and lunatik_opt_t are absent, although every binding reads `object->private`, `object->opt` and `object->class`.

*Evidence.* lunatik.h:84-97 `typedef struct lunatik_object_s { struct kref kref; const lunatik_class_t *class; void *private; union { struct mutex mutex; spinlock_t spin; }; struct task_struct *owner; lunatik_opt_t opt; gfp_t gfp; unsigned long flags; struct rcu_head rcu; } lunatik_object_t;`; lunatik.h:22 `typedef u8 __bitwise lunatik_opt_t;`

*Fix.* Add a lunatik_object_t entry naming the fields a binding reads (`private`, `class`, `opt`, and `gfp` through `lunatik_gfp`) and those it must not touch (`kref`, the lock union, `owner`, `flags`, `rcu`). Add a lunatik_opt_t entry: a `__bitwise` u8, so a cast into it carries `__force` and flags combine with `|`.

#### C-06 · `doc/capi.md:13` · outdated · medium

lunatik_class_t is shown with four fields (name, methods, release, opt), and cloneobject is said to call `lunatik_require(L, class->name)` so that the metatable is registered even if the script never called require (lines 22-24, 385-386).

*Evidence.* lunatik.h:76-82 `const char *name; const luaL_Reg *methods; lunatik_release_t release; lua_CFunction opener; lunatik_opt_t opt;`; lunatik.h:304-310 `static inline void lunatik_require(lua_State *L, const lunatik_class_t *class) { if (class->opener) { luaL_requiref(L, class->name, class->opener, 0); ...` - without `.opener` nothing is required, and lunatik_setclass then raises "metatable not found" (lunatik.h:254-255). 21 classes set it (e.g. lib/luaskel.c:77-82 `LUNATIK_OPENER(skel); ... .opener = luaopen_skel,`).

*Fix.* Add `lua_CFunction opener;` to the struct block and a bullet: "`opener`: the library's `luaopen_<name>`, declared ahead of the class with `LUNATIK_OPENER(<name>)`. `lunatik_cloneobject` (and so `lunatik_copyobjects`) calls it through `lunatik_require(L, class)` so the metatable exists in a state that never required the library; with `NULL`, cloning into such a state raises `'<name>': metatable not found`." Change capi.md:385 to `lunatik_require(L, class)` and document LUNATIK_OPENER under Module Definition.

#### C-07 · `doc/capi.md:25` · missing · medium

No part of capi.md says that a class's `methods` must carry `{"__gc", lunatik_deleteobject}` (and usually `__close`/`close` = `lunatik_closeobject`), nor documents these two functions.

*Evidence.* lunatik_obj.c:123-133 `int lunatik_deleteobject(lua_State *L) { ... lunatik_putobject(object); *pobject = NULL; ...}` is the only path that drops the reference the userdata holds (lunatik_newobject's kref_init, lunatik.h:274). lunatik.h:325-338 lunatik_newclass adds only `__name` and `__index`, never `__gc`. 29 method tables under lib/ register `"__gc"`; lib/luaskel.c:72-75, the in-tree template, has none (`{"nop", luaskel_nop}, {NULL, NULL}`), so its objects are never released.

*Fix.* Under `methods`, add: "Include `{"__gc", lunatik_deleteobject}`, which drops the reference the userdata holds; without it the object and its private are never released. `{"__close", lunatik_closeobject}` and `{"close", lunatik_closeobject}` release the private early through `lunatik_closeprivate`." Document lunatik_deleteobject, lunatik_closeobject and lunatik_closeprivate under Object Lifecycle and put a `__gc` in the NEWLIB examples' method tables. Adding the `__gc` entry to lib/luaskel.c is a separate code fix.

#### C-08 · `doc/capi.md:26` · inaccurate · medium

`release`: "called when the object's reference counter reaches zero".

*Evidence.* lunatik_obj.c:83-94 lunatik_closeprivate takes the private under the lock, sets `object->private = NULL` and calls `lunatik_releaseprivate(object->class, private)`, which runs `release(private)` (73-81). lunatik_obj.c:104-110 releaseobject runs it at zero only `if (private != NULL)`. So release runs once, at the first of close/stop (lunatik_closeobject, lunatik_lstop, lunatik_stop, percpu stop) or the last put.

*Fix.* "`release`: called once with the private, at `lunatik_closeprivate` (an object's `close`/`stop`, `lunatik_stop`) or, if nothing closed it, when the reference count reaches zero; afterwards Lunatik frees the private unless the class is `LUNATIK_OPT_EXTERNAL`. It runs on the task that closed the object or dropped the last reference. May be `NULL`."

#### C-09 · `doc/capi.md:105` · missing · medium

lunatik_stop names no calling context and no refusal.

*Evidence.* lunatik_core.c:86-90 `lunatik_closeprivate(runtime); return lunatik_putobject(runtime);`; lunatik_obj.c:87 closeprivate does `lunatik_lock(object)` (a mutex for a process runtime, lunatik_lock.h:33-34) and then lua_close through the release. lunatik_core.c:198-205 the Lua `stop` refuses under RTNL and from the runtime's own task (`lunatik_checkrtnl(L); lunatik_checkowner(L, runtime);`), while the C function checks neither. lunatik_percpu.c:99 `/* may run in softirq: a put, never a stop */`.

*Fix.* Add: "Call it from process context and never from the runtime's own task (a handler it dispatched, its script body): the close takes the runtime's lock and would wait on itself, which `lunatik_isowner` detects. Do not call it while holding RTNL if the script may have registered netdevice notifiers. A holder in atomic context drops its reference with `lunatik_putobject` instead."

#### C-10 · `doc/capi.md:139` · missing · medium

lunatik_run: "If the Lua state has been closed, `ret` is set with `-ENXIO`". The other `-ENXIO` cases and the calling-context rule are absent.

*Evidence.* lunatik.h:60-66 `ret = -ENXIO; if (likely(_runtime != NULL)) { ... if (likely(lunatik_isready(_runtime))) lunatik_handle(...)`; lunatik.h:45-46 isready is `private && ready`, false while the script body still runs; lunatik_percpu.h:30-31 the per-CPU slot is NULL until that CPU's runtime is published. lunatik_lock.h:31-39 lunatik_lock takes `mutex_lock` for a process runtime.

*Fix.* "`ret` is `-ENXIO`, and the handler does not run, when the runtime is closed, when its script is still loading (a hook armed from the script body fires before the runtime is ready), and, for a `percpu` object, when this CPU's runtime is not published yet. A process runtime is locked with a mutex, so `lunatik_run` on it must come from a context that may sleep; a softirq or hardirq runtime is run from its matching context."

#### C-11 · `doc/capi.md:208` · missing · medium

lunatik_handle: "Like `lunatik_run`, but without acquiring the runtime lock."

*Evidence.* lunatik.h:48-54 `lua_State *L = lunatik_getstate(runtime); int n = lua_gettop(L); ret = handler(L, ...)` - no `lunatik_pin` (a `percpu` object is not resolved; its private is a lunatik_percpu_t, not a lua_State), no `lunatik_isready` check (a closed runtime gives L == NULL), no owner check. Its one user, lib/luanotifier.c:78-79, takes it only for a replay on the task that already holds the lock.

*Fix.* "Runs `handler(L, ...)` on `runtime`'s state and restores the stack. Unlike `lunatik_run` it does not lock, does not resolve a `percpu` object, and does not check that the state is open or ready: the caller already runs inside the runtime (holding its lock, or in its script body) and passes a plain runtime whose state it knows is open."

#### C-12 · `doc/capi.md:351` · missing · medium

lunatik_newobject lists no raise, no precondition and says nothing about the private's contents.

*Evidence.* lunatik_obj.c:24-34: `lunatik_checkclass(L, class);` (raises "'<name>': process-context class in interrupt-context runtime"), `lunatik_checkmetatable(L, class, monitor);` (raises "'<name>': metatable not found", lunatik.h:254-255, i.e. the library's luaopen must have run in this state), `lunatik_checkalloc` / `lunatik_checkzalloc(L, size)` (raise "not enough memory", lunatik.h:144-154; the private is zeroed and comes from the runtime's allocator, GFP_ATOMIC in an IRQ runtime after load).

*Fix.* Add: "Raises `'<name>': process-context class in interrupt-context runtime`, `'<name>': metatable not found` when the class's library was not opened in this state (call `lunatik_require(L, class)` first when it may not be), and `not enough memory`. The private is zeroed and comes from the runtime's allocator (`GFP_ATOMIC` in an IRQ runtime once loaded); it is freed with `kvfree` after `release`."

#### C-13 · `doc/capi.md:357` · inaccurate · medium

lunatik_newobject: "Pass `LUNATIK_OPT_MONITOR` to wrap method calls with the object lock, enabling safe concurrent access from multiple runtimes." The cloneobject example at line 391 likewise passes LUNATIK_OPT_MONITOR to lunatik_createobject for an arbitrary luafoo_class.

*Evidence.* lunatik.h:397-407 lunatik_newclasses registers the monitored metatable only `if (lunatik_ismonitor(cls->opt))`, i.e. only for a class that declares MONITOR itself. lunatik_obj.c:21-25 computes monitor from `lunatik_inheritopt(class, opt)` and calls lunatik_checkmetatable(L, class, monitor), which raises `'<name>': metatable not found` (lunatik.h:252-256) when the monitored metatable is absent. lunatik_obj.c:68 cloneobject does the same with object->opt. So an instance opt of MONITOR on a class without it raises instead of wrapping; the in-tree caller that passes it (lib/luadata.c:367-368) does so on a class whose opt already carries MONITOR (lib/luadata.c:352).

*Fix.* "Pass `LUNATIK_OPT_MONITOR` only for a class whose `opt` carries it (where it is already inherited); on a class without it, `lunatik_newobject` and `lunatik_cloneobject` raise `'<name>': metatable not found`, since the monitored metatable is registered only for classes that declare the flag." In the cloneobject example, state that `luafoo_class` carries `LUNATIK_OPT_MONITOR`, or pass `LUNATIK_OPT_NONE`.

#### C-14 · `doc/capi.md:427` · missing · medium

Several exported or binding-facing checks and pushers are undocumented: lunatik_checkshareable, lunatik_pushobject, lunatik_setruntime, lunatik_checkcontext, lunatik_checkclass, lunatik_cannotsleep, lunatik_checkbounds, lunatik_checkinteger, lunatik_checkfield, lunatik_optcfunction, lunatik_nop, lunatik_pushstring, lunatik_pushoptinteger, lunatik_pusherrname, lunatik_value_t with lunatik_checkvalue/lunatik_pushvalue, lunatik_env and lunatik_class.

*Evidence.* lunatik.h:371-378 lunatik_checkshareable; 312-316 lunatik_pushobject; 216 `#define lunatik_setruntime(L, libname, priv) ((priv)->runtime = lunatik_checkruntime((L), lua##libname##_class.opt))` (lib/luadevice.c:440, lib/luahid.c:301); 208-214 lunatik_checkcontext; 42 lunatik_cannotsleep (which AGENTS.md:503 tells authors to use); 490-498 lunatik_checkbounds/lunatik_checkinteger (9 files); 181-187 lunatik_checkfield; 482-488 lunatik_optcfunction; 125-130 lunatik_pushstring (writes `s[len] = '\0'` and hands `s` to Lua through lua_pushexternalstring); lunatik_aux.c:77-89 lunatik_pusherrname EXPORT_SYMBOL; lunatik_val.h:9-22 and lunatik_val.c:130-181 (EXPORT_SYMBOL, used by lib/luarcu.c); lunatik_core.c:29-30 and 225 EXPORT_SYMBOL(lunatik_env), EXPORT_SYMBOL(lunatik_class).

*Fix.* Document what bindings call first: checkbounds/checkinteger (9 files), checkfield, optcfunction, setruntime, checkshareable, pushstring (takes a `len + 1` buffer from lunatik_malloc, writes the NUL and hands the buffer to Lua), pushoptinteger, pusherrname, lunatik_value_t with lunatik_checkvalue/lunatik_pushvalue, lunatik_env and lunatik_class (e.g. `lunatik_checkobjectclass(L, ix, &lunatik_class)` as lib/luathread.c:231). Then pushobject (with cloneobject), cannotsleep (which AGENTS.md already names), checkclass and checkcontext.

#### C-15 · `doc/capi.md:508` · inaccurate · medium

lunatik_registerobject "Pins `object` and its `private` pointer in `LUA_REGISTRYINDEX`".

*Evidence.* lunatik.h:512-516 `lunatik_register(L, ix, object->private); /* private */ lunatik_register(L, -1, object);` - it stores the value at `ix` (the options table) under the key `object->private`, and the value on top of the stack, which must be the object's userdata, under the key `object`. Callers use it right after lunatik_newobject: lib/luanetfilter.c:214-220, lib/luafsnotify.c:709-710, lib/luaprobe.c:378-383.

*Fix.* "Stores the value at `ix` (typically the options table holding the callback) under the key `object->private`, where a handler reads it with `lunatik_getregistry(L, private)`, and the userdata on top of the stack, which must be `object`'s, under the key `object`, keeping it from collection until `lunatik_unregisterobject`. Call it with the object's userdata on top, as right after `lunatik_newobject`." Reword capi.md:515 likewise: "Clears the registry entries keyed by `object->private` and by `object`, so the userdata may be collected."

#### C-16 · `doc/capi.md:682` · missing · medium

Module Definition shows no complete binding. There is no class definition with `.opener`/`__gc`, no LUNATIK_OPENER, no module_init/exit, and no pointer to the in-tree template.

*Evidence.* lunatik.h:409 `#define LUNATIK_OPENER(libname) int luaopen_##libname(lua_State *L)` (used by 20 files); lib/luaskel.c:6-11 "Template for a kernel module exposing a Lua library: copy it to `lib/lua<name>.c`" wires checker, methods, release and opener (77-95), and is never referenced from capi.md.

*Fix.* Add a "Writing a binding" example: private struct, LUNATIK_PRIVATECHECKER, method table with `__gc`/`__close`, `LUNATIK_OPENER(foo)` before the class, the class with `.opener`, a `luafoo_new` calling lunatik_newobject, LUNATIK_CLASSES + LUNATIK_NEWLIB, module_init/exit and MODULE_LICENSE; link lib/luaskel.c as the file to copy once it carries `__gc`.

#### C-17 · `doc/capi.md:741` · missing · medium

The Memory section documents only malloc/realloc/free: it has no raising allocators and does not say which gfp the allocator uses.

*Evidence.* lunatik.h:144-154 `#define lunatik_enomem(L) luaL_error((L), "not enough memory")`, `lunatik_checknull`, `#define lunatik_checkalloc(L, s)`, `#define lunatik_checkzalloc(L, s)` (used in 3-8 files under lib/). lunatik_core.c:55-62 the allocator uses `lunatik_gfp(runtime)` with `__GFP_NOWARN`, GFP_ATOMIC in an IRQ runtime after load (302-303) and kvmalloc above a page under GFP_KERNEL.

*Fix.* Add lunatik_checkalloc / lunatik_checkzalloc / lunatik_checknull / lunatik_enomem (raise `not enough memory` instead of returning NULL), and on lunatik_malloc: "allocates with the runtime's gfp (`GFP_ATOMIC` in a softirq or hardirq runtime once loaded, `GFP_KERNEL` otherwise, possibly vmalloc'ed), without an allocation warning; free with `lunatik_free`, never `kfree`".

#### C-18 · `doc/capi.md:1` · missing · low

The eBPF binding helpers in lunatik_ebpf.h are not documented anywhere in capi.md.

*Evidence.* lunatik_ebpf.h:14-148 defines lunatik_ebpf_getruntimes, lunatik_ebpf_lookupruntime, lunatik_ebpf_findctx/getctx, lunatik_ebpf_invoke, lunatik_ebpf_attach/detach, lunatik_ebpf_bind/unbind, LUNATIK_EBPF_RUN, LUNATIK_EBPF_START/END, LUNATIK_EBPF_BTF_SET_START/END, LUNATIK_EBPF_KFUNC_DEFINE_SET, LUNATIK_EBPF_NEWLIB, LUNATIK_EBPF_KFUNC_INIT, LUNATIK_EBPF_EXIT; included by lib/luatc.c, lib/luaxdp.c, lib/luasched.c.

*Fix.* Add an "eBPF bindings" section: runtime lookup by key in `_ENV.runtimes` (lunatik_ebpf_lookupruntime, IRQ runtimes only), context registration (lunatik_ebpf_attach/detach, bind/unbind, findctx/getctx, noting findctx leaves the userdata pushed when it finds one), dispatch (LUNATIK_EBPF_RUN), the BTF kfunc set and init/exit macros, pointing at lib/luaxdp.c and noting `make btf_install` before building.

#### C-19 · `doc/capi.md:29` · missing · low

The opt flag list omits LUNATIK_OPT_IRQ, LUNATIK_OPT_PERCPU and LUNATIK_OPT_NONE, and the MONITOR bullet says only "A metamethod, and a method named `close`, are left unwrapped".

*Evidence.* lunatik.h:23-30 defines LUNATIK_OPT_IRQ (the bit SOFTIRQ and HARDIRQ share, tested by lunatik_isirq) and LUNATIK_OPT_PERCPU (lunatik_percpu.c:194). lunatik_obj.c:14-17 `lunatik_ismetamethod(reg)` also skips `(reg)->func == lunatik_lstop`, so the runtime's `stop` is unwrapped too.

*Fix.* Add: "`LUNATIK_OPT_IRQ`: the bit both IRQ flags carry, tested with `lunatik_isirq(opt)`; not set alone. `LUNATIK_OPT_PERCPU`: marks the `percpu` class, internal. `LUNATIK_OPT_NONE`: 0." Change the MONITOR sentence to "A metamethod, a method named `close`, and a method bound to `lunatik_lstop` (`stop`) are left unwrapped".

#### C-20 · `doc/capi.md:63` · broken-link · low

Four links point to https://www.kernel.org/doc/Documentation/kref.txt (lines 63, 112, 403, 419).

*Evidence.* The kernel tree has no Documentation/kref.txt: `ls linux v6.8: Documentation/kref.txt` -> No such file; the page is Documentation/core-api/kref.rst. The www.kernel.org/doc/Documentation/ tree serves current files, so the .txt path does not resolve (not fetched; inferred from the tree).

*Fix.* Replace all four with https://docs.kernel.org/core-api/kref.html.

#### C-21 · `doc/capi.md:77` · missing · low

lunatik_runtime "opens the Lua standard libraries present on Lunatik" and runs the script, with no word on what differs in an IRQ runtime, where errors go, or what stays on the stack.

*Evidence.* lunatik_core.c:241-248: a process runtime gets `luaL_openlibs` and the full `lunatik` library; an IRQ runtime gets `luaL_openselectedlibs(L, ~LUA_IOLIBK, 0)` (no `io`) and `luaopen_lunatik_stub` (only `cpu`, 184-187). lunatik_core.c:72-78 with no calling state the load error goes to `pr_err`. lunatik_core.c:259-261 the script's single return value stays on the state's stack (the thread body).

*Fix.* Add: "A softirq or hardirq runtime opens every standard library but `io`, and its `lunatik` library carries only `cpu`. On failure the error is logged with `pr_err`. The script's first return value stays on the state's stack, below what a handler pushes."

#### C-22 · `doc/capi.md:78` · broken-link · low

"[present on Lunatik](https://github.com/luainkernel/lunatik#c-api)".

*Evidence.* README.md headings are only `# Lunatik`, `## Get started`, `## Documentation`, `## License` (grep -n '^#' README.md), so the `#c-api` anchor does not exist. The list of supported libraries is in doc/guide/04-lua.md:16-25.

*Fix.* Link `[present on Lunatik](guide/04-lua.md)`, which resolves on GitHub and, through the same rewrite, to 04-lua.md.html on the site; confirm the rendered href after `make doc-site`.

#### C-23 · `doc/capi.md:122` · missing · low

lunatik_copyobjects names only `invalid object` and `cannot share SINGLE object` as failures.

*Evidence.* lunatik_core.c:109 `lunatik_pushobject(L, *pobject);` -> lunatik_obj.c:61-68: the SINGLE message is prefixed with the class name (`"'%s': %s", class->name, LUNATIK_ERR_SINGLE`), `lunatik_checkclass` raises "process-context class in interrupt-context runtime" when Lto is an IRQ runtime, and setclass may raise "metatable not found" for a class without opener; lunatik_core.c:104 `luaL_checkstack(L, nobjects, "too many objects")`.

*Fix.* "...fails it with `invalid object`; a SINGLE object with `'<class>': cannot share SINGLE object`; a process-context object copied into an IRQ runtime with `'<class>': process-context class in interrupt-context runtime`; a class whose library cannot be opened in `Lto` with `'<class>': metatable not found`; more objects than the stack takes with `too many objects`."

#### C-24 · `doc/capi.md:236` · unclear · low

lunatik_isready: "for example, spawning a kernel thread from a `runner.spawn` callback".

*Evidence.* lib/luathread.c:230 `luaL_argcheck(L, lunatik_isready(lunatik_toruntime(L)), 1, "not allowed during module load");` - the guard refuses `thread.run` from the calling runtime's own script body; runner.spawn is not involved. lunatik.h:45-46 also returns false once the runtime is closed (`(runtime)->private && ...`).

*Fix.* "Returns `true` once the runtime's script body has returned and until the runtime is closed. `thread.run` uses it to refuse creating a thread from the script body of the runtime that calls it."

#### C-25 · `doc/capi.md:274` · unclear · low

lunatik_checkruntime "raises a Lua error" and is "Typically called from `lunatik_new*` functions".

*Evidence.* lunatik.h:200-206 raises `luaL_error(L, LUNATIK_ERR_RUNTIME)`, i.e. "runtime context mismatch"; its callers are the bindings' constructors (lib/luanetfilter.c:211, lib/luaprobe.c:375, lib/luafsnotify.c:703, lib/luanotifier.c:270), not core `lunatik_new*` functions, and lunatik.h:216 `lunatik_setruntime` wraps it for a `priv->runtime` field.

*Fix.* "Raises `runtime context mismatch`. A binding's constructor calls it, directly or through `lunatik_setruntime(L, libname, priv)`, which stores the result in `priv->runtime` and reads the class as `lua<libname>_class`."

#### C-26 · `doc/capi.md:315` · missing · low

Of the percpu helpers only lunatik_percpudata, LUNATIK_PERCPUDATA and a passing mention of lunatik_getpercpu/lunatik_pin are documented.

*Evidence.* lunatik_percpu.h:11-14 `#define LUNATIK_CPU_NONE (-1)`, `lunatik_getcpu(L)`, `lunatik_hascpu(L)`, `lunatik_getpercpu(L)`; 23-44 `lunatik_pin` / `lunatik_unpin` (preempt_disable in IRQ, migrate_disable in process, NULL until published); 71-77 `static inline void lunatik_checkpercpu(lua_State *L)` raising "not allowed in a percpu runtime", used by 5 files under lib/. lunatik_percpu.h:48 `extern const lunatik_class_t lunatik_percpu_class;`.

*Fix.* Document lunatik_checkpercpu (raises `not allowed in a percpu runtime`) and lunatik_getcpu/lunatik_hascpu/LUNATIK_CPU_NONE beside lunatik_percpudata, and give lunatik_getpercpu an entry of its own. Mention lunatik_pin/lunatik_unpin only as what lunatik_run uses to resolve a percpu object (preemption off in IRQ, migration off in process, NULL until published); they and lunatik_percpu_class need no binding-facing entry.

#### C-27 · `doc/capi.md:331` · broken-link · low

The `### LUNATIK\_PERCPUDATA` heading gets the same anchor as `### lunatik\_percpudata`, so no link can reach it; the two `#### Example` headings also collide.

*Evidence.* doc/topics/capi.md.html ids: `id="lunatik_percpudata" id="lunatik_percpudata"` and `id="example" ... id="example"` (grep -o 'id="[^"]*"').

*Fix.* Rename the heading, e.g. `### LUNATIK\_PERCPUDATA (macro)`, or fold it into the lunatik_percpudata entry; give each example a distinct heading (`#### Example: lunatik_runtime`, `#### Example: lunatik_run`).

#### C-28 · `doc/capi.md:377` · inaccurate · low

lunatik_createobject: "Sleep mode is determined by `LUNATIK_OPT_SOFTIRQ` in `object->opt`."

*Evidence.* lunatik_obj.c:41 `gfp_t gfp = lunatik_isirq(opt | class->opt) ? GFP_ATOMIC : GFP_KERNEL;`; lunatik.h:23-25 LUNATIK_OPT_IRQ is the bit both SOFTIRQ and HARDIRQ carry. lunatik_obj.c:48 always `kzalloc(size, gfp)` for the private, even for an EXTERNAL class, whose private releaseprivate never frees (79-80).

*Fix.* "Allocates with `GFP_ATOMIC` when `opt | class->opt` carries an IRQ flag (`LUNATIK_OPT_SOFTIRQ` or `LUNATIK_OPT_HARDIRQ`), otherwise `GFP_KERNEL`, so a process-context object is created only where the caller may sleep. The private is `size` zeroed bytes; the call is not for a `LUNATIK_OPT_EXTERNAL` class, whose private it would allocate and never free."

#### C-29 · `doc/capi.md:477` · unclear · low

The registry pattern block is pseudo code with `//` comments, `lunatik_attach(L, obj, field, luafoo_new)` without its trailing arguments, and `lunatik_toobject` for the read-back.

*Evidence.* lunatik.h:544-549 lunatik_attach passes varargs to new_fn (lib/luadata.h:27 `lunatik_attach(L, obj, field, luadata_new, opt)`); lunatik.h:451-455 lunatik_getregistryobject is the checked read the same page recommends at line 528-531; lib/luanetfilter.c and lib/luahid.c use getregistryobject, and no binding uses toobject.

*Fix.* Rewrite as C with `/* */` comments: `lunatik_attach(L, obj, field, luafoo_new, opt);`, then `lunatik_object_t *o = lunatik_getregistryobject(L, obj->field);` with a NULL check and `lua_pop(L, 1)`, then `lunatik_detach(runtime, obj, field);`.

#### C-30 · `doc/capi.md:582` · unclear · low

lunatik_throw "Pushes the POSIX error name for `-ret`".

*Evidence.* lunatik_aux.c:77-88 lunatik_pusherrname takes `err = abs(err)`, pushes errname() on 6.7+ or the `%pe` form below it, and pushes "unknown" when the errno has no name.

*Fix.* "Pushes the name of the errno `ret` through `lunatik_pusherrname` (either sign; the tree passes it negative, e.g. `-EINVAL` -> `\"EINVAL\"`, and `\"unknown\"` when it has no name) and raises it with `lua_error`."

#### C-31 · `doc/capi.md:601` · unclear · low

lunatik_errmsg: "...and `\"error object is not a string\"` otherwise, without converting it: ...; any other value reads as `NULL`."

*Evidence.* lunatik.h:176-179 `return lua_type(L, -1) == LUA_TSTRING ? lua_tostring(L, -1) : "error object is not a string";` - it never returns NULL. The closing clause describes lua_tostring, but it reads as a second return value of lunatik_errmsg.

*Fix.* "Returns the error on top of `L`'s stack when it is a string, and `\"error object is not a string\"` for any other value, never `NULL`. It does not call `lua_tostring` on a number, which converts in place and could allocate outside a protected call."

#### C-32 · `doc/capi.md:624` · inaccurate · low

lunatik_optinteger "Falls back to `opt` if the field is absent or nil."

*Evidence.* lunatik.h:477-478 `lua_getfield(L, idx, #field); priv->field = lua_isnil(L, -1) ? opt : lua_tointeger(L, -1);` - a present value that is not a number (a string such as "abc", a table) silently stores 0; nothing is bounded against the field's type.

*Fix.* "Falls back to `opt` when the field is nil or absent. Any other value goes through `lua_tointeger`: a numeric string is converted, anything else not a number stores 0 without an error, and the value is not bounded, so bound it with `lunatik_checkbounds` when the field is narrower than `lua_Integer`."

### Core and utility modules

#### MC-01 · `lib/luacpu.c:54` · inaccurate · high

cpu.stats documents '@raise if CPU is offline', implying any invalid CPU id raises; an id past the cpumask is never bounded and is read out of bounds.

*Evidence.* lib/luacpu.c:59 `unsigned int cpu = luaL_checkinteger(L, 1);` then :62 `luaL_argcheck(L, cpu_online(cpu), 1, "CPU is offline");`. cpu_online -> cpumask_test_cpu -> test_bit(cpumask_check(cpu), ...) (include/linux/cpumask.h:148-152, :502-505), and cpumask_check only WARNs under CONFIG_DEBUG_PER_CPU_MAPS. cpu.stats(-1) tests bit 0xFFFFFFFF, about 512 MB past __cpu_online_mask. A smaller id past nr_cpu_ids reads adjacent memory, and if that bit reads set, kcpustat_cpu_fetch indexes per-CPU data out of range. This is a crash reachable from one line of script, a code defect behind the doc line.

*Fix.* Code: bound the id first, `unsigned int cpu = (unsigned int)lunatik_checkinteger(L, 1, 0, nr_cpu_ids - 1);`, then the online check. Doc: '@raise "out of bounds" for an id outside 0..linux.numcpus()-1, "CPU is offline" for an offline one.' File it as a severity: high issue and a fix of its own.

#### MC-02 · `lib/lualinux.c:81` · missing · high

linux.schedule is documented as 'Puts the current task to sleep' with no execution-context restriction, so nothing tells a reader it must not be called from a softirq or hardirq runtime (a netfilter/XDP/kprobe callback).

*Evidence.* lib/lualinux.c:104-106 `__set_current_state(state);` / `lua_pushinteger(L, jiffies_to_msecs(schedule_timeout(timeout)));` with no lunatik_checkruntime/lunatik_cannotsleep guard anywhere in lualinux_schedule (lines 94-108); linux is not a class, so no checkclass refusal applies either.

*Fix.* Doc: 'Sleeps. Call it only from a process-context runtime, or from the top-level body of a softirq/hardirq script, which runs in process context before the runtime is armed. Never call it from a hook callback.' Code: the guard should key on the armed state, not on the runtime type alone. `lunatik_checkruntime(L, LUNATIK_OPT_NONE)` would also refuse a softirq script's body, which is sleepable (guide 02:48). Use a lunatik_cannotsleep(L, lunatik_isready(...)) check like lunatik_checkarmed (lunatik.h:225-228) and document the message it raises in @raise.

#### MC-03 · `autogen/ldoc.lua:278` · inaccurate · medium

Each linux.* constant page (linux.eth, linux.task, linux.stat, linux.signal, ...) documents a table named `constants`, e.g. `linux.eth.constants`, that does not exist. No page lists a constant name or states the prefix-stripping rule, so a reader cannot tell that ETH_P_IP is `require("linux.eth").IP`.

*Evidence.* autogen/ldoc.lua:278 `local name = s.module == top and "constants" or s.module:sub(#top + 2)` and :281 `f:write(("%s.%s = {}\n"):format(top, name))`; the real output, autogen.lua:398 `if mod.name ~= top then out:write(mod.name, " = {}\n") end` and :401 `out:write(mod.name, '["', e.key, '"]\t= ', ...)`, writes top-level constants straight onto the module table. specs.lua:5-7 states the rule ('keyed by the constant name with `prefix` stripped'), but it never reaches the pages. The rendered doc/modules/linux.eth.html shows 'Tables: constants'.

*Fix.* In autogen/ldoc.lua, for a spec whose module equals top, put its description on the module block and emit no `constants` table. Add to every stub: 'Keys are the kernel names with the prefix stripped: ETH_P_IP is linux.eth.IP', and a generated @usage (`local eth = require("linux.eth")`) with one example key.

#### MC-04 · `lib/lighten.lua:6` · missing · medium

lighten.run(ct, iv) is documented as running an encrypted script from ciphertext and IV only; the doc never says where the key comes from, that a `light` module must be installed, or how to produce the ciphertext.

*Evidence.* lib/lighten.lua:11 `local light = require("light")` and :22 `return darken.run(hex2bin(ct), hex2bin(iv), hex2bin(light))`; the key file is produced by tools/shade.sh:9 `shade.sh lighten [-t] <secret>  generate light.lua from a secret` and :71 `cat > light.lua`; nothing under doc/ or README mentions shade.sh or light.lua. Without it, require("lighten") fails with module 'light' not found.

*Fix.* Module doc: 'The key is read from the module `light` (/lib/modules/lua/light.lua, returning the hex-encoded 32-byte key). Generate it with `tools/shade.sh lighten <secret>` (64 hex chars) and encrypt a script with `tools/shade.sh darken [-s secret] <script.lua>`, which writes `<script>.dark.lua` calling `lighten.run` and prints the secret. With -t both sides derive the key from the current 30 s time step, so light.lua and the dark script must be generated in the same step.' Add a @usage with the two commands and `lunatik run script.dark`.

#### MC-05 · `lib/luacpu.c:48` · missing · medium

cpu.stats lists the fields but not their unit. num_possible, num_present and num_online have no summary line, so they render blank on the page.

*Evidence.* lib/luacpu.c:44 `lua_pushinteger(L, (lua_Integer)kcs.cpustat[CPUTIME_##NAME]);`: raw kernel_cpustat values in nanoseconds (kernel fs/proc/stat.c:127 converts the same values with `nsec_to_clock_t(user)`). luacpu.c:24-27 `/*** @function num_possible @treturn ... */` has no description line.

*Fix.* stats: '@treturn table cumulative time per state in nanoseconds since boot: user, nice, ...; idle and iowait come from kcpustat and may lag /proc/stat on a tickless CPU.' Give each num_* block a first line, and explain possible/present/online once in the module doc, relating num_possible to linux.numcpus().

#### MC-06 · `lib/luacrypto_core.c:6` · missing · medium

The crypto module page is one line with no functions. The real entry points `crypto.shash`, `crypto.skcipher`, `crypto.aead`, `crypto.rng` and `crypto.comp` appear nowhere; each class page documents a non-existent `crypto_shash:new(algname)` (and so on) instead.

*Evidence.* lib/luacrypto_core.c:15-22 `{"shash", luacrypto_shash_new}, {"skcipher", ...}, {"aead", ...}, {"rng", ...}, #if < 6.15 {"comp", ...}`; lib/luacrypto_shash.c:213 `@function new` (the same in aead.c:222, skcipher.c:170, rng.c:130, comp.c `@function new`); doc/modules/crypto.html has no entries and doc/classes/crypto_shash.html lists 'crypto_shash:new (algname)'.

*Fix.* Document the constructors in luacrypto_core.c as `@function shash` ... `@function comp`, each with `@tparam string algname`, `@treturn crypto_shash` (etc.) and a link to the class page. Note that `comp` is absent on 6.15 and later. Drop or retag the class-page `new` blocks so no `crypto_x:new` method is shown.

#### MC-07 · `lib/luacrypto_core.c:6` · missing · medium

No crypto doc says that every crypto object can only be created in a process-context runtime. crypto.hkdf and lighten/darken inherit this restriction.

*Evidence.* Class opts carry no IRQ bit: lib/luacrypto_shash.c:208 `.opt = LUNATIK_OPT_MONITOR | LUNATIK_OPT_EXTERNAL`, luacrypto_aead.c:217 `.opt = LUNATIK_OPT_MONITOR`, luacrypto_skcipher.c:165 `.opt = LUNATIK_OPT_MONITOR`, luacrypto_rng.c:125 `.opt = LUNATIK_OPT_MONITOR | LUNATIK_OPT_EXTERNAL`; lunatik_obj.c:24 `lunatik_checkclass(L, class);` -> lunatik.h:221-222 raises "'crypto_shash': process-context class in interrupt-context runtime".

*Fix.* Crypto module doc: 'Crypto objects are created only in a process runtime: in a softirq or hardirq runtime the constructors raise "'<class>': process-context class in interrupt-context runtime".' Add the same line to crypto.hkdf.

#### MC-08 · `lib/luacrypto_rng.c:25` · inaccurate · medium

crypto_rng:generate 'Generates random bytes, optionally reseeding first', with `seed` described as seed data. getbytes is described as 'without reseeding'.

*Evidence.* lib/luacrypto_rng.c:43 `crypto_rng_generate(tfm, seed_data, (unsigned int)seed_len, (u8 *)buffer, num_bytes)`; kernel include/crypto/rng.h:170 `@src: Input buffer holding additional data, may be NULL`. Reseeding is crypto_rng_reset (rng.h:215), which `reset` calls.

*Fix.* generate: 'Generates n random bytes, passing the optional string to the algorithm as additional input for this call (e.g. drbg's additional input); it does not reseed, use reset for that.' Rename the parameter to `additional`. getbytes: 'Generates n random bytes with no additional input.'

#### MC-09 · `lib/luacrypto_shash.c:181` · missing · medium

The public method `algname()` is registered on shash, skcipher, aead and rng objects but documented on none of them.

*Evidence.* lib/luacrypto_shash.c:189 `{"algname", luacrypto_shash_algname},` (no doc block above the function at :181); likewise luacrypto_skcipher.c:150, luacrypto_aead.c:201, luacrypto_rng.c:111.

*Fix.* Above each *_algname: `/*** Returns the driver-independent algorithm name the transform was allocated with. @function algname @treturn string */`.

#### MC-10 · `lib/luadarken.c:97` · missing · medium

darken.run does not say that the plaintext must be Lua source (binary chunks are refused) or that it may only be called from a process-context runtime.

*Evidence.* lib/luadarken.c:120 `luaL_loadbufferx(L, buf, ct_len, "=darken", "t");` (text mode only); :45 `crypto_alloc_skcipher(LUADARKEN_ALG, 0, 0)` allocates and may sleep, and luadarken_run has no lunatik_checkruntime (darken is a plain library, so no class check applies).

*Fix.* 'The decrypted script must be Lua source; a precompiled chunk raises "attempt to load a binary chunk". It runs with the runtime's global environment. Allocates a crypto transform, so call it from a process runtime only.' Quote "IV must be 16 bytes" / "key must be 32 bytes" in @raise. The sleep reachable from a softirq/hardirq callback also warrants a lunatik_cannotsleep guard in the code.

#### MC-11 · `lib/luadata.c:76` · missing · medium

The data class doc and its integer accessors do not say that multi-byte values are read and written in host byte order. data is the packet view (skb:data(), XDP), where fields are big-endian.

*Evidence.* lib/luadata.c:48 `T##_t value = *(T##_t *)luadata_checkbounds(L, 2, data, offset, sizeof(T##_t));` and :60 `*ptr = (T##_t)luaL_checkinteger(L, 3);`: native loads and stores, no byte swapping.

*Fix.* In @type data: 'Integer accessors use host byte order and 0-based offsets; convert network fields with byteorder, e.g. byteorder.ntoh16(pkt:getuint16(12)).' Give each accessor a one-line summary and mark getnumber/setnumber as aliases of getint64/setint64.

#### MC-12 · `lib/luadata.c:76` · missing · medium

The data class doc says data objects are also returned 'by the modules that expose kernel memory (as skb:data())' but not that such an object is only valid during the callback that received it.

*Evidence.* lib/luaxdp.c:119-120 `luadata_clear(lctx->packet); luadata_clear(lctx->argument);` after the callback; lib/luahid.c:232 and :261 `luadata_clear(data);`; luadata.h:16 `#define luadata_clear(o) (luadata_reset((o), NULL, 0, LUADATA_OPT_KEEP))`. After the clear, size is 0, so every accessor raises "out of bounds" (luadata.c:36-37).

*Fix.* 'A data object handed to a callback, or returned by skb:data(), views kernel memory only while that callback runs; afterwards its length is 0 and every access raises "out of bounds". Copy what you need with getstring.' Also document "read only" (luadata.c:41) for views the kernel marks read-only.

#### MC-13 · `lib/luafifo.c:26` · inaccurate · medium

push and pop render as module-level functions `pop (size)` and `push (data)`, as if called as `fifo.push(data)`, and not as methods of a fifo object.

*Evidence.* lib/luafifo.c:26 and :49 `@function push/pop` come before the `@type fifo` block at :88; they are registered in luafifo_mt (115-122: `{"push", luafifo_push}, {"pop", luafifo_pop}`). doc/modules/fifo.html lists them under 'Functions' and only `close` under Class fifo.

*Fix.* Move the `@type fifo` block above the push block, keeping new under `@within fifo`, so push/pop render as fifo:push / fifo:pop.

#### MC-14 · `lib/lualinux.c:6` · outdated · medium

The linux module doc says it gives 'access to kernel constants like file modes, task states, and error numbers'.

*Evidence.* lib/lualinux.c:302-315 lualinux_lib has only functions (random ... numcpus), no constant tables. Commit a12c0eac3 'lualinux: migrate task and stat constants to autogen' moved them to `linux.stat` and `linux.task`, and there is no errno table (only errname).

*Fix.* 'Kernel facilities: random numbers, sleeping, tracing, time, symbol lookup, network interface and namespace ids, errno names and CPU count. Kernel constants live in the linux.* modules, e.g. require("linux.stat") for file modes and require("linux.task") for task states.'

#### MC-15 · `lib/lualinux.c:166` · missing · medium

linux.lookup says it uses kallsyms_lookup_name 'potentially via kprobes' but not that it always returns nil on a kernel without CONFIG_KPROBES.

*Evidence.* lunatik_aux.c:100-108 `#ifdef CONFIG_KPROBES struct kprobe kp = {.symbol_name = "kallsyms_lookup_name"}; ...` is the only place __lunatik_lookup is set; :113 `return __lunatik_lookup == NULL ? NULL : ...`.

*Fix.* 'In a module build (the usual one) the lookup function is resolved through a kprobe when lunatik loads: without CONFIG_KPROBES, or if that kprobe fails to register, every lookup returns nil.'

#### MC-16 · `lib/luasignal.c:15` · missing · medium

The signal module doc is just 'POSIX Signals'. It does not say that sigmask, sigpending and sigstate act on the calling task (`current`) and are meaningful only in process context, nor which pid namespace kill resolves in.

*Evidence.* lib/luasignal.c:39 `lunatik_try(L, sigprocmask, cmd, &newmask, NULL);`, :51 `signal_pending(current)`, :88 `sigismember(&current->blocked, signum)`, with no context guard. kernel/signal.c:3109 `/* Lockless, only current can change ->blocked, never from irq */` and __set_current_blocked takes `spin_lock_irq(&tsk->sighand->siglock)` (kernel/signal.c:3091). In a softirq/hardirq callback, current is the interrupted task.

*Fix.* Module doc: 'Signal state of the calling task, and kill. Use from a process runtime (typically a kernel thread body, which thread:stop interrupts); in a softirq/hardirq callback the calling task is whatever was interrupted, and sigmask must not be called there. kill resolves pid in the calling task's pid namespace.' Add a @usage.

#### MC-17 · `lib/luasignal.c:56` · inaccurate · medium

sigstate(sig, "pending") is documented as checking whether the signal is pending for the current task, and the usage uses `signal.sigstate` without requiring `signal`.

*Evidence.* lib/luasignal.c:91 `result = sigismember(&current->pending.signal, signum);` reads only the thread-private set; process-directed signals (kill, including this module's kill_pid) are queued on `signal->shared_pending` (kernel/signal.c:1088 `pending = (type != PIDTYPE_PID) ? &t->signal->shared_pending : &t->pending;`), so they read as not pending. luasignal.c:64-66 usage: `local sig = require("linux.signal")` then `signal.sigstate(15)`.

*Fix.* Doc: '"pending": the signal is in the thread's private pending set; signals sent to the process (kill) sit in the shared set and are not reported, so use sigpending() for those.' Alternatively the code also tests current->signal->shared_pending. Fix the usage: `local signal = require("signal"); local sig = require("linux.signal"); signal.sigstate(sig.TERM, "pending")`.

#### MC-18 · `lib/luasignal.c:101` · inaccurate · medium

signal.kill says 'sig 0 sends nothing and checks the process and the permission' and '@raise ... the operation is not permitted'. sigmask also lists 'the operation is not permitted'.

*Evidence.* lib/luasignal.c:122 `int ret = kill_pid(pid, sig, 1);`: priv=1 sends SEND_SIG_PRIV, and kernel/signal.c:840-841 `if (!si_fromuser(info)) return 0;` skips the permission check, so any existing pid succeeds. sigprocmask (luasignal.c:39) only fails with -EINVAL (kernel/signal.c sigprocmask `default: return -EINVAL;`), and it can block SIGKILL (kernel/signal.c comment above sigprocmask).

*Fix.* kill: 'Sends as the kernel: no permission check applies, so sig 0 only checks that the pid exists. @raise "ESRCH" if no task has that pid; an out-of-bounds pid or sig.' sigmask: drop 'not permitted' and note that it can block SIGKILL and SIGSTOP.

#### MC-19 · `lib/luatask.c:101` · inaccurate · medium

The generated page shows the constructor as a method, `task:current()`, when it is the module function `task.current()`.

*Evidence.* lib/luatask.c:120-121 `static const luaL_Reg luatask_lib[] = { {"current", luatask_current}, ...` while the doc block at :99-107 follows `@type task` (line ~28) without `@within task`; doc/modules/task.html lists 'task:current ()' under Class task.

*Fix.* Add `@within task` to the current block, or move it above `@type task`.

#### MC-20 · `lib/luathread.c:216` · inaccurate · medium

The generated page lists the module functions as methods: `thread:run(runtime, name, ...)`, `thread:current()`, `thread:shouldstop()`, and `thread:stop(self)`/`thread:task(self)` with a redundant self parameter.

*Evidence.* lib/luathread.c:19-21 `@type thread` comes before every doc block, and none of run (216), current (265) or shouldstop (63) carries `@within`, while they are registered in luathread_lib (152-157: `{"run", ...}, {"shouldstop", ...}, {"current", ...}`), not in luathread_mt. doc/modules/thread.html renders 'thread:run (runtime, name, ...)'.

*Fix.* Tag run, shouldstop and current `@within thread` (as completion.new and fifo.new do), or move the `@type thread` block below them. Drop `@tparam thread self` from stop and task. Add a module @usage with a spawn script body.

#### MC-21 · `lib/lunatik/runner.lua:49` · inaccurate · medium

runner.run: 'Runs a Lunatik script in the current context'; context documented as only `"process"` (default) or `"softirq"`; @treturn is `table`.

*Evidence.* lib/lunatik/runner.lua:64 `local runtime = ispercpu and lunatik.percpu(script, context) or lunatik.runtime(script, context)`; lunatik.h:210 `static const char *const contexts[] = {"process", "softirq", "hardirq", NULL};` so hardirq is accepted (the CLI's `lunatik run <script> hardirq` goes through here), and the result is a runtime/percpu userdata, not a table.

*Fix.* 'Runs a script in a new runtime of the given context and registers it under its name. @tparam[opt="process"] string context "process", "softirq" (netfilter, XDP) or "hardirq" (kprobes), as in lunatik.runtime. @treturn runtime|percpu. @raise "<script> is already running", an invalid context, or the script's load error.'

#### MC-22 · `lib/lunatik_core.c:6` · missing · medium

The lunatik module doc lists runtime, percpu, cpu and _ENV without saying that a softirq or hardirq runtime gets a reduced module: only `cpu` and `_ENV`, and no `io` library.

*Evidence.* lunatik_core.c:184-187 `static const luaL_Reg lunatik_stub_lib[] = { {"cpu", lunatik_cpu}, {NULL, NULL} };` and :241-248 `if (!(lunatik_isirq(...))) { luaL_openlibs(L); luaL_requiref(L, "lunatik", luaopen_lunatik, 0); } else { luaL_openselectedlibs(L, ~LUA_IOLIBK, 0); luaL_requiref(L, "lunatik", luaopen_lunatik_stub, 0); }`. The guide (doc/guide/02-running-scripts.md) does not say it either.

*Fix.* Module doc: 'In a softirq or hardirq runtime the lunatik module has only `cpu` and `_ENV`: `runtime` and `percpu` exist only in a process runtime, and the `io` library is not opened.' Add the same line to `runtime` and `percpu`, and one sentence to guide 04's io paragraph.

#### MC-23 · `lib/lunatik_core.c:134` · inaccurate · medium

runtime:resume says the objects are 'delivered to the script as return values of coroutine.yield()'; the doc never says the script must return a function, and that the first resume calls it with the objects as arguments.

*Evidence.* lunatik_core.c:259-261 `lua_call(L, 0, 1); lua_remove(L, scriptix); return 1; /* callback */` keeps the script's return value on the main state; :131 `lua_resume(Lto, Lfrom, nargs, &nresults)` then starts that function. tests/runtime/resume_results_recv.lua: `local function recv(first, second) ... coroutine.yield(...) ... end return recv`.

*Fix.* 'The script must return a function. The first resume calls it with the given objects as arguments; later resumes deliver them as the return values of the coroutine.yield() it is suspended in. Returns what the function yields, or what it returns when it ends.' Add a two-script @usage and add "null pointer dereference" (stopped runtime) to @raise. Apply the same to percpu:resume.

#### MC-24 · `lib/mailbox.lua:6` · missing · medium

The module says mailboxes connect runtimes but not how: that the fifo and completion must be created once and passed to the other runtime (e.g. through runtime:resume), or that receive needs a process-context runtime while send also works from softirq.

*Evidence.* lib/mailbox.lua:47-48 `if type(q) == 'userdata' then mbox.queue, mbox.event = q, e` (the sharing path); lib/luacompletion.c:86 `lunatik_checkruntime(L, LUNATIK_OPT_NONE);` in wait raises "runtime context mismatch" in a softirq/hardirq runtime, while fifo and completion classes are LUNATIK_OPT_SOFTIRQ (luafifo.c:130, luacompletion.c:127). Passing a fifo as q with e nil leaves `event` nil, and receive then fails with an index error.

*Fix.* Module doc and @usage: the receiver creates `local inbox = mailbox.inbox(4096)` and passes `inbox.queue, inbox.event` to the other runtime (e.g. `rt:resume(inbox.queue, inbox.event)`), where the sender builds `mailbox.outbox(q, e)`. State that e is required when q is a fifo, that send works in any context, and that receive sleeps and is refused outside a process runtime.

#### MC-25 · `lib/mailbox.lua:25` · inaccurate · medium

The generated page lists a phantom `Tables: mailbox` entry and renders the constructors as methods of MailBox, `mailbox:inbox (q, e)` / `mailbox:outbox (q, e)`.

*Evidence.* lib/mailbox.lua:23-25 `--- The main mailbox table. -- @table mailbox`, :31 `@type MailBox` placed before :66 `function mailbox.inbox(q, e)` and :80 `function mailbox.outbox(q, e)`.

*Fix.* Drop the `@table mailbox` block and tag inbox/outbox `@within mailbox`, or move the `@type MailBox` block after them, so they render as mailbox.inbox(q, e) / mailbox.outbox(q, e).

#### MC-26 · `lib/mailbox.lua:91` · inaccurate · medium

MailBox:receive says timeout is 'maximum time to wait in jiffies', 'If 0, returns immediately', and '@treturn[2] string Error message if the wait times out'.

*Evidence.* lib/mailbox.lua:99-100 `local ok, err = self.event:wait(timeout)` / `if not ok then error(err) end`; lib/luacompletion.c:82-83 `lua_Integer timeout = luaL_optinteger(L, 2, MAX_SCHEDULE_TIMEOUT); unsigned long timeout_jiffies = msecs_to_jiffies((unsigned long)timeout);` so the unit is milliseconds, and a timeout or an interrupt raises ("...: timeout" / "interrupt") instead of returning a string; timeout 0 on an empty mailbox raises "timeout".

*Fix.* '@tparam[opt] integer timeout maximum wait in milliseconds; omitted waits indefinitely; 0 returns at once. @treturn string|nil the message, or nil if the event fired with the queue empty. @raise an error ending in "timeout" when the wait elapses (including timeout 0 on an empty mailbox) or "interrupt" when a signal or thread:stop() interrupts it; "malformed message" on a truncated header; "runtime context mismatch" from a softirq/hardirq runtime (completion:wait's lunatik_checkruntime).' Drop @treturn[2].

#### MC-27 · `autogen/specs.lua:54` · missing · low

The linux.scx page ('Extensible Scheduler flags.') does not say the module is empty on kernels without <linux/sched/ext.h>.

*Evidence.* autogen/specs.lua:54 `{ header = "linux/sched/ext.h", prefix = "SCX_", module = "scx", optional = true,`; the autogen.lua comment at :115 says an optional dump's 'module then comes out empty instead of failing the build'.

*Fix.* desc: 'Extensible Scheduler (sched_ext) flags; empty on kernels without <linux/sched/ext.h> (before 6.12).' Have autogen/ldoc.lua append such a note for every spec with optional = true.

#### MC-28 · `config.ld:16` · missing · low

lib/util.lua (bin2hex, hex2bin, log, test) is installed and required by lighten and the runtime tests, but it is absent from config.ld, so it has no page.

*Evidence.* Makefile:115 `$(call INSTALL_LUA,lib/util.lua,${SCRIPTS_INSTALL_PATH}/)`; lib/lighten.lua:13 `local hex2bin = require("util").hex2bin`; config.ld `file = {...}` has no './lib/util.lua'.

*Fix.* Add './lib/util.lua' to config.ld in the module-name order the list keeps (between './lib/luathread.c' and './lib/luaxdp.c' by module name: thread < util < xdp). In util.lua's module doc, mark log and test as test helpers. No README row: the README has no module table.

#### MC-29 · `lib/class.lua:28` · missing · low

The class page shows only the module blurb and usage; the function the module returns, and the fact that `new` wires `__close` only when the class already has `close` at instantiation time, are not rendered.

*Evidence.* lib/class.lua:28-32 doc on `return function(class)` is not rendered on doc/modules/class.html; the file's local `new` sets `self.__close = self.close` on each :new call.

*Fix.* Render the call as `@function class` with `@tparam[opt] table class` and `@treturn table`, and add: 'class:new(o) sets __index and __close (from close, as it is at that call) on the class, then makes it the metatable of o.'

#### MC-30 · `lib/crypto/hkdf.lua:20` · inaccurate · low

HKDF:close 'This method is also called by the garbage collector.'

*Evidence.* lib/crypto/hkdf.lua:26-27 `HKDF.__close = HKDF.close` / `HKDF.__index = HKDF`: there is no __gc. The underlying shash transform is freed by its own __gc, not through close.

*Fix.* 'Releases the HMAC transform; also called when a to-be-closed variable holding the instance goes out of scope. Without close the transform is freed when it is collected.' Optionally add to expand: 'length is at most 255 * digest size'.

#### MC-31 · `lib/luabyteorder.c:11` · unclear · low

The byteorder module doc is just 'Byte Order Conversion': no usage, no link to where the values come from (data accessors), and no note that inputs are silently truncated to the function's width.

*Evidence.* lib/luabyteorder.c:18 `T x = (T)luaL_checkinteger(L, 1);` casts to u16/u32/u64 without a check.

*Fix.* Module doc: 'Converts integers between host, big-endian (network) and little-endian order, typically around data:getuint16/getuint32. Inputs are truncated to the function's width.' @usage: `local port = byteorder.ntoh16(pkt:getuint16(20))`.

#### MC-32 · `lib/luabyteorder.c:26` · inaccurate · low

Every byteorder @tparam reads 'num16-bit integer ...' with no space, so LDoc takes 'num16' as the parameter name and renders the description as '-bit integer in host byte order.'

*Evidence.* lib/luabyteorder.c:26, 34, 42, 50, 58, 66, 74, 82, 90, 98, 106, 114, 123, 130, 137, 144, 159, 166 `* @tparam integer num16-bit integer in host byte order.`; doc/modules/byteorder.html renders 'be16toh (num16)', 'htobe16 (num16)'.

*Fix.* `@tparam integer num 16-bit integer in host byte order.` (and the 32/64-bit variants), on every block.

#### MC-33 · `lib/luacompletion.c:54` · missing · low

completion:wait says the calling runtime must be sleepable but does not document the error raised otherwise.

*Evidence.* lib/luacompletion.c:86 `lunatik_checkruntime(L, LUNATIK_OPT_NONE);` -> lunatik.h:203-204 `luaL_error(L, LUNATIK_ERR_RUNTIME)` = "runtime context mismatch".

*Fix.* Add `@raise "runtime context mismatch" from a softirq or hardirq runtime (including its script body)`, and say that complete() may be called from any runtime.

#### MC-34 · `lib/luacrypto_aead.c:151` · unclear · low

The crypto @raise clauses say 'on allocation failure', 'incorrect IV length', 'on invalid key' without the values a script can match on: the errors are kernel errno names.

*Evidence.* lib/luacrypto.h:93-94 `if (iv_len != expected) lunatik_throw(L, -EINVAL);` (the raised value is "EINVAL"); luacrypto.h:19-20 and :69-70 `lunatik_throw(L, PTR_ERR(tfm))` (e.g. "ENOENT" for an unknown algname); luacrypto_skcipher.c:106-109 raises the errno from crypto_skcipher_encrypt, e.g. "EINVAL" for cbc input that is not a multiple of blocksize.

*Fix.* Crypto module doc: 'Errors are raised as errno names: "ENOENT" for an unknown algorithm, "EINVAL" for a wrong IV, key or state length or a block cipher input that is not a multiple of blocksize(), "EBADMSG" for an AEAD tag mismatch, "ENOMEM" on allocation failure.'

#### MC-35 · `lib/luacrypto_core.c:6` · inaccurate · low

The crypto sources carry a comment saying the per-tfm state exists so that encrypt/decrypt never allocate on the hot path 'e.g. softirq', which suggests softirq use, while every crypto class is process-context only.

*Evidence.* lib/luacrypto.h:31-32 `/* ... so encrypt/decrypt never allocates on the hot path (e.g. softirq). */`, against class opts without an IRQ bit (luacrypto_aead.c:217, luacrypto_skcipher.c:165) that lunatik_newobject refuses in an IRQ runtime (lunatik_obj.c:23, lunatik.h:219-222).

*Fix.* Either make the classes usable from softirq (object created in process context and shared) and document how, or drop 'e.g. softirq' from the comment so it matches the process-only contract that finding 14 documents.

#### MC-36 · `lib/luadata.c:121` · unclear · low

data:checksum has no description of which checksum it computes. getstring/setstring do not say that a zero length (offset at the end, or an empty string) raises.

*Evidence.* lib/luadata.c:135-136 `__wsum sum = csum_partial(value, length, 0); lua_pushinteger(L, csum_fold(sum));` (16-bit ones'-complement Internet checksum, folded and complemented); :36 `offset >= 0 && length > 0 && ...` rejects length 0.

*Fix.* checksum: 'Returns the 16-bit ones'-complement Internet checksum of [offset, offset+length), folded and complemented (csum_fold); 0 over a region that already holds a correct checksum.' getstring/setstring: 'length must be at least 1'.

#### MC-37 · `lib/luafifo.c:6` · inaccurate · low

The fifo module calls the queues 'lockless', and `close` is described as 'an alias for the __close and __gc metamethods'.

*Evidence.* lib/luafifo.c:130 `.opt = LUNATIK_OPT_SOFTIRQ | LUNATIK_OPT_MONITOR,`: every method runs under the object lock. luafifo.c:116-118 `{"__gc", lunatik_deleteobject}, {"__close", lunatik_closeobject}, {"close", lunatik_closeobject}`: __gc is not close.

*Fix.* Module: 'Byte FIFO over kfifo. Each call takes the object's lock, so one fifo can be shared between runtimes (e.g. through runtime:resume) and used from softirq.' close: 'Frees the buffer; also runs when a to-be-closed variable goes out of scope. Later calls raise "null pointer dereference".'

#### MC-38 · `lib/lualinux.c:84` · unclear · low

linux.schedule's state parameter says 'See linux.task for possible values', but linux.task exports every TASK_* constant while only four are accepted. The tracing usage names the result `was_tracing`, though it is the state after the change.

*Evidence.* lib/lualinux.c:102-103 `luaL_argcheck(L, state == TASK_INTERRUPTIBLE || state == TASK_UNINTERRUPTIBLE || state == TASK_KILLABLE || state == TASK_IDLE, 2, "invalid task state");`; :134 `lua_pushboolean(L, tracing_is_on());` after the change.

*Fix.* state: 'one of linux.task.INTERRUPTIBLE (default), UNINTERRUPTIBLE, KILLABLE or IDLE; any other raises "invalid task state".' In tracing's usage rename was_tracing to is_on.

#### MC-39 · `lib/lualinux.c:188` · missing · low

linux.ifindex and linux.ifaddr do not say they resolve only in the initial network namespace (netns documents this for ifindex, but ifindex's own block does not).

*Evidence.* lib/lualinux.c:202 `struct net_device *dev = dev_get_by_name(&init_net, ifname);` and :226 `dev_get_by_index(&init_net, ifindex);`. A device in a container namespace raises "device not found".

*Fix.* Add to both blocks: 'Resolved in the initial network namespace; a device of another namespace raises "device not found" (see linux.netns).'

#### MC-40 · `lib/lualinux.c:268` · inaccurate · low

linux.errname says it returns 'unknown' (or the error number as a string) if the name cannot be resolved.

*Evidence.* lunatik_aux.c:79-86 `err = abs(err); ... lua_pushstring(L, name ? name : "unknown");` and the pre-6.7 arm `lua_pushstring(L, buf[1] == 'E' ? buf + 1 : "unknown");`: it never returns the number. It also accepts negative errnos.

*Fix.* '@treturn string symbolic name (e.g. "ENOENT"), or "unknown"; the sign of err is ignored.'

#### MC-41 · `lib/luatask.c:31` · inaccurate · low

task:comm is 'the executable', 'truncated to TASK_COMM_LEN (16) characters'; task:prio 'Ranges from 0 (highest) to 139'.

*Evidence.* lib/luatask.c:40-41 `char comm[TASK_COMM_LEN]; strscpy_pad(comm, task->comm, sizeof(comm));` gives at most 15 characters plus NUL, and comm is whatever the task set (PR_SET_NAME, kthread name), not necessarily the executable. kernel/sched/core.c:2166 `prio = MAX_DL_PRIO - 1;` gives -1 for SCHED_DEADLINE tasks.

*Fix.* comm: 'the task's name (comm), at most 15 characters: the executable's basename unless the task renamed itself.' prio: '-1 for deadline tasks, 0-99 real-time, 100-139 normal.' Add that task.current() in a softirq/hardirq callback returns the interrupted task.

#### MC-42 · `lib/luathread.c:210` · unclear · low

thread.run's @raise paraphrases its errors ('Error if called during module load, if the runtime is not sleepable or has been stopped...') instead of quoting them, and the module never says that thread objects cannot be created in softirq/hardirq runtimes or that shouldstop() returns false outside a kernel thread.

*Evidence.* lib/luathread.c:230 "not allowed during module load", :232 "IRQ runtime cannot spawn threads", :197 "stopped runtime", :199 "couldn't pass the thread arguments", :248 "failed to create a new thread"; :172 `.opt = LUNATIK_OPT_MONITOR` (no IRQ bit, so thread.current() in an IRQ runtime raises "'thread': process-context class in interrupt-context runtime"); :73 `(current->flags & PF_KTHREAD) ? kthread_should_stop() : 0`. stop on a thread.current() object or an already stopped thread only logs (lines 100-118).

*Fix.* Quote each message in run's @raise. Module doc: 'Process runtimes only. shouldstop() is false outside a kernel thread. stop() on an object from thread.current(), or on a stopped thread, only logs a warning.'

#### MC-43 · `lib/lunatik/runner.lua:69` · missing · low

runner.spawn documents only `script`, but the function takes `context` and `ispercpu`, and its @raise already refers to `percpu`.

*Evidence.* lib/lunatik/runner.lua:77 `function runner.spawn(script, context, ispercpu)`; :79-80 `if ispercpu then error("spawn does not support percpu scripts", 0)`.

*Fix.* Add `@tparam[opt="process"] string context` (only "process" can spawn: a softirq/hardirq runtime is created, then thread.run refuses it with "IRQ runtime cannot spawn threads" and the runtime is stopped) and `@tparam[opt] boolean ispercpu must be false`. Change `@treturn userdata` to `@treturn thread`.

#### MC-44 · `lib/lunatik_core.c:22` · unclear · low

_ENV's summary is cut at 'scripts exchange objects (e.g.' on the page, and the doc does not say what type it is or when it exists.

*Evidence.* LDoc splits the summary at the first period ('e.g.'), as the rendered doc/modules/lunatik.html shows. lunatik_core.c:250 `if (lunatik_env != NULL)` (nil until the lunatik_run module creates it); lunatik_run.c:21 `lunatik_env = luarcu_newtable(LUARCU_DEFAULT_SIZE, LUNATIK_OPT_NONE)`.

*Fix.* 'Shared rcu.table through which scripts exchange objects, for instance the runner's runtimes and threads tables. Present once the lunatik_run module is loaded.'

#### MC-45 · `lib/mailbox.lua:64` · inaccurate · low

The usages `mailbox.inbox(10) -- Inbox with capacity for 10 messages` and `mailbox.outbox(10) -- ... 10 messages` treat q as a message count.

*Evidence.* lib/mailbox.lua:50 `mbox.queue, mbox.event = fifo.new(q), completion.new()` (q is a byte capacity, rounded up to a power of two by kfifo) and :121 `self.queue:push(string.pack("s", message))` (each message takes string.packsize("T") = 8 bytes of header plus its length); push raises "not enough space" when full.

*Fix.* Usage: `local inbox = mailbox.inbox(4096) -- 4096-byte queue; each message takes 8 bytes of header plus its length`, and the same for outbox.

#### MC-46 · `lib/struct.lua:71` · missing · low

The struct page drops the constructor (calling the module on a layout) and the `size` field, and lists pack, unpack and fieldsize as module functions without the codec receiver.

*Evidence.* lib/struct.lua:71-75 the doc block sits on `return function(layout)`, an anonymous function LDoc does not render; doc/modules/struct.html shows only 'fieldsize (name)', 'pack (...)', 'unpack (buf[, pos])' under Functions. It also says nothing about the assert at :77-78 ('derived format does not match the layout size').

*Fix.* Document the call as `@function struct` with `@tparam table layout`, `@treturn codec` and `@raise` for 'derived format does not match the layout size'. Declare `@type codec` with `@field size`, move pack/unpack/fieldsize under it, and state that values are packed in native byte order.

### Networking modules

#### MN-01 · `lib/luanetfilter.c:201` · missing · high

`register` documents `mark` only as "optionally `mark` (integer, default 0)", which reads as a mark the hook sets. Nothing says it is a filter: the hook runs only for packets whose skb->mark equals it, so with the default 0 a packet that already carries a mark skips the Lua callback.

*Evidence.* lib/luanetfilter.c:102-103 `if (likely(hook->mark != skb->mark))\n\t\treturn policy;` (policy = NF_ACCEPT, line 100)

*Fix.* In @tparam opts say: `mark` (integer, default 0) selects packets: the callback runs only for packets whose `skb:mark()` equals it, and every other packet is accepted without reaching Lua, so with the default 0 a packet that something else already marked skips the hook. Add a @usage.

#### MN-02 · `lib/luanetfilter.c:201` · missing · high

The callback contract is missing: the hook function is called as `hook(skb)`, returns a verdict (linux.nf.action) and optionally a new mark, and a raise or an out-of-range verdict means NF_ACCEPT. The constants for pf, hooknum and priority (linux.nf.proto / nf.inet / nf.ip.pri) are not referenced, and there is no @usage.

*Evidence.* lib/luanetfilter.c:82 `if (lua_pcall(L, 1, 2, 0) != LUA_OK)`; 88-90 `if (!lua_isnil(L, -1)) skb->mark = (u32)lua_tointeger(L, -1); ret = (int)lua_tointeger(L, -2);`; 106 `return (ret < 0 || ret > NF_MAX_VERDICT) ? policy : ret;`

*Fix.* Document `hook` as `function(skb) -> verdict[, mark]`: the verdict is a `linux.nf.action` value, a non-nil second value is stored in skb->mark, a raising callback accepts the packet, and a callback that returns no verdict (nil or a non-number) DROPS it, because nil reads as 0 = NF_DROP. Point pf/hooknum/priority to `linux.nf.proto`, `linux.nf.inet`, `linux.nf.ip.pri`, and add examples/dnsblock/nf_dnsblock.lua's registration as @usage.

#### MN-03 · `lib/luanetfilter.c:201` · missing · high

Nothing says that a hook callback which returns no verdict drops the packet. The pcall asks for two results and pads with nil, and lua_tointeger(nil) is 0, which is NF_DROP. A callback written as a pure observer (it logs and returns nothing) therefore drops every matching packet, and on LOCAL_OUT or LOCAL_IN that is the host's traffic.

*Evidence.* lib/luanetfilter.c:82 `lua_pcall(L, 1, 2, 0)`; 90 `ret = (int)lua_tointeger(L, -2);`; 106 only `ret < 0 || ret > NF_MAX_VERDICT` falls back to NF_ACCEPT; NF_DROP is 0 (linux.nf.action.DROP)

*Fix.* State in register's `hook` description that the callback must return a `linux.nf.action` verdict: a missing or non-integer return is read as 0 = `DROP`, and only a raising callback falls back to `ACCEPT`.

#### MN-04 · `lib/luanetfilter.c:204` · missing · high

`register` does not say it may only be called from the script body. Called from a hook callback of a non-percpu softirq script, it runs `nf_register_net_hook`, which sleeps, while the runtime's spinlock is held. The only after-load guard is on the percpu path.

*Evidence.* lib/luanetfilter.c:135 `if ((ret = nf_register_net_hook(&init_net, &hook->nfops)) != 0)`, reached through luanetfilter_own (line 177) with no lunatik_checkarmed; kernel net/netfilter/core.c:432 `mutex_lock(&nf_hook_mutex);`. The only armed check is in lunatik_percpu.c:53-54, reached only when percpu != NULL (luanetfilter.c:218).

*Fix.* Add `lunatik_checkarmed(L)` at the top of luanetfilter_lregister (it raises only in an IRQ runtime that is ready, lunatik.h:225-228), and document it: "Call at the top level of the script, before the runtime is armed", with @raise `not allowed after module load` for every runtime, not only percpu.

#### MN-05 · `lib/luaskb.c:100` · inaccurate · high

skb:data documents `"net" (default, L3)`. For the skb a TC program hands over (`tc_ctx:skb()`), skb->data is at the MAC header, so "net" returns the frame from L2. "mac" then adds mac_len to a length that already starts at L2, and the writable view runs mac_len bytes past the linear data.

*Evidence.* kernel net/sched/cls_bpf.c:97-101 `} else if (at_ingress) { __skb_push(skb, skb->mac_len); bpf_compute_data_pointers(skb); filter_res = bpf_prog_run(prog->filter, skb);` (egress runs with data at L2 too); lib/luaskb.c:114-121 `void *ptr = skb->data; size_t size = skb_headlen(skb); if (mac) { ... ptr += skb_mac_offset(skb); size += skb_mac_header_len(skb); }`; examples/sniclassify/classify.c:56 computes the payload offset from the L2 `data` and sni.lua:30 reads it through `raw:data()`

*Fix.* Say that "net" means from skb->data: L3 in netfilter hooks, L2 in a tc callback. In code, bound the "mac" view to the linear area (size = skb_headlen(skb) - skb_mac_offset(skb)) so that it never extends past skb_tail_pointer, and add a tc test for data("mac").

#### MN-06 · `lib/luasocket.c:230` · missing · high

receive and accept block until data or a connection arrives, with no default timeout, and nothing in the doc says so. In a `lunatik spawn` thread body this makes the thread unstoppable. AGENTS.md states the rule, but the socket doc does not, and it is where a script author reads.

*Evidence.* lib/luasocket.c:269 `int flags = luaL_optinteger(L, 3, 0);` and 282 `lunatik_tryret(L, ret, kernel_recvmsg, socket, &msg, &vec, 1, len, flags);` (no timeout of its own); 613-616 `kernel_accept(socket, ..., flags)` with flags default 0

*Fix.* Add to receive (and restate for accept): the call blocks until data arrives unless `linux.socket.msg.DONTWAIT` is passed or `SO_RCVTIMEO_NEW` is set with setsockopt. In a spawned thread, bound every call and poll `thread.shouldstop()`, or `lunatik stop` cannot return. Link setsockopt's @usage.

#### MN-07 · `lib/luaxdp.c:226` · inaccurate · high

The xdp.attach and tc.attach usages key the runtime as `"my_xdp_handler.lua"` / `"my_tc_handler.lua"` ('Key matches the script name'). The runner registers runtimes with the `.lua` stripped, so that key finds nothing: the kfunc returns -1 and the callback never runs. The same doc's prose example (`"examples/filter/sni"`) is right.

*Evidence.* lib/lunatik/runner.lua:27-29 `local function trim(script) return (script:gsub("%.lua$", "")) end`; runner.lua:60,65 `local script = trim(script) ... env.runtimes[script] = runtime`; lunatik_ebpf.h:34 `luarcu_getobject(runtimes, key, keylen)`; examples/filter/https.c:12 `static char runtime[] = "examples/filter/sni";`

*Fix.* In both usages write `char rt_key[] = "my_xdp_handler";` (and `"my_tc_handler"`), and say under `key` that it is the script path relative to /lib/modules/lua without the `.lua` extension, as given to `lunatik run`.

#### MN-08 · `lib/luanetfilter.c:200` · inaccurate · medium

Because the `@type netfilter_hook` block comes first, the generated page lists the module function as a method, `netfilter_hook:register (opts)`. The real call is `netfilter.register{...}`.

*Evidence.* lib/luanetfilter.c:225-227 `static const luaL_Reg luanetfilter_lib[] = { {"register", luanetfilter_lregister},` (library function, not a method); doc/modules/netfilter.html lists 'netfilter_hook:register (opts)' under 'Class netfilter_hook'

*Fix.* Add `@within netfilter` to the register block so that it renders as `netfilter.register(opts)`.

#### MN-09 · `lib/luanetlink.c:141` · missing · medium

netlink.channel says userspace resolves the family 'to learn the group it must join' but never names the group. The one multicast group is always called `lunatik`, and a userspace subscriber needs that name to join.

*Evidence.* lib/luanetlink.c:25 `#define LUANETLINK_MCGRP	"lunatik"` and 168 `memcpy(channel->mcgrp.name, LUANETLINK_MCGRP, sizeof(LUANETLINK_MCGRP));`

*Fix.* Add: the family has one multicast group named "lunatik", which userspace joins through CTRL_ATTR_MCAST_GROUPS (e.g. `genl_ctrl_resolve_grp(sk, name, "lunatik")` then `nl_socket_add_membership`). Add a @usage covering creation at load and a multicast from a hook.

#### MN-10 · `lib/luaskb.c:53` · missing · medium

The skb type doc does not say where an skb comes from (the netfilter hook argument, `tc_ctx:skb()`, `skb:copy()`), that a handed skb is valid only during the callback, or that afterwards every method raises `skb is not set`. It also leaves out that the `data` object returned by `data()` is cleared when the callback returns. The module has no @usage.

*Evidence.* lib/luaskb.c:27-29 `LUNATIK_PRIVATECHECKER(luaskb_check, ... luaL_argcheck(L, private->skb != NULL, ix, "skb is not set");`; lib/luanetfilter.c:92 `luaskb_clear(object);` after the call; lib/luaskb.h:369-373 luaskb_clear clears data and skb

*Fix.* Extend the type doc: the skb is handed to netfilter hooks and returned by `tc_ctx:skb()`, and it is valid only while that callback runs. Afterwards its methods raise `skb is not set` and the `data` view from `data()` is cleared too. Use `copy()` to keep a packet. Add a netfilter @usage.

#### MN-11 · `lib/luaskb.c:131` · unclear · medium

`resize` measures and changes only the linear head (skb_headlen), not `#skb`. On a non-linear skb, growing raises 'insufficient tailroom' because tailroom reads 0. Shrinking returns silently without trimming and puts a WARN in dmesg. The doc does not say to linearize first (for example by calling `data()`).

*Evidence.* lib/luaskb.c:142 `size_t cur_size = skb_headlen(skb);`, 146 `luaL_argcheck(L, skb_tailroom(skb) >= needed, 2, "insufficient tailroom");`, 150 `skb_trim(skb, new_size);`; kernel include/linux/skbuff.h:2716 `return skb_is_nonlinear(skb) ? 0 : skb->end - skb->tail;` and 3073 `if (WARN_ON(skb_is_nonlinear(skb))) return;`

*Fix.* Document that `n` is the new length of the linear data that `data()` views, not `#skb`. Better, linearize at the top of resize with luaskb_checklinearize, as data() and copy() do, which removes both the spurious raise and the WARN reachable from Lua.

#### MN-12 · `lib/luasocket.c:7` · missing · medium

The socket module doc does not say sockets are process-context only. `socket.new` (and `accept`) in a softirq or hardirq runtime raise a class/context error.

*Evidence.* lib/luasocket.c:564 `.opt = LUNATIK_OPT_MONITOR | LUNATIK_OPT_EXTERNAL,` (no SOFTIRQ); lunatik_obj.c:24 `lunatik_checkclass(L, class);`; lunatik.h:219-222 `if (lunatik_cannotsleep(L, !lunatik_isirq(class->opt))) luaL_error(L, "'%s': %s", class->name, LUNATIK_ERR_CONTEXT);` with LUNATIK_ERR_CONTEXT "process-context class in interrupt-context runtime"

*Fix.* Add to the module doc: sockets sleep, so they are created and used from a process runtime (the default) or a spawned thread, and in a softirq/hardirq runtime `socket.new` and `accept` raise `'socket': process-context class in interrupt-context runtime`. Add the same to new's @raise.

#### MN-13 · `lib/luasocket.c:14` · outdated · medium

The module doc says "The library also exposes constants for address families, socket types, IP protocols, and message flags". The `socket` library registers only `new`; the constants live in `linux.socket`.

*Evidence.* lib/luasocket.c:537-540 `static const luaL_Reg luasocket_lib[] = { {"new", luasocket_lnew}, {NULL, NULL} };`

*Fix.* Replace the sentence with: constants for address families, socket types, protocols, message flags and option levels/names are in `linux.socket` (`af`, `sock`, `ipproto`, `msg`, `sol`, `so`).

#### MN-14 · `lib/luasocket.c:189` · inaccurate · medium

send, connect, bind, receive, getsockname and getpeername describe only AF_INET, AF_UNIX and 'other families: a packed string' (for AF_PACKET send, 'MAC address'). The code takes AF_PACKET as two integers (protocol, ifindex). AF_NETLINK takes two optional integers (pid, groups) and always sends to an explicit destination. receive/getsockname return pid and groups as two integers for AF_NETLINK. connect reads flags at index 4 for AF_PACKET and AF_NETLINK, not only for AF_INET.

*Evidence.* lib/luasocket.c:77-81 `addr_ll->sll_protocol = htons((u16)lunatik_checkinteger(L, ix, 0, U16_MAX)); addr_ll->sll_ifindex = (int)lunatik_checkinteger(L, ix + 1, 0, INT_MAX);`; 83-87 `addr_nl->nl_pid = (u32)luaL_optinteger(L, ix, 0); addr_nl->nl_groups = ...`; 220 `if (unlikely(nargs >= 3) || luasocket_family(socket) == AF_NETLINK)`; 121-125 pushaddr pushes nl_pid and nl_groups; 55 `luasocket_ispair(family) ((family) == AF_INET || (family) == AF_PACKET || (family) == AF_NETLINK)`; 390 flags index `luasocket_ispair(...) ? 4 : 3`

*Fix.* Describe the address arguments once in the `socket` type block and reference that from each method: AF_INET (ipv4:int, port:int); AF_PACKET (ethertype:int in host order, ifindex:int); AF_NETLINK ([pid=0], [groups=0]), which send always passes and so defaults to the kernel; AF_UNIX (path:string); other families a packed string. In send, drop 'MAC address for AF_PACKET'. In connect, say that flags follows a two-argument address for AF_INET, AF_PACKET and AF_NETLINK. In receive/getsockname/getpeername, say that AF_NETLINK returns `pid, groups`.

#### MN-15 · `lib/luasocket.c:426` · inaccurate · medium

The getsockname and getpeername usages test `my_socket.sk.sk_family`, and bind and connect say the address 'depends on `socket.sk.sk_family`'. A socket object exposes no `sk` field, so the usage raises.

*Evidence.* lib/luasocket.c:542-556 the method table (close, send, receive, bind, listen, accept, connect, setsockopt, getsockname, getpeername), which has no `sk`; lines 295, 371, 426 and 448 cite `socket.sk.sk_family`

*Fix.* Say the interpretation depends on the family the socket was created with (`socket.new`'s first argument), and drop the `if ... .sk.sk_family == ...` guard from the getsockname/getpeername usages.

#### MN-16 · `lib/luaxdp.c:191` · inaccurate · medium

xdp.attach and tc.attach say 'The runtime invoking this function must be non-sleepable' and @raise 'if the current runtime is sleepable'. Only softirq is accepted: a hardirq runtime, which is also non-sleepable, raises too, with the message `runtime context mismatch`.

*Evidence.* lib/luaxdp.c:233 `lunatik_checkruntime(L, LUNATIK_OPT_SOFTIRQ);`; lib/luatc.c:240 same; lunatik.h:203-204 raises LUNATIK_ERR_RUNTIME "runtime context mismatch"

*Fix.* Replace with: the runtime must be softirq (`lunatik run <script> softirq`); @raise `runtime context mismatch` in a process or hardirq runtime.

#### MN-17 · `lib/netlink/rt/route.lua:61` · missing · medium

route/link/addr/rule `list` return 'list of route tables' (link/address/rule) and name no fields. route:add/del do not give the format of `dst`/`gateway`. The code expects and returns raw network-order bytes, and message.attrs packs a number as a native-endian u32, so a `net.aton()` integer lands byte-swapped on little-endian hosts.

*Evidence.* lib/netlink/rt/route.lua:48-59 decode returns `{family, dst_len, src_len, tos, table, protocol, scope, rtype, flags, dst = attrs[rtnl.rta.DST], gateway = attrs[rtnl.rta.GATEWAY], oif, priority}`; lib/netlink/message.lua:79-81 `if type(value) == "number" then value = pack(U32, value)` with U32 = "=I4" (line 26); tests/netlink/route_adddel.lua:12 `local DST = string.char(192, 0, 2, 0) -- 192.0.2.0 (TEST-NET-1), network byte order`

*Fix.* List each record's fields in @treturn (route: family, dst_len, src_len, tos, table, protocol, scope, rtype, flags, dst, gateway, oif, priority; link: family, ltype, ifindex, flags, change, name, mtu; addr: family, prefix_len, scope, ifindex, address, label; rule: family, action, flags, table, priority, fwmark). Say that `dst`, `gateway` and `address` are raw network-order bytes, e.g. `string.pack(">I4", net.aton("192.0.2.0"))`, never a bare integer.

#### MN-18 · `lib/netlink/session.lua:11` · missing · medium

The session docs (and genl, nl80211.*, rt.*) say only 'All methods block and require a sleepable runtime'. They do not say that every request raises `not allowed under RTNL` when it runs from a netdevice notifier callback. The underlying socket send/receive refuses a netlink socket under RTNL.

*Evidence.* lib/luasocket.c:140-144 `if (luasocket_family(socket) == AF_NETLINK) lunatik_checkrtnl(L);` called at 213 (send) and 273 (receive); lunatik.h:195 `#define LUNATIK_ERR_RTNL "not allowed under RTNL"`

*Fix.* Append to session's module doc: requests raise `not allowed under RTNL` from a `notifier.netdevice` callback and any coroutine it runs; defer them to a thread or to after the callback. genl, nl80211 and rt reference session via @see.

#### MN-19 · `lib/skb/attr.lua:41` · inaccurate · medium

`@classmod` renders `attr.new` as the method `skb.attr:new (skb)`. Called with a colon it wraps the class instead of the packet. The doc also omits that reading or writing any key other than `mark` or `priority` raises.

*Evidence.* lib/skb/attr.lua:44 `function attr.new(skb)` (dot, one argument); doc/classes/skb.attr.html lists 'skb.attr:new (skb)' under Methods; lib/skb/attr.lua:19-23 `error("skb has no attribute '" .. key .. "'")`

*Fix.* Mark the constructor static (`@static`) so that it renders `skb.attr.new(skb)`. Add: keys other than `mark` and `priority` raise `skb has no attribute '<key>'`. Add a @usage (`local view = attr.new(skb); view.priority = 3`).

#### MN-20 · `doc/modules/xdp.html:285` · broken-link · low

Cross-references to a class type resolve nowhere. LDoc links `#<type>`, but the page anchors a class as `Class_<type>`. This affects xdp_ctx, tc_ctx, skb, inet, unix, session, genl, netlink.channel, and the nl80211 and rt object types.

*Evidence.* doc/modules/xdp.html:285 `<a href="../modules/xdp.html#xdp_ctx">xdp_ctx</a>` while the only anchor is line 182 `<a name="Class_xdp_ctx"></a>`; the same holds on modules/tc.html (#tc_ctx), skb.html (#skb), socket.inet.html (#inet), socket.unix.html (#unix), netlink.session.html (#session), netlink.genl.html (#genl), netlink.channel.html (#netlink.channel) and the nl80211.* and rt.* pages

*Fix.* In doc/style/ldoc.ltp, beside the section anchor at line 196, emit `<a name="$(kitem.name)"></a>` for a class section (the @type item's name, dots kept) so that LDoc's `#<type>` references land on the class section.

#### MN-21 · `lib/luanetfilter.c:7` · missing · low

The module doc does not say hooks are registered only in the initial network namespace.

*Evidence.* lib/luanetfilter.c:135 `nf_register_net_hook(&init_net, &hook->nfops)` and 144 `nf_unregister_net_hook(&init_net, ...)`

*Fix.* Add to the module doc: hooks are registered in the initial network namespace only, and packets of other namespaces do not reach them.

#### MN-22 · `lib/luanetfilter.c:197` · missing · low

The netfilter docs never say the script must run as `lunatik run <script> softirq`. `register` raises in a process runtime, and neither the module doc nor @raise mentions it.

*Evidence.* lib/luanetfilter.c:211 `lunatik_checkruntime(L, luanetfilter_class.opt)` with .opt = LUNATIK_OPT_SOFTIRQ (line 193); lunatik.h:203-204 `if (lunatik_context(runtime->opt) != lunatik_context(opt)) luaL_error(L, LUNATIK_ERR_RUNTIME);` and LUNATIK_ERR_RUNTIME is "runtime context mismatch" (lunatik.h:193)

*Fix.* Add one line to the module doc: scripts that register hooks run as `lunatik run <script> softirq`, linking the guide's execution-context section, and add `runtime context mismatch` outside a softirq runtime to @raise.

#### MN-23 · `lib/luanetlink.c:96` · missing · low

`unicast` does not say it delivers only to a port in the initial network namespace.

*Evidence.* lib/luanetlink.c:118 `genlmsg_unicast(&init_net, skb, portid)`

*Fix.* Add: `portid` is a netlink port in the initial network namespace.

#### MN-24 · `lib/luanotifier.c:11` · missing · low

The module doc lists what counts as `notify.DONE` but not what a raising callback yields: `notify.OK`, logged. Its @raise lists also omit `runtime context mismatch` (netdevice outside a process runtime, keyboard/vterm outside a hardirq runtime) and `couldn't create notifier`.

*Evidence.* lib/luanotifier.c:65-67 `if (lua_pcall(L, nargs + 1, 1, 0) != LUA_OK) { pr_err_ratelimited(...); return NOTIFY_OK; }`; 270 `notifier->runtime = lunatik_checkruntime(L, class->opt);`; 283 `luaL_error(L, "couldn't create notifier");`

*Fix.* Add to the module doc: a callback that raises is logged and counts as `notify.OK`. Add to netdevice's @raise: `'notifier': process-context class in interrupt-context runtime` outside a process runtime. Add to keyboard/vterm's @raise: `runtime context mismatch` outside a hardirq runtime. Add to all three: `couldn't create notifier` when the kernel refuses the registration.

#### MN-25 · `lib/luaskb.c:162` · unclear · low

`checksum` gives no conditions. It does nothing for non-IP skbs, updates only TCP/UDP, and for IPv6 uses `nexthdr` directly, so a packet with extension headers is not handled.

*Evidence.* lib/luaskb.c:171-182 `if (skb->protocol == htons(ETH_P_IP)) {...} else if (skb->protocol == htons(ETH_P_IPV6)) { ... luaskb_csum(skb, ip6h->nexthdr, 0);` and 156-159 only UDP/TCP

*Fix.* Add: recomputes the IPv4 header checksum and the TCP/UDP checksum; non-IP packets and IPv6 packets with extension headers are left unchanged.

#### MN-26 · `lib/luaskb.c:186` · unclear · low

`forward` does not say that it transmits a clone and the original skb continues through the hook. The caller decides the original's verdict, usually DROP to avoid a duplicate.

*Evidence.* lib/luaskb.c:200-203 `struct sk_buff *nskb = lunatik_checknull(L, skb_clone(skb, GFP_ATOMIC)); skb_push(nskb, ...); dev_queue_xmit(nskb);`

*Fix.* Add: transmits a clone out of skb->dev; the original is untouched and still needs a verdict (return `DROP` to avoid sending it twice).

#### MN-27 · `lib/luaskb.c:208` · missing · low

`connmark` does not say it exists only when the kernel has CONFIG_NF_CONNTRACK_MARK. Without it the method is nil, and a script calling it gets 'attempt to call a nil value'.

*Evidence.* lib/luaskb.c:207 `#if defined(CONFIG_NF_CONNTRACK_MARK)` around the function and 282-284 around its method-table entry

*Fix.* Add: only present when the kernel is built with `CONFIG_NF_CONNTRACK_MARK`; test `skb.connmark ~= nil` before relying on it.

#### MN-28 · `lib/luasocket.c:463` · missing · low

setsockopt's @raise omits the argument error that kernels before 6.7 (inside the supported 6.6 floor) raise when the protocol has no setsockopt.

*Evidence.* lib/luasocket.c:491-493 `#else ... luaL_argcheck(L, setter != NULL, 2, "unsupported option level");`

*Fix.* Add to @raise: `unsupported option level` on kernels before 6.7 when the protocol has no setsockopt handler.

#### MN-29 · `lib/luasocket.c:603` · unclear · low

accept declares `@tparam socket self`, so the generated page renders `socket:accept (self[, flags=0])`. That reads as if self is passed twice.

*Evidence.* lib/luasocket.c:603 `* @tparam socket self listening socket object.`; doc/modules/socket.html renders 'socket:accept (self[, flags=0])'

*Fix.* Remove the `@tparam socket self` line.

#### MN-30 · `lib/luaxdp.c:6` · missing · low

The xdp and tc module docs do not state the build and runtime requirements: the kfunc is registered through BTF, so the module needs the running kernel's BTF (CONFIG_DEBUG_INFO_BTF), and the eBPF program has to be loaded separately (bpftool) as an XDP or SCHED_CLS program.

*Evidence.* lunatik_ebpf.h:142-146 `return register_btf_kfunc_id_set(prog_type, &bpf_lua##subsys##_kfunc_set);`; lib/luaxdp.c:255 `LUNATIK_EBPF_KFUNC_INIT(xdp, BPF_PROG_TYPE_XDP);`; lib/luatc.c:262 `BPF_PROG_TYPE_SCHED_CLS`

*Fix.* Add a Requirements paragraph to both modules: kernel BTF (CONFIG_DEBUG_INFO_BTF), `make btf_install` before building, and an XDP (resp. SCHED_CLS) program loaded separately (bpftool) that declares `extern int bpf_luaxdp_run(...) __ksym` (resp. bpf_luatc_run). Link examples/filter and examples/sniclassify.

#### MN-31 · `lib/net.lua:16` · unclear · low

net.aton does not say it performs no validation. Non-numeric parts are skipped, a short address yields a partial integer, and a fifth octet raises a Lua arithmetic error.

*Evidence.* lib/net.lua:24-29 `local bits = { 24, 16, 8, 0 } ... for n in string.gmatch(addr, "(%d+)") do ... ip = ip | (n << bits[i])`

*Fix.* Add: expects a dotted-quad string; the input is not validated (octets are masked to 8 bits, missing trailing octets are 0, and more than four octets raise).

#### MN-32 · `lib/netlink/genl.lua:92` · unclear · low

genl:family says it raises 'if the family does not exist' but gives no message. The kernel answers an unknown name with an NLMSG_ERROR, so the raise is `ENOENT` from the session and the `genl family not found` branch is not reached. nl80211 objects therefore raise `ENOENT` when cfg80211 is not loaded (CONFIG_CFG80211), and the nl80211 docs do not state that requirement.

*Evidence.* lib/netlink/genl.lua:97-103 call then `error("genl family not found: " .. name)`; lib/netlink/session.lua:64-65 raises `linux.errname(err)` first; kernel net/netlink/genetlink.c:1461 `return -ENOENT;` in ctrl_getfamily; lib/netlink/nl80211/object.lua:32 `o.id = o:family("nl80211")`

*Fix.* Change genl:family's @raise to the errno name of the controller's reply (`ENOENT` when no family has that name). Add to netlink.nl80211's module doc: requires cfg80211 (CONFIG_CFG80211); creating an object raises `ENOENT` when the nl80211 family is not registered.

#### MN-33 · `lib/netlink/message.lua:96` · unclear · low

message.attrs describes parsing into `{[type] = value}` but does not say that the key is the raw nla_type, including the NLA_F_NESTED/NLA_F_NET_BYTEORDER bits. The kernel sets NLA_F_NESTED on every nested attribute, so such an attribute is keyed `type | 0x8000`, and nested payloads are not decoded.

*Evidence.* lib/netlink/message.lua:88-93 `for value, atype in records(nlattr, body, pos) do attrs[atype] = value end`; kernel include/net/netlink.h:1933 `return nla_nest_start_noflag(skb, attrtype | NLA_F_NESTED);`

*Fix.* Add: keys are the raw attribute type, flag bits included (a nested attribute appears under `type | NLA_F_NESTED`), and nested payloads stay strings, which a second `message.attrs(value, 1)` parses.

#### MN-34 · `lib/netlink/rt/route.lua:33` · inaccurate · low

Each OOP class page (inet, unix, session, genl, nl80211.*, rt.*) documents `X:new([o])` as 'Creates a new X object'. That is the class helper's derive step: it creates no socket, so the object it returns fails at its first method. The working constructor is calling the class (`netlink.rt.route([pid])`), and the rt and nl80211 subclass pages never document that call or its pid argument. netlink.rt.object documents only a free `list`.

*Evidence.* lib/class.lua:21-26 `local function new(self, o) ... return setmetatable(o, self) end` (no socket); lib/netlink/session.lua:102-107 `function session:__call(pid) local o = self:new() o.socket = socket.new(...)`; lib/netlink/rt/object.lua:19 `object.__call = session.__call`

*Fix.* Reword the `:new` blocks to 'Derives a subclass or wraps a table (internal); create instances by calling the class', or mark them @local. On the rt and nl80211 subclass pages, add a doc-only `@function route:__call` (and link, addr, rule, the nl80211 objects) with `@tparam[opt] integer pid` and session:__call's ESRCH/EOPNOTSUPP raises.

#### MN-35 · `lib/netlink/rt/route.lua:76` · missing · low

route:add/del and rule:add/del have no @raise, but each raises the kernel's errno name on a netlink error reply (e.g. `EEXIST` for a duplicate add).

*Evidence.* lib/netlink/session.lua:60-66 `if err ~= 0 then error(linux.errname(err), 0) end`; route.lua:86 `self:talk(self.NEW, nl.flag.CREATE | nl.flag.EXCL, ...)`

*Fix.* Add `@raise the errno name of a netlink error reply (e.g. "EEXIST" when the route exists, "ESRCH" on deleting a missing one)` to the four functions.

#### MN-36 · `lib/socket/inet.lua:60` · unclear · low

inet:receive says 'if the `raw` parameter (third boolean) is true, it returns the raw IP address'. The argument is socket:receive's `from` flag, and it returns the integer address and the port.

*Evidence.* lib/luasocket.c:237 `@tparam[opt=false] boolean from` and 270 `int from = lua_toboolean(L, 4);`

*Fix.* Say `(len[, flags[, from]])`: with `from` true it also returns the sender as an integer IPv4 address and a port, while `inet.udp:receivefrom` returns the address as a string.

#### MN-37 · `lib/socket/inet.lua:186` · inaccurate · low

inet.udp:receivefrom and unix.dgram:receivefrom document `len` as optional, but they pass it to socket:receive, which requires it, so calling either without `len` raises.

*Evidence.* lib/socket/inet.lua:186 `@param len (number) [optional]` and lib/socket/unix.lua:150 the same; both forward to socket:receive, where lib/luasocket.c:264 `size_t len = (size_t)luaL_checkinteger(L, 2);`

*Fix.* Drop `[optional]` from `len` in both receivefrom docs (or give it a default in the Lua wrappers).

#### MN-38 · `lib/socket/raw.lua:23` · unclear · low

socket.raw.bind is described as 'for receiving frames', yet its usage binds a `tx` socket, and nothing says how to send on it. The send path takes `(ethertype, ifindex)` integers, which the socket.send doc also gets wrong.

*Evidence.* lib/socket/raw.lua:29-30 `local rx <close> = raw.bind(0x0003)` / `local tx <close> = raw.bind(0x88cc, ifindex)`; lib/luasocket.c:77-81 the AF_PACKET address is two integers

*Fix.* Add a send example, `tx:send(frame, 0x88cc, ifindex)`, where the frame starts at the Ethernet header and the ethertype is in host byte order, and drop 'for receiving' from the summary.

#### MN-39 · `lib/socket/unix.lua:40` · inaccurate · low

unix:__call says the stored path is 'Reused automatically by `bind`, `connect`, `send`, `sendto`, and `receivefrom`'. `send` and `receivefrom` never read it.

*Evidence.* lib/socket/unix.lua:86 `return path and self.socket:send(msg, path) or self.socket:send(msg)` (no self.path); lib/socket/unix.lua:156-158 `function unix.dgram:receivefrom(len, flags) return self:receive(len, flags, true) end`

*Fix.* Change to 'Reused by `bind`, `connect` and `dgram:sendto` when no explicit path is given'.

### Tracing, device, eBPF, filesystem and data-structure modules

#### MS-01 · `lib/luarcu.c:284` · inaccurate · high

`map` is documented under `@type rcu_table` with no `@within rcu`, so the generated page shows it as the method `rcu_table:map (callback)` and lists only `callback`. The `__index` and `__newindex` metamethods also show up as methods (`rcu_table:__index (key)`).

*Evidence.* lib/luarcu.c:316-319 registers map as a module function: `static const struct luaL_Reg luarcu_lib[] = { {"table", luarcu_table}, {"map", luarcu_map},`. The methods table at :322-327 holds only `__newindex`, `__index` and `__gc`. luarcu_map at :291 reads the table as argument 1: `luarcu_table_t *table = luarcu_checktable(L, 1);`. Following the page, `t:map(cb)` runs `__index(t, "map")`, which returns the stored value or nil, and the call fails. lib/lunatik/runner.lua:107 uses the right form: `rcu.map(env.runtimes, function (script)`.

*Fix.* Add `@within rcu` to the map block and a first `@tparam rcu_table t the table to walk`; add `@usage rcu.map(t, function (key, value) print(key, value) end)`. Describe `t[key]` and `t[key] = value` in the rcu_table type prose (or tag the metamethod blocks so LDoc does not render them as `rcu_table:__index`).

#### MS-02 · `lib/luasched.c:240` · inaccurate · high

The @usage says to call the kfunc with `char rt_key[] = "my_sched_handler.lua"; // Key matches the script name`, for a script started with `lunatik run my_sched_handler.lua hardirq`.

*Evidence.* lib/lunatik/runner.lua:27-28 strips the extension, `return (script:gsub("%.lua$", ""))`, and :60-65 registers the runtime as `env.runtimes[script] = runtime` under the trimmed name. lunatik_ebpf.h:34 looks the key up exactly: `luarcu_getobject(runtimes, key, keylen)`. The key "my_sched_handler.lua" finds no runtime, so no callback runs, and bpf_luasched_run still returns 0 with SCX_DSQ_GLOBAL (luasched.c:154-169). It fails silently.

*Fix.* Use `char rt_key[] = "my_sched_handler";` and state that the key is the script name as given to `lunatik run`, without `.lua` (a path such as "dir/script" keeps its directory), and that `key__sz` is `sizeof` the array, NUL included.

#### MS-03 · `lib/bpf/map.lua:253` · inaccurate · medium

`map_hash` (also returned by `map.array`) says "assigning `nil` deletes". On an array proxy that assignment raises.

*Evidence.* lib/bpf/map.lua:164-165: `if value == nil then state.map:delete(rawkey)`. lib/luabpf.c:192 calls `map->ops->map_delete_elem`, and linux v6.8: kernel/bpf/arraymap.c:392-394 is `static long array_map_delete_elem(...) { return -EINVAL; }`. luabpf_map_checkret (luabpf.c:71-72) throws on anything other than ENOENT/EEXIST.

*Fix.* Add to `map.array`: "Array elements always exist: every index below max_entries reads a value (zero-filled if never set), and assigning nil raises EINVAL; write a zero value instead."

#### MS-04 · `lib/luabpf.c:220` · missing · medium

`next` "Mirrors Lua's `next(t, key)`, so it can drive a generic `for` directly", and bpf.map says "`pairs` iterates". Neither says that when the key passed in is gone, a hash map restarts from its first key. Lua's `next` allows clearing fields during a traversal, so a reader carries that expectation over.

*Evidence.* linux v6.8: kernel/bpf/hashtab.c:855-858: `l = lookup_nulls_elem_raw(...); if (!l) goto find_first_elem;`. lib/luabpf.c:242 calls `map->ops->map_get_next_key(map, (void *)key, next_key)` directly, and lib/bpf/map.lua:127-134 builds `pairs` on it. Deleting the current key in the loop body, or a concurrent delete by the eBPF program, restarts the walk, and keys already visited come back.

*Fix.* On `next` and on bpf.map's `map_hash`: "On hash and LRU hash maps, a key no longer in the map makes `next` restart from the first key, so deleting entries during the walk (or concurrent deletes by eBPF) can revisit keys; collect keys first if the loop deletes."

#### MS-05 · `lib/luadevice.c:384` · missing · medium

The @raise of `device.new` names allocation, a missing `name` and percpu. It does not say that the runtime must be process context.

*Evidence.* lib/luadevice.c:418: `.opt = LUNATIK_OPT_SINGLE | LUNATIK_OPT_EXTERNAL,` (no IRQ bit). :440: `lunatik_setruntime(L, device, luadev);` calls `lunatik_checkruntime` with that opt and raises `runtime context mismatch` in a softirq or hardirq runtime (lunatik.h:199-204, :208).

*Fix.* Add to @raise: "`'device': process-context class in interrupt-context runtime` in a softirq or hardirq runtime (run it in process context, the default of `lunatik run`)". Say in the module doc that file operations run on the calling task and may sleep.

#### MS-06 · `lib/luadevice.c:393` · inaccurate · medium

The @usage read callback is `return data:sub(1, len), off + #data`. It ignores the offset, so it never returns an empty string and `cat /dev/my_lua_device` never reaches EOF.

*Evidence.* lib/luadevice.c:167-176: `lbuf = lua_tolstring(L, -2, &llen); llen = min(ctx->len, llen); ... ctx->ret = (ssize_t)llen;`. The read returns however many bytes the string has, and returns 0 (EOF) only for an empty string or nil. The example string is never empty. The inline anonymous callback also goes against the Lua style rule on named callbacks.

*Fix.* Use a named local: `local function read(drv, len, off) local data = "Hello from " .. drv.name .. "!\n" return data:sub(off + 1, off + len) end` and `read = read` in the driver table. Document that an empty string or nil signals EOF.

#### MS-07 · `lib/luahid.c:277` · unclear · medium

`@function register` follows `@type hid_driver` with no `@within hid`, so the page shows `hid_driver:register (opts)` as a method. The module doc is one line and has no @usage.

*Evidence.* lib/luahid.c:61-64: `static const luaL_Reg luahid_lib[] = { {"register", luahid_register},`. The class methods at :66-69 hold only `__gc`. `hid_driver:register(t)` would pass a table that is not the driver.

*Fix.* Add `@within hid` to register. Expand the module doc: a HID driver written in Lua matching devices by id_table, able to fix report descriptors and rewrite raw reports, softirq only, with pointers to examples/gesture and examples/xiaomi.

#### MS-08 · `lib/luahid.c:278` · missing · medium

`register` documents `opts` as only `name` and `id_table`. The callbacks the driver table carries are not documented anywhere: `probe`, `report_fixup`, `raw_event`, their arguments, the table fields they receive, and what their returns and errors do. How to unregister a driver is not documented either.

*Evidence.* lib/luahid.c:189 looks up the callback by name on the registered table: `lunatik_optcfunction(L, -1, ctx->cb, lunatik_nop);`. The call is `ops.cb(hid, args)` (:195). probe gets the id table with driver_data (:205). report_fixup gets the hdev table and a data object over the report descriptor (:229-231). raw_event gets hdev, report and data (:257-260). hdev fields are bus/group/vendor/product/version/name (:141-146) and report fields are id/type/size/application/maxfield (:148-156). Return values are ignored (:119 `ctx->ret = 0;`). A raising callback gives -ECANCELED, which fails probe (:196, :217). The hid class has no stop method (:66-69), so the driver lives until the runtime stops. examples/xiaomi/driver.lua:61 names the data argument `report` because nothing documents the order.

*Fix.* Document the driver table: `name`, `id_table`, `probe(driver, id)`, `report_fixup(driver, hdev, rdesc)` (rdesc a `data` over the descriptor, edited in place, fixed size, valid only during the call) and `raw_event(driver, hdev, report, raw)` (raw a `data` over the report, editable in place). List the hdev fields (bus, group, vendor, product, version, name) and report fields (id, type, size, application, maxfield). State that returns are ignored, that an error fails probe with ECANCELED and makes the HID core drop that report in raw_event, and that the driver stays registered until the runtime stops. Add a @usage and point to examples/gesture and examples/xiaomi.

#### MS-09 · `lib/luahid.c:281` · missing · medium

Nothing in the hid docs says which execution context `hid.register` needs. The @raise lists fields, id_table, registration and percpu only.

*Evidence.* lib/luahid.c:77: `.opt = LUNATIK_OPT_SOFTIRQ | LUNATIK_OPT_SINGLE,`. :301: `lunatik_setruntime(L, hid, hid);`, which expands (lunatik.h:208) to `lunatik_checkruntime((L), luahid_class.opt)` and raises `runtime context mismatch` unless the runtime is softirq. Only the example READMEs say it (examples/gesture/README.md:23 `sudo lunatik run examples/gesture/driver softirq`).

*Fix.* Module doc and @raise: "Must run in a softirq runtime (`lunatik run <script> softirq`); other contexts raise `runtime context mismatch`. The callbacks must not sleep."

#### MS-10 · `lib/luaprobe.c:291` · unclear · medium

`@function new` follows `@type probe` with no `@within`, so the page renders it as `probe:new (symbol, handlers)`, a method of the probe object. The module has no @usage showing the right call.

*Evidence.* lib/luaprobe.c:309-312 registers `new` as a module function: `static const luaL_Reg luaprobe_lib[] = { {"new", luaprobe_new},`. The methods table at :314-319 has no `new`. doc/modules/probe.html lists it under "Class probe" as `probe:new`. `probe:new(sym, h)` passes the module table as argument 1, and luaprobe_checkspec (:335) raises `string expected, got table`.

*Fix.* Add `@within probe` to the new block (as lib/luabpf.c does) and a module @usage, e.g. `local p = probe.new("do_sys_openat2", {pre = pre})` with `pre` a named local function, run with `lunatik run <script> hardirq`.

#### MS-11 · `lib/luaprobe.c:304` · missing · medium

Neither the probe module doc ("kprobes interface.") nor `probe.new` says that the script must run in a hardirq runtime. The @raise names registration, percpu duplicates and "after module load" only.

*Evidence.* lib/luaprobe.c:375: `lunatik_object_t *runtime = lunatik_checkruntime(L, LUNATIK_OPT_HARDIRQ);`. It raises `runtime context mismatch` (lunatik.h:193, :203-204) for a default `lunatik run script` (process) or a softirq runtime. Only doc/guide/02-running-scripts.md:47 says it ("kprobes in hardirq").

*Fix.* Module doc: "Handlers run in hardirq context: run the script with `lunatik run <script> hardirq`; handlers must not sleep." Add "`runtime context mismatch` unless the runtime is hardirq" to new's @raise.

#### MS-12 · `lib/luarcu.c:10` · missing · medium

"values can be booleans, integers, lunatik objects, or `nil`". Many lunatik objects are refused, and so are strings, but neither is stated.

*Evidence.* lunatik_val.c:20-21: `case LUA_TUSERDATA: value->object = lunatik_checkshareable(L, ix);`. lunatik.h:375-376: `if (lunatik_issingle(object->opt)) luaL_argerror(L, ix, LUNATIK_ERR_SINGLE);` ("cannot share SINGLE object"). Other types reach lunatik_val.c:24 `luaL_argerror(L, ix, "unsupported type");`. SINGLE classes include device, probe, fsnotify and hid (luadevice.c:418, luaprobe.c:327, luafsnotify.c:752, luahid.c:77).

*Fix.* "Values can be booleans, integers, or shareable lunatik objects; SINGLE objects (device, probe, hid, ...) raise `cannot share SINGLE object`, and strings and tables raise `unsupported type`. Reading an object returns a clone that shares the same kernel object; a process-context object read from a softirq or hardirq runtime raises `process-context class in interrupt-context runtime`."

#### MS-13 · `lib/luasched.c:16` · missing · medium

"Needs 6.12 and later, with `CONFIG_SCHED_CLASS_EXT`." The doc does not say what happens without it, and does not state the BTF build requirement for the kfunc.

*Evidence.* lib/luasched.c:271-276: without CONFIG_SCHED_CLASS_EXT the module registers an empty lib (`static const luaL_Reg luasched_lib[] = { {NULL, NULL} };`), so `require("sched")` succeeds and `sched.attach` is nil. :268 `LUNATIK_EBPF_KFUNC_INIT(sched, BPF_PROG_TYPE_STRUCT_OPS);` registers a kfunc set, which needs module BTF. Makefile:212-213 `btf_install: cp /sys/kernel/btf/vmlinux ...`. Kernel btf.c:7973 prints `missing module BTF, cannot register kfuncs`.

*Fix.* Add: "Without `CONFIG_SCHED_CLASS_EXT` the module loads but exports nothing (`sched.attach` is nil). The kfunc needs module BTF: run `sudo make btf_install` before `make`; without it the kernel logs `missing module BTF, cannot register kfuncs` and an eBPF program calling `bpf_luasched_run` will not load. The eBPF side is a sched_ext `struct_ops` scheduler (see tests/sched/sched_pass.bpf.c)."

#### MS-14 · `lib/luasched.c:203` · inaccurate · medium

"The runtime invoking this function must be non-sleepable." and "@raise Error if the current runtime is sleepable". Both imply that a softirq runtime is accepted.

*Evidence.* lib/luasched.c:247: `lunatik_checkruntime(L, LUNATIK_OPT_HARDIRQ);`. lunatik.h:199-204: `if (lunatik_context(runtime->opt) != lunatik_context(opt)) luaL_error(L, LUNATIK_ERR_RUNTIME);`, and LUNATIK_ERR_RUNTIME is "runtime context mismatch" (lunatik.h:193). A softirq runtime is non-sleepable and still raises.

*Fix.* Replace "must be non-sleepable" with "must run in a hardirq runtime (`lunatik run <script> hardirq`)"; @raise: "`runtime context mismatch` unless the runtime is hardirq, or if internal setup fails".

#### MS-15 · `lib/luasyscall.c:11` · unclear · medium

The module suggests using the address with `probe`, but it does not say that the table entry is the arch syscall wrapper, whose only argument is `struct pt_regs *`. So `argument(n)` in a probe on that address does not return the syscall's arguments.

*Evidence.* linux v6.8: arch/arm64/include/asm/syscall_wrapper.h:54: `asmlinkage long __arm64_sys##name(const struct pt_regs *regs)`. arch/arm64/kernel/sys.c:58 fills `const syscall_fn_t sys_call_table[__NR_syscalls]` with these wrappers. lib/luaprobe.c:52 reads `regs_get_kernel_argument(regs, n)` of the probed function.

*Fix.* Add: "On architectures with syscall wrappers (arm64, x86_64), the entry is the wrapper `__<arch>_sys_<name>(const struct pt_regs *)`: a probe on it sees that pointer as `argument(0)`, not the syscall arguments."

#### MS-16 · `lib/luasyscall.c:28` · inaccurate · medium

"@treturn lightuserdata kernel address of the system call entry point, or `nil` if the number is invalid or the address cannot be determined."

*Evidence.* lib/luasyscall.c:39-40: `luaL_argcheck(L, nr >= 0 && nr < __NR_syscalls, 1, "out of bounds"); lua_pushlightuserdata(L, (void *)luasyscall_table[nr]);`. An invalid number raises, and a valid one always returns a lightuserdata. The function never returns nil.

*Fix.* @treturn lightuserdata "the `sys_call_table` entry for the number" (drop the nil clause); keep the @raise; add that the module fails to load (ENXIO) when `sys_call_table` cannot be looked up.

#### MS-17 · `Kconfig:104` · inaccurate · low

The LUNATIK_PROBE prompt says "Lunatik Probe (Kprobe/Kretprobe) Support", and LUNATIK_SYSCALL's help says "System call tracking and manipulation."

*Evidence.* lib/luaprobe.c registers only kprobes (:189 `register_kprobe(kp)`) and has no kretprobe. lib/luasyscall.c:36-42 only returns `sys_call_table` entries (`lua_pushlightuserdata(L, (void *)luasyscall_table[nr]);`).

*Fix.* "Lunatik Probe (kprobe) Support" and "System call table addresses, by number."

#### MS-18 · `lib/bpf/map.lua:200` · unclear · low

The bpf.map constructors say only "Error if the map cannot be opened". They inherit bpf's restriction that a softirq or hardirq runtime can open maps only while the script body runs, and nothing says so.

*Evidence.* lib/bpf/map.lua:176: `local handle = open(pathname)` calls bpf.hash and the like, which run `lunatik_checkarmed(L);` (lib/luabpf.c:393).

*Fix.* Add to the bpf.map module doc: "As in `bpf`, in a softirq or hardirq runtime the constructors run only in the script body; the proxies can then be used from handlers."

#### MS-19 · `lib/luabpf.c:6` · missing · low

The module doc does not state its requirements or where the flag constants live: CONFIG_BPF_SYSCALL, a mounted bpffs, maps pinned by bpftool or libbpf, and `update`/`push` flags from `linux.bpf` (ANY, NOEXIST, EXIST). It also does not say that the handles work from softirq and hardirq handlers.

*Evidence.* Kconfig:191-194: `config LUNATIK_BPF ... depends on BPF_SYSCALL`. autogen/specs.lua:46-48: `prefix = "BPF_", module = "bpf", ... include = { "ANY", "NOEXIST", "EXIST", ...`. lib/luabpf.c:380/387: `.opt = LUNATIK_OPT_EXTERNAL | LUNATIK_OPT_HARDIRQ`. :502 fails the module load with ENXIO when `bpf_map_iops` is not found.

*Fix.* Add to the module doc: "Needs CONFIG_BPF_SYSCALL and a map pinned on bpffs (e.g. `bpftool map pin`). Flags come from `require(\"linux.bpf\")` (`ANY`, `NOEXIST`, `EXIST`)." Drop the handler sentence from the fix, since `hash` already carries it.

#### MS-20 · `lib/luabpf.c:165` · unclear · low

`update`'s @raise says "if the operation is not permitted by the map". It also raises on a key or value of the wrong size, and when a hash map is full (E2BIG) under BPF_ANY. `lookup`, `delete`, `next`, `remove` and `push` raise on size mismatch as well, and no @raise says so.

*Evidence.* lib/luabpf.c:46-47: `if (size != expected) luaL_argerror(L, ix, lua_pushfstring(L, "invalid %s size", what));`. :71-72: every negative errno other than ENOENT/EEXIST is thrown, E2BIG from a full htab included.

*Fix.* On the key/value methods: "@raise `invalid key size`/`invalid value size` when a string does not match the map, or the kernel's errno (e.g. E2BIG when a hash map is full, EINVAL for bad flags)".

#### MS-21 · `lib/luabpf.c:416` · unclear · low

"if called after module load", here and in probe's new/stop/enable, reads as the kernel module's load. It means the script body has returned (the runtime is armed), which is what `lunatik_checkarmed` tests.

*Evidence.* lunatik.h:225-228: `static inline void lunatik_checkarmed(lua_State *L) { if (unlikely(lunatik_cannotsleep(L, lunatik_isready(lunatik_toruntime(L))))) luaL_error(L, LUNATIK_ERR_ARMED); }`. LUNATIK_ERR_ARMED is "not allowed after module load" (lunatik.h:194). luaprobe.c:242, :262 and :368 call the same check.

*Fix.* Keep the message's words in @raise and add "(the script body has returned and the runtime is armed)"; define the term once in doc/guide/02-running-scripts.md.

#### MS-22 · `lib/luadevice.c:348` · unclear · low

`@function new` follows `@type device` with no `@within device`, so the page shows `device:new (driver)` as a method of the device object.

*Evidence.* lib/luadevice.c:401-404: `static const luaL_Reg luadevice_lib[] = { {"new", luadevice_new},`. The methods table at :406-410 has only `__gc` and `stop`. The @usage (:398) uses the right `device.new(my_driver)`.

*Fix.* Add `@within device` to the new block.

#### MS-23 · `lib/luadevice.c:377` · inaccurate · low

"`release` (function): Callback for the `release(2)` system call". There is no release(2). The doc also lists `mode` under "callback functions" and uses `@treturn userdata` instead of the device type.

*Evidence.* lib/luadevice.c:285: `.release = luadevice_fop_release` is the file_operations release, which runs on the last close(2) of an open file. :449 `lunatik_optinteger(L, 1, luadev, mode, 0);` reads mode as an integer field.

*Fix.* "`release`: runs when the last reference to an open file is closed (the final close(2))"; move `mode` out of the callback list into a fields list; `@treturn device`.

#### MS-24 · `lib/luafsnotify.c:9` · unclear · low

"Event masks are the `linux.fs` bits", but the generated linux.fs page lists no names. A reader cannot find which bits exist (OPEN, MODIFY, EVENT_ON_CHILD, OPEN_PERM, ACCESS_PERM, OPEN_EXEC_PERM) or which of them are permission events.

*Evidence.* autogen/ldoc.lua:7-11: the stubs exist because "The real autogen output ... only exists after a kernel build", so the site renders them without values. doc/modules/linux.fs.html shows only "Mirrors FS_* defines in <linux/fsnotify_backend.h>". lib/luafsnotify.c:696-697 gates on `ALL_FSNOTIFY_PERM_EVENTS`.

*Fix.* In the fsnotify module doc, list the bits a script uses (names without the `FS_` prefix) and mark OPEN_PERM, ACCESS_PERM and OPEN_EXEC_PERM as permission events. Cross-cutting: have autogen/ldoc.lua emit each spec's `include` names from autogen/specs.lua into the linux.* stubs.

#### MS-25 · `lib/luaprobe.c:6` · unclear · low

The module doc is one line, "kprobes interface." It gives no purpose, no usage and no handler semantics. It does not say what `dump` does, that the `pre` handler's return value is ignored (a handler cannot skip the probed function), that handlers must not sleep, or how to obtain an address for the lightuserdata form.

*Evidence.* lib/luaprobe.c:39: `luaprobe_showregs(regs);` (show_regs, found at load by `lunatik_lookup("show_regs")` at :392). :119-121: the pre handler always returns 0. :332-333 accepts a lightuserdata address. syscall.address and syscall.table produce such addresses (examples/systrack/probe.lua:6).

*Fix.* Expand the module doc: kprobes on a kernel symbol or address; handlers run in hardirq and cannot sleep; `dump()` prints the probed CPU's registers to the kernel log; handler returns are ignored (a probe cannot skip the function); addresses come from `syscall.address`, `syscall.table` or `linux.lookup`. Point to examples/systrack and examples/dropreason and add a @usage.

#### MS-26 · `lib/luarcu.c:204` · unclear · low

"@tparam string key up to `LUARCU_MAXKEY` bytes, exclusive" names a C macro that the Lua reader cannot see. Its value is not given anywhere in the docs.

*Evidence.* lib/luarcu.h:11: `#define LUARCU_MAXKEY (LUAL_BUFFERSIZE)`. lunatik_conf.h:32: `#define LUAL_BUFFERSIZE (256)`. lib/luarcu.c:213: `lunatik_checkbounds(L, 2, keylen, 0, LUARCU_MAXKEY - 1);`.

*Fix.* "keys up to 255 bytes; longer keys raise `out of bounds`". In rcu.table, replace `LUARCU_MAXSIZE` with prose ("bounded by what the allocator can serve").

#### MS-27 · `lib/luarcu.c:280` · unclear · low

`map` says "the callback may sleep", which holds only in a process-context runtime; the rcu class is softirq and map is callable from IRQ runtimes, where the callback runs in the handler's context.

*Evidence.* luarcu.c:280-282 states the SRCU walk lets the callback sleep; the class opt is LUNATIK_OPT_SOFTIRQ (luarcu.c:335), so map is reachable from softirq/hardirq handlers, where lunatik_cannotsleep applies to anything the callback calls.

*Fix.* "the walk itself allows the callback to sleep (SRCU); whether it may is the runtime's context, as for any code in a softirq or hardirq handler".

#### MS-28 · `lib/luasched.c:59` · missing · low

`sched_ctx:task` returns a task object, but the doc does not say that this one object is reused for every callback and cleared afterwards. It also does not say that `sched.attach` replaces a previous callback.

*Evidence.* lib/luasched.c:66: `lunatik_getregistry(L, ctx->task_obj);` returns the same object each time. :120 `luatask_clear(lctx->task_obj);` runs after every callback, so a kept task raises on its next method. :249: `luasched_detach(L); /* re-attaching replaces the previous callback */`.

*Fix.* On `task`: "The same task object is reused for every callback: it is valid only during the callback that returned it; later it raises, or reads the task of the callback then running." On `attach`: "Calling it again replaces the previous callback."

#### MS-29 · `lib/luasched.c:206` · unclear · low

The kfunc signature is written inline in backticks, and LDoc's markdown turns its asterisks into emphasis. The rendered page shows `const char <em>key, ... struct task_struct </em>task_struct` with the pointer stars missing. The prose also names `key_sz` where the parameter is `key__sz`, and says `const char *` where the code has `char *`.

*Evidence.* doc/modules/sched.html:268: `<code>int bpf_luasched_run(const char <em>key, size_t key__sz, struct task_struct </em>task_struct, struct task_class *cls)</code>`. lib/luasched.c:152: `__bpf_kfunc int bpf_luasched_run(char *key, size_t key__sz, struct task_struct *task, struct task_class *cls)`.

*Fix.* Put the BPF-side declaration in an indented code block, copied from tests/sched/sched_pass.bpf.c:21 (`extern int bpf_luasched_run(const char *key, size_t key__sz, struct task_struct *task, struct task_class *cls) __ksym;`); name the parameter `key__sz`; document the return (0 once `cls` is filled, whether or not a callback ran; -1 when `cls` is NULL).

#### MS-30 · `lib/luasched.c:208` · broken-link · low

The key example names "examples/workload/workload", a script the tree does not have. No sched_ext example exists to follow.

*Evidence.* `ls examples` lists common cpuexporter dnsblock dnsdoctor dropreason echod execguard filter fsmonitor gesture ifquarantine keylocker linkflap lldpd netfailover shared sniclassify spyglass systrack tap tcpreject xiaomi. There is no `workload` directory, and grep finds no `bpf_luasched_run` caller under examples/.

*Fix.* Use a neutral key such as "sched/policy" (script path without `.lua`) and point to tests/sched/sched_pass.bpf.c and tests/sched/pass.lua as the worked pair, or add a sched_ext example.

#### MS-31 · `lib/luaset.c:185` · unclear · low

`new` and `labeled` follow `@type set` and `@type set.labeled` with no `@within set`, so the page shows `set:new (strings)` and `set.labeled:labeled (t)`. `__len` shows under module "Functions" as `__len ()`.

*Evidence.* lib/luaset.c:358-362: `static const luaL_Reg luaset_lib[] = { {"new", luaset_new}, {"labeled", luaset_labeled},`. `__len` is a metamethod of both classes (:366, :373). `set:new(t)` would pass the module table as the member array.

*Fix.* Add `@within set` to new and labeled; document `#s` in each type's prose instead of a module-level `__len` function.

#### MS-32 · `lib/lunatik/runner.lua:48` · inaccurate · low

`runner.run` documents `context` as "`\"process\"` (default) or `\"softirq\"` (for netfilter/XDP hooks)", leaving out `hardirq`; `runner.spawn` (:66-72) takes `context` and `ispercpu` and documents neither.

*Evidence.* runner.lua:59-66 passes `context` straight to lunatik.runtime/lunatik.percpu; bin/lunatik:304 accepts process, softirq and hardirq; doc/guide/02-running-scripts.md:28 documents hardirq for kprobes. runner.lua:74 `function runner.spawn(script, context, ispercpu)` refuses ispercpu (:76-78).

*Fix.* `@tparam[opt] string context` "`process` (default), `softirq` (netfilter, XDP) or `hardirq` (kprobes)"; on spawn add `@tparam[opt] string context` and `@tparam[opt] boolean ispercpu` "refused: spawn does not support percpu scripts".

### Examples and tests README

#### E-01 · `examples/cpuexporter/README.md:3` · inaccurate · medium

'expose using OpenMetrics text format'

*Evidence.* examples/cpuexporter/daemon.lua:95 `local ts_ms = linux.time() // 1000  -- convert nanoseconds to milliseconds` gives microseconds, since lib/lualinux.c:142 documents `linux.time` as 'current time in nanoseconds'; the README's own sample `1764094519529162` has 16 digits. OpenMetrics timestamps are seconds and the exposition must end with `# EOF`, which the daemon never sends. daemon.lua:144 answers HTTP with `Content-Type: text/plain; version=0.0.4` (Prometheus text format, where timestamps are milliseconds).

*Fix.* Describe the output as 'Prometheus text exposition format (version 0.0.4)', and also change the wording in doc/guide/05-examples.md:34. The timestamp is a code defect: fix it separately to `linux.time() // 1000000` (milliseconds). Document the HTTP mode, a `GET /metrics` on the socket, reachable through e.g. `socat TCP-LISTEN:9100,fork ABSTRACT-CONNECT:cpuexporter`. Add `sudo lunatik stop examples/cpuexporter/daemon`.

#### E-02 · `examples/dnsblock/README.md:4` · inaccurate · medium

'This script drops any outbound DNS packet with question matching the blacklist'

*Evidence.* examples/dnsblock/nf_dnsblock.lua:69-73 always parses an IPv4 header (`pkt:getuint8(9)`, `ihl * 4`) while registering `pf = family.INET` (nf_dnsblock.lua:79). The kernel registers an INET hook for IPv6 too (net/netfilter/core.c:566-571), so IPv6 queries are read as if IPv4 and pass. The match is a Lua pattern over the wire-format name (common.lua:29 `string.find(name, v)`), so `github.com` also matches any name that contains `github` followed by one byte and then `com`.

*Fix.* Change to 'drops locally generated IPv4 UDP DNS queries whose question name contains a blacklisted domain (default `github.com` and `gitlab.com`, set in `common.lua`; the entries are Lua patterns)'. Add that IPv6, DNS over TCP and forwarded queries are not covered.

#### E-03 · `examples/dnsdoctor/README.md:11` · missing · medium

`examples/dnsdoctor/setup.sh  # sets up the environment` is followed at once by `dig lunatik.com` and `sudo lunatik run ...`, as if setup returned.

*Evidence.* examples/dnsdoctor/setup.sh:57 `sudo ip netns exec ns1 .venv/bin/dnserver --no-upstream zones.toml` is the last line and runs the DNS server in the foreground, so the script never returns; setup.sh:30-32 `python -m venv .venv` / `pip install dnserver` need a `python` binary and network access; setup.sh:36-38 `sudo sed -i 's/nameserver/#nameserver/g' /etc/resolv.conf` and appends `nameserver 10.1.1.3`, taking the whole host's DNS until cleanup.sh runs

*Fix.* Write this against origin/master, which serves the zone with dnsmasq. Say that setup.sh keeps dnsmasq running in the foreground and the remaining steps go in a second terminal. Say it needs dnsmasq installed. Warn that it points /etc/resolv.conf at 10.1.1.3 (the old file is saved to /etc/resolv.conf.lunatik) until cleanup.sh restores it, so cleanup.sh must run even after a Ctrl-C.

#### E-04 · `examples/filter/README.md:33` · inaccurate · medium

The docker section runs `sudo bpftool prog load example/filter/https.o /sys/fs/bpf/lunatik_filter type xdp`.

*Evidence.* The object is at examples/filter/https.o (examples/filter/Makefile:4 `all: https.o`; Makefile:158 installs `examples/filter/https.o`), so `example/...` does not exist. The Usage block at README:24 already pinned `/sys/fs/bpf/lunatik_filter`, so a second load to the same pin path fails for a reader who runs both blocks.

*Fix.* Spell `examples/filter/https.o`. Present the docker block as the Usage block with `<ifname>` = `docker0`, not as a second load: `sudo bpftool net attach xdp pinned /sys/fs/bpf/lunatik_filter dev docker0`. Add a teardown: `sudo bpftool net detach xdp dev <ifname>`, `sudo rm /sys/fs/bpf/lunatik_filter`, `sudo lunatik stop examples/filter/sni`.

#### E-05 · `examples/shared/README.md:14` · missing · medium

The usage spawns the daemon and connects with nc, and never says how to stop it or what stopping it needs.

*Evidence.* examples/shared/daemon.lua:142 `local request = session:receive(size)` is a blocking receive with no RCVTIMEO and no MSG_DONTWAIT; lib/luasocket.c:269 `int flags = luaL_optinteger(L, 3, 0);`, and it runs inside the thread body (daemon.lua:167 `pcall(handle, session)`). So `lunatik stop examples/shared/daemon` waits for as long as a client stays connected, and clients are served one at a time.

*Fix.* Add `sudo lunatik stop examples/shared/daemon  # returns once the client hangs up`. Add one sentence: the daemon serves one connection at a time, and a stop waits until that client disconnects. Also say that keys and values are alphanumeric (`%w+`), that `key=` with no value deletes the key, and that a request without a `key[=value]` line ends the session.

#### E-06 · `examples/sniclassify/README.md:20` · missing · medium

'Run the classifier and set up the HTB classes on an interface: sudo ./examples/sniclassify/setup.sh eth0'

*Evidence.* examples/sniclassify/setup.sh:13 `tc qdisc add dev "$IF" root handle 1: htb default 20` replaces the interface's root qdisc, with a 100mbit ceiling (setup.sh:14). setup.sh:22 `bpftool prog load "$DIR/classify.o" "$PIN"` loads the object from the source tree, so it needs bpftool and a prior `make ebpf` (clang), and never uses the copy `ebpf_install` puts under /usr/local/lib/bpf/lunatik.

*Fix.* Add: 'Needs clang and bpftool. setup.sh replaces the root qdisc of <iface> with a 100 mbit HTB and cleanup.sh deletes it, so use a test interface (a veth) rather than your uplink. Only IPv4 ClientHellos are classified.' Drop `sudo make ebpf_install` from the steps, or say that setup.sh loads the build-tree object.

#### E-07 · `examples/tcpreject/README.md:19` · missing · medium

`sudo examples/tcpreject/setup.sh  # sets up namespace, nft mark rule, and loads the hook` gives no warning about what enabling IPv6 forwarding does to the host.

*Evidence.* examples/tcpreject/setup.sh:36 `echo 1 > /proc/sys/net/ipv6/conf/all/forwarding`. linux v6.8: include/net/ipv6.h:537-543 `ipv6_accept_ra`: 'If forwarding is enabled, RA are not accepted unless the special hybrid mode (accept_ra=2) is enabled.' On a host that gets its IPv6 default route from router advertisements in the kernel (accept_ra=1), the RAs are ignored while the example is set up, and the route disappears when its lifetime runs out. This does not apply when a userspace daemon handles RAs, as systemd-networkd can.

*Fix.* Add to the caution for finding 2: while set up, the host stops accepting IPv6 router advertisements in the kernel (unless accept_ra=2), so a SLAAC-configured host can lose its IPv6 default route. Run the example on a test machine or VM.

#### E-08 · `examples/tcpreject/README.md:28` · missing · medium

`sudo examples/tcpreject/cleanup.sh` is presented as undoing the setup.

*Evidence.* examples/tcpreject/cleanup.sh:12-13 `echo 0 > /proc/sys/net/ipv4/ip_forward` / `echo 0 > /proc/sys/net/ipv6/conf/all/forwarding` turn forwarding off whatever it was before setup.sh:28-29 turned it on, so a host that forwarded before (a container or VM host) loses forwarding

*Fix.* Add a caution: setup.sh turns IPv4 and IPv6 forwarding on, and cleanup.sh turns both off rather than back to their previous values, so a host that forwarded before (a container or VM host) has to re-enable forwarding. The better fix is to have setup.sh save both values and cleanup.sh restore them.

#### E-09 · `doc/guide/05-examples.md:3` · missing · low

The index gives one line per example and nothing on how each one runs or what it needs; every example README starts with `sudo make examples_install`.

*Evidence.* Makefile:166-172 `examples_install` copies only the example .lua files, and the modules and CLI come from `install` (Makefile:218). The examples differ in context and verb: `run ... softirq` (dnsblock), `hardirq` (keylocker, dropreason), `spawn` (echod, shared, cpuexporter, lldpd), setup.sh (tcpreject, sniclassify). Several need tools (bpftool, clang, nft, dig/python) or change host state (ifquarantine denies interfaces, sniclassify replaces a root qdisc, tcpreject and dnsdoctor change forwarding and resolv.conf).

*Fix.* Add a table to the index: example, verb and context (`run`/`spawn`, `--context=`, `--percpu`), external requirements (bpftool, clang, dnsmasq, nft, CONFIG_KPROBES, CONFIG_VT, a HID device) and host impact (ifquarantine denies interfaces, sniclassify replaces a root qdisc, tcpreject changes forwarding, dnsdoctor rewrites resolv.conf). Replace `sudo make examples_install` in the READMEs with a note that they assume `sudo make install`.

#### E-10 · `doc/guide/05-examples.md:34` · inaccurate · low

`[cpuexporter]: CPU usage statistics in OpenMetrics text format on a UNIX socket.` and line 39 `[systrack]: counts every system call with kprobes.`

*Evidence.* This repeats findings 15 and 20 in the index. examples/cpuexporter/daemon.lua:144 answers with `Content-Type: text/plain; version=0.0.4` (Prometheus text), sends no `# EOF`, and gives microsecond timestamps (:95). examples/systrack/probe.lua:13,24 skip syscall entries that share an address.

*Fix.* Change the index lines together with the example READMEs: 'CPU usage statistics in the Prometheus text format on an abstract UNIX socket' and 'counts system calls with kprobes, one probe per unshared syscall entry point'.

#### E-11 · `examples/dnsblock/README.md:11` · unclear · low

The two `lunatik run` lines (plain softirq, and softirq percpu) are listed one after the other, as they are in examples/dnsdoctor/README.md:17-18.

*Evidence.* lib/lunatik/runner.lua:61-62 `if env.runtimes[script] then error(string.format("%s is already running", script), 0)`, so running both lines in order fails on the second

*Fix.* Write the two lines as alternatives, in the current syntax: 'run either `sudo lunatik run --context=softirq examples/dnsblock/nf_dnsblock` or, for one runtime per CPU, `sudo lunatik run --context=softirq --percpu examples/dnsblock/nf_dnsblock`'. Add `sudo lunatik stop examples/dnsblock/nf_dnsblock` and a test, e.g. `dig github.com` timing out. Do the same in examples/dnsdoctor/README.md:17-18.

#### E-12 · `examples/dnsdoctor/README.md:24` · unclear · low

Cleanup is `sudo lunatik unload`.

*Evidence.* bin/lunatik:85-92 `unload_modules` runs `lunatik.runner.shutdown()`, which stops every running script, and then removes every module. That is more than this example needs, and it touches whatever else is running.

*Fix.* Use `sudo lunatik stop examples/dnsdoctor/nf_dnsdoctor`. Say that the domain (`lunatik.com`), the rewritten address (`10.1.2.3`) and the client (`10.1.1.2`) are set in nf_dnsdoctor.lua (lines 30-37), not provided at run time.

#### E-13 · `examples/dropreason/README.md:23` · missing · low

Usage arms the kprobe with no stated kernel requirement.

*Evidence.* lib/luaprobe.c:43 `#ifdef CONFIG_HAVE_FUNCTION_ARG_ACCESS_API` decides whether the `argument` closure exists at all, and examples/dropreason/monitor.lua:63 calls `argument(REASON)`. probe needs CONFIG_KPROBES. tests/README.md already lists both for the matching test ('Skipped without CONFIG_KPROBES or CONFIG_HAVE_FUNCTION_ARG_ACCESS_API').

*Fix.* Add a line: 'Needs CONFIG_KPROBES on an architecture with CONFIG_HAVE_FUNCTION_ARG_ACCESS_API (x86_64 and arm64 have it). The trigger line is a bash redirection.'

#### E-14 · `examples/echod/README.md:10` · missing · low

Usage spawns the daemon and talks to it; nothing says how to stop it or how it is built.

*Evidence.* examples/echod/daemon.lua:33-34 starts a worker thread per connection (`lunatik.runtime("examples/" .. worker)`, `thread.run(...)`) that `lunatik list` does not show, and daemon.lua:40 `control:setbyte(1, 0) -- dead` ends them on stop; worker.lua:59 bounds each receive to 100 ms

*Fix.* Add `sudo lunatik stop examples/echod/daemon`. Add one sentence: the daemon listens on 127.0.0.1:1337 and hands each connection to a kernel thread running worker.lua, and the workers end within 100 ms of the stop.

#### E-15 · `examples/filter/README.md:7` · broken-link · low

`[blacklisted](sni.lua#L35)`

*Evidence.* examples/filter/sni.lua:35 is `ctx:action(action[verdict])`; the list is at sni.lua:16-18 `local blacklist = set{ "ebpf.io", }`

*Fix.* Link `sni.lua#L16`. Name the default entry, `ebpf.io`, in the prose, and say the match is on the exact server name.

#### E-16 · `examples/filter/README.md:11` · missing · low

'Usage requires `libbpf` and `bpftool` installed.'

*Evidence.* examples/filter/Makefile:7-10 `bpftool btf dump file /sys/kernel/btf/vmlinux format c > $@` and `clang -target bpf -Wall -O2 -c -g $<`, so the build also needs clang and the kernel's BTF at /sys/kernel/btf/vmlinux. https.c:24-36 parses the frame as Ethernet + IPv4 + TCP to port 443 with PSH set, so IPv6 HTTPS is not filtered.

*Fix.* Change to 'Requires clang, libbpf headers, bpftool and a kernel with BTF (/sys/kernel/btf/vmlinux).' Add: 'Only IPv4 TLS ClientHellos to port 443 are inspected.'

#### E-17 · `examples/filter/README.md:13` · outdated · low

'Come back to this repository, install and load the filter:' and `cd ${LUNATIK_DIR}/lunatik    # cf. above`

*Evidence.* Nothing above in this README defines LUNATIK_DIR or sends the reader elsewhere. The file was moved out of the guide page in a784de033 ('each description moves as it was into a README'), so 'cf. above' points at text that is not there.

*Fix.* Drop the 'Come back to this repository' sentence and the `cd` line, and start with 'From the root of the Lunatik checkout (see [getting started](../../doc/guide/01-getting-started.md)):'.

#### E-18 · `examples/gesture/README.md:4` · unclear · low

'implements a HID driver for QEMU USB Mouse (0627:0001)' and 'the following configuration can help you disable PS2 mouse & enable USB mouse'

*Evidence.* examples/gesture/driver.lua:46 `local x1 = raw:getint16(1)` and driver.lua:24 `(x0 >= 32767 and x1 <= 0)` decode a 16-bit absolute X coordinate that wraps at 32767. I found no relative-mouse decoding, and I did not check QEMU's source for which of its devices sends such reports. The XML shown only turns PS/2 off; it adds no USB input device.

*Fix.* Say that the snippet is libvirt domain XML, and add the USB input device the driver decodes. The 16-bit absolute X suggests `<input type='tablet' bus='usb'/>`; confirm against QEMU's dev-hid.c before writing it. Say that a drag means moving with the left button held. Fix 'protocal'. Add `sudo lunatik stop examples/gesture/driver`.

#### E-19 · `examples/keylocker/README.md:11` · missing · low

The keyboard notifier is described with no config requirement or input scope, and the same holds for examples/spyglass/README.md:10.

*Evidence.* lib/luanotifier.c:194 documents `keyboard` as 'Only available when the kernel is built with `CONFIG_VT`' (luanotifier.c:228 `#ifdef CONFIG_VT` around the entry). The chain sees keys that reach the VT keyboard handler, so input over ssh or a pty never reaches it.

*Fix.* Add to both READMEs: 'Needs CONFIG_VT. Only keys from a local keyboard reach the notifier, not input over ssh or a pty.' For keylocker, add how to recover without the sequence: `sudo lunatik stop examples/keylocker/notifier` from another session. For spyglass, add `sudo lunatik stop examples/spyglass/device`.

#### E-20 · `examples/lldpd/README.md:15` · inaccurate · low

`ip link add veth0 type veth peer name veth1` and the two `ip link set ... up` lines are shown without sudo, while every other line uses sudo.

*Evidence.* Creating and bringing up links needs CAP_NET_ADMIN. The daemon resolves the interface at load: examples/lldpd/daemon.lua:68 `local ifindex = linux.ifindex(config.interface)` with daemon.lua:20 `interface = "veth0"`

*Fix.* Prefix the three `ip link` lines with `sudo`. Add `sudo lunatik stop examples/lldpd/daemon` and `sudo ip link del veth0`. Say that the interface is `config.interface` in daemon.lua and that a frame goes out every 30 s (`tx_interval_ms`).

#### E-21 · `examples/netfailover/README.md:6` · unclear · low

'each change is announced on the `netfailover` family of a `netlink.channel`'

*Evidence.* examples/netfailover/reactor.lua:95 `channel:multicast(CMD, event)` sends a plain string payload (reactor.lua:94 `format("%s %s: %s", ...)`), not the attributes linkflap's subscriber.c decodes, and the README gives no way to receive it

*Fix.* Say that the payload is a text line such as `dummy0 down: backup route installed`, sent as the raw genl body of command 1 on the `netfailover` family's only multicast group, and printed to dmesg as `netfailover: dummy0 down: backup route installed`. Point to dmesg as the easiest thing to watch.

#### E-22 · `examples/shared/README.md:12` · inaccurate · low

Every example README starts with `sudo make examples_install  # installs examples`, as the only install step.

*Evidence.* Makefile:166-171 `examples_install` does `${RM} -r ${SCRIPTS_INSTALL_PATH}/examples` and copies only examples/*/*.lua. The modules, the CLI and lib/*.lua come from `install` (Makefile:218). AGENTS.md: 'Use `sudo make install`, not the partial `*_install` targets.' doc/guide/05-examples.md:4 already says `sudo make install` installs the examples. So all 21 READMEs contradict the index and the project rule, and on a fresh checkout the step leaves nothing to load the scripts with.

*Fix.* In every example README, replace `sudo make examples_install` with `sudo make install` (or with a note that the README assumes it has been run). Change all 21 in one commit, not in one README at a time.

#### E-23 · `examples/sniclassify/README.md:7` · broken-link · low

`[policy table](sni.lua#L26)`

*Evidence.* examples/sniclassify/sni.lua:26 is blank; the table is at sni.lua:18-21 `local policy = set.labeled{ ["netflix.com"] = TC_H_MAKE(1, 0x30), ["zoom.com"] = TC_H_MAKE(1, 0x10), }`

*Fix.* Link `sni.lua#L18`. Say that netflix.com and its subdomains go to class 1:30 (20 mbit, prio 3), zoom.com and its subdomains go to 1:10 (50 mbit, prio 1), and everything else goes to the HTB default 1:20.

#### E-24 · `examples/sniclassify/README.md:33` · unclear · low

Verify with `sudo tc filter show dev eth0`.

*Evidence.* The filter is attached on clsact egress (examples/sniclassify/setup.sh:23 `tc filter add dev "$IF" egress bpf da object-pinned "$PIN"`). In the kernel's dump, parent 0 means the root qdisc (net/sched/cls_api.c:2822-2823 `if (!parent) q = rtnl_dereference(dev->qdisc);`), and that is the HTB, which has no filters. I did not check iproute2's default parent in its source.

*Fix.* Use `sudo tc filter show dev eth0 egress`. Add a stimulus, `curl -so /dev/null https://zoom.com`, and the expected kernel log line `sniclassify: zoom.com 65552`.

#### E-25 · `examples/systrack/README.md:4` · inaccurate · low

'uses kprobes to count every system call on the running architecture'

*Evidence.* examples/systrack/probe.lua:51 `names[address] = names[address] == nil and symbol or false` and probe.lua:62 `if symbol then probe.new(...)`: an address that more than one table entry shares (aliases, sys_ni_syscall) gets no probe and is not counted

*Fix.* Change to 'counts each system call whose entry point no other syscall-table entry shares (aliases and the not-implemented stub are skipped)', and say it needs CONFIG_KPROBES. Change the same line in doc/guide/05-examples.md:39.

#### E-26 · `examples/tcpreject/README.md:22` · inaccurate · low

`ip netns exec tcpreject curl --connect-timeout 2 https://8.8.8.8` (and the IPv6 line 25) are shown without sudo.

*Evidence.* examples/tcpreject/setup.sh:15 `ip netns add $NETNS` creates a root-owned namespace; entering it with `ip netns exec` needs CAP_SYS_ADMIN (setns), so as written the command fails for a normal user

*Fix.* Prefix both test commands in the README, and the two echo lines in setup.sh, with `sudo`. Say that the host needs a default route for each family, because a packet with no route is never forwarded and the FORWARD hook never sees it.

#### E-27 · `examples/xiaomi/README.md:14` · unclear · low

'Then insert the Xiaomi Silent Mouse with bluetooth mode on and it should work properly.'

*Evidence.* The kernel carries its own driver for the device (linux v6.8: drivers/hid/hid-xiaomi.c:64 `xiaomi_report_fixup`, hid-ids.h:1413 `USB_DEVICE_ID_MI_SILENT_MOUSE 0x5014`), built as a module on this distro (CONFIG_HID_XIAOMI=m). Where that module binds first, the Lua driver never sees the device. examples/xiaomi/driver.lua:81 matches `bus = 0x05` (Bluetooth) only.

*Fix.* Add: 'The in-tree hid-xiaomi driver handles the same device. If it is loaded (`lsmod | grep hid_xiaomi`), unload it with `sudo modprobe -r hid-xiaomi` before running this one, or the Lua driver never binds. Only the Bluetooth mode (bus 0x05) is matched.' Add the stop line.

#### E-28 · `tests/README.md:8` · missing · low

Requirements: 'Lunatik installed: `sudo make install`' and 'Root privileges'.

*Evidence.* Suites skip or partly skip without external tools: bpftool (tests/bpf/run.sh `bpftool map show ... || skip`), clang (tests/sched/run.sh `command -v clang`), gcc (tests/socket/unix/abstract.sh:99), python3 (tests/examples/shared.sh:93), nsenter, iw, mac80211_hwsim, nft, conntrack, genl, setarch, and the module BTF from `make btf_install`

*Fix.* Add an 'Optional tools' list naming each tool and the suites that skip without it: bpftool, clang, gcc (userspace peers), genl, nft, nsenter, setarch, ss, taskset, tc, iw/mac80211_hwsim, lunatic. Also say that the eBPF suites need `sudo make btf_install` and linux-tools, so a reader can tell a skip caused by a missing package from a real one. Leave python3 out.

#### E-29 · `tests/README.md:68` · missing · low

The crypto section describes only `context`; the six algorithm tests the suite runs have no entry.

*Evidence.* tests/crypto/run.sh `TESTS="shash skcipher aead rng hkdf comp"`, and each runs as its own KTAP case (`ktap_pass "crypto/$t"`)

*Fix.* Add a bullet for each of shash, skcipher, aead, rng, hkdf and comp saying what it asserts (read from each .lua), and keep the comp skip note on the comp bullet.

#### E-30 · `tests/README.md:718` · unclear · low

'The post half of a hit had no coverage before: nothing in the tree registered a `post` handler.'

*Evidence.* This sentence tells history, which AGENTS.md ('Comments and documentation') keeps out of docs: 'Comments describe the present, not the history.'

*Fix.* Replace it with 'This is the only case that registers a `post` handler.'

## Gaps by reader journey

| Priority | Journey | Page | Contents |
|----------|---------|------|----------|
| high | newcomer, first 30 minutes | Tutorial: your first kernel script | A lesson sequence in the style of bpftrace's one-liners: `sudo lunatik -e 'return 42'`, then a script file in /lib/modules/lua, then run/list/stop, reading its print output in `dmesg`, seeing a load error and what it looks like, a character device (the passwd driver) read with head, then a softirq hook (a netfilter counter) with `run ... softirq`. Each step has a command, its expected output, and cleanup. |
| high | newcomer, first 30 minutes | Concepts: runtimes, contexts, objects (explanation plus glossary) | What a runtime is (one Lua state and its lock); script body vs callbacks; process/softirq/hardirq and what each forbids; 'armed' (the state after the script body returns, what LUNATIK_ERR_ARMED calls 'module load'); percpu sets; objects, classes, sharing (SINGLE, monitor, clone into another runtime); lunatik._ENV and rcu tables; spawn and kernel threads. Every other page links here on first use of a term. |
| high | newcomer, first 30 minutes | Troubleshooting | Symptom-to-fix table, with each error text given verbatim: 'Exec format error' after a kernel upgrade (vermagic; rebuild); 'missing module BTF, cannot register kfuncs' (make btf_install); bpftool missing (linux-tools); 'not allowed after module load'; 'process-context class in interrupt-context runtime'; 'runtime context mismatch'; '?:?:' errors from stripped chunks; `require` returning true (a stray file shadowing a module); a stop that hangs (a thread that does not poll shouldstop); where print and errors go (printk). |
| high | script author (hooks) | How-to: filter packets with netfilter | register() options with the linux.nf constants for pf/hooknum/priority; the callback's argument (skb) and its return value, the verdict: an error or an out-of-range value falls back to NF_ACCEPT (luanetfilter.c:100-106, documented nowhere); running in softirq, percpu, the conntrack mark; stopping; a complete minimal script, then links to dnsblock/dnsdoctor/tcpreject. |
| high | script author (hooks) | How-to: run Lua from XDP and TC eBPF programs | Prerequisites (make btf_install, linux-tools, bpftool), the bpf_luaxdp_run kfunc from the eBPF side, xdp.attach/ctx:action and the -1 'no verdict' result, tc classifier equivalents, building with make ebpf, loading with bpftool (not iproute2), attach/detach, softirq percpu run. |
| high | script author (hooks) | How-to: trace kernel functions with kprobes | probe.new with pre/post, argument(n) and its limits, dump, hardirq context, what may not be called from a handler (stop/enable raise), percpu probes, the counter-plus-device pattern. |
| high | script author | How-to: share state between runtimes | rcu tables published in lunatik._ENV, runner.run/stop, runtime:resume to pass objects, mailbox (fifo plus completion), what can and cannot cross (SINGLE objects, plain Lua values), why an rcu.table made in a percpu script body is not shared. |
| high | script author | How-to: write a kernel thread (spawn) | The required shape (return the body, poll thread.shouldstop, linux.schedule), bounded blocking calls (receive timeouts, MSG_DONTWAIT), why an unbounded receive makes the thread unstoppable, stopping. |
| high | script author | Module overview blocks (every lib module) | Each @module block gains purpose, context, kernel requirements, sharing/percpu behaviour, a complete @usage and a link to its how-to and example. The thinnest today: netfilter, probe, skb, byteorder, signal, cpu, task, syscall, darken, the netlink.* namespaces. |
| high | binding author (C API) | How-to: write a binding | Step by step from lib/luaskel.c: the class and its opt (context choice), the checker (LUNATIK_PRIVATECHECKER plus lunatik_argcheckclass), constructor error paths, LUNATIK_CLASSES/NEWLIB, Kbuild and install wiring, the config.ld entry and module doc, a test suite, running from a hook (lunatik_run plus lunatik_cpcall, and that a raise outside a protected call is a BUG()). |
| high | binding author (C API) | capi.md coverage of public helpers | Document, or declare internal, the lunatik.h symbols with no entry: lunatik_cannotsleep, lunatik_checkbounds, lunatik_pusherrname, lunatik_closeprivate, lunatik_checkclass, lunatik_checkfield, lunatik_checkalloc/checkzalloc, lunatik_checkshareable, lunatik_isirq/ishardirq/ispercpu predicates, lunatik_percpu, lunatik_newclass/newclasses/hasclass, lunatik_pushobject, lunatik_newpobject/checkpobject, lunatik_require, LUNATIK_OPT_IRQ and LUNATIK_OPT_PERCPU (lunatik.h:23-29). |
| high | operator (OpenWRT / distro) | How-to: install and deploy | One section per target: Debian/Ubuntu, Arch, Fedora (untested), OpenWRT feed (package names, kernel config, cross-compiling bytecode with `lunatic -e big\|little`), the kernel-upgrade hook (tools/debian_kernel_postinst_lunatik.sh), BTF and bpftool requirements, uninstall. Starting scripts at boot needs to be checked: I did not find an in-tree unit or init script. |
| high | accuracy (verified stale or wrong) | doc/capi.md | (1) The link 'present on Lunatik' points at github.com/luainkernel/lunatik#c-api; the README has no such heading, and the list of libraries lives in 04-lua.md. (2) The kref link kernel.org/doc/Documentation/kref.txt is stale: the file is Documentation/core-api/kref.rst (checked in the 6.8 tree). (3) The LUNATIK_CLASSES example uses the inverted version guard, `#if (LINUX_VERSION_CODE < KERNEL_VERSION(6, 15, 0))` around the legacy class, which AGENTS.md's C style rule names as the wrong shape. (4) The opt-flag list omits LUNATIK_OPT_IRQ and LUNATIK_OPT_PERCPU. |
| high | accuracy (verified stale or wrong) | examples/filter/README.md | `cd ${LUNATIK_DIR}/lunatik # cf. above` refers to text no longer on the page; `example/filter/https.o` (missing s) in the docker section; `[blacklisted](sni.lua#L35)` points at `ctx:action(action.PASS)`, but the blacklist is at line 16. |
| medium | script author | How-tos: devices, notifiers, filesystem events, sockets, netlink, crypto | One short how-to per facility, in the shape of the Aya chapters: what the hook is, the context, the kernel config, a complete script, and cleanup. Covers device (read/write callbacks), notifier (netdevice, keyboard, vt), fsnotify (permission events, marks, the CONFIG_FANOTIFY_ACCESS_PERMISSIONS fallback), socket server/client, netlink rt/genl/nl80211, crypto AEAD/shash, hid. |
| medium | script author | API reference index grouped by area | Replace the flat alphabetical module_list with groups: Runtime (lunatik, lunatik.runner, thread, mailbox), Packet hooks (netfilter, xdp, tc, skb), Sockets and netlink, Tracing (probe, syscall), Devices and input (device, hid, notifier), Filesystem (fsnotify), Shared data (rcu, set, fifo, data, completion), Crypto, Encoding (byteorder, struct, util, class), Kernel constants (linux.*). Each group gets a one-line purpose. |
| medium | script author | 04-lua.md completions | Where print and error output go (printk KERN_CONT, lunatik_conf.h:22-24); integer division and the remaining math functions; how require resolves (package.path, C modules already linked, pinning); what `lunatik._ENV` is; `_LUNATIK_VERSION`. |
| medium | binding author (C API) | Explanation: object model, locking and sharing | The object lifecycle (kref, release vs detach/stop), the monitor wrapper and why close is unwrapped, SINGLE/EXTERNAL, clone into another runtime, the registry pattern for per-hook objects (luanetfilter skb), lunatik_percpudata and why registrations arm before the percpu set exists, where a runtime fact lives (extra space vs registry). |
| medium | binding author (C API) | How-to: embed a runtime in your own kernel module | A complete module (init/exit, lunatik_runtime, lunatik_run from a file_operations callback, lunatik_stop) assembled from the fragments now split across capi.md entries, plus module dependencies and loading order. |
| medium | operator | Reference: supported kernels, architectures and kernel config per module | The 6.6 floor, which modules need which CONFIG_ (kprobes, fanotify permission events, BTF/kfuncs, sched_ext, nl80211), per-arch notes (probe argument access, IBT), and what each module does on a kernel without them (refuse vs degrade). |
| medium | operator | Explanation: security model | Root only, what /dev/lunatik exposes, what a script can do to the machine (hooks that cut the network, like ifquarantine), encrypted scripts with darken/lighten, safe practice (scratch mounts, watchdog). |
| medium | contributor | Contributing (expand 06-development) | Build targets (make, C=1, btf_install, ebpf, doc-site, BYTECODE), the test loop and the host lock, how the site is built (config.ld topics/files, autogen/ldoc.lua stubs, the template), the documentation templates below, where design notes go. |
| medium | accuracy (verified stale or wrong) | lib/luaxdp.c xdp.attach @usage | It says `lunatik run my_xdp_handler.lua softirq`, but the CLI takes the script name without .lua and resolves /lib/modules/lua/<script>.lua. |
| medium | accuracy (verified stale or wrong) | @raise vocabulary across lib/ | The error text is 'not allowed after module load' (LUNATIK_ERR_ARMED). @raise lines variously say 'if called after module load', 'Error if the current runtime is sleepable', and 'Error if called during module load'. The 'Error if' prefix is used in some modules and not others, and 'module load' (meaning the script body has returned) is defined nowhere a script author reads. |
| medium | accuracy (verified stale or wrong) | config.ld / util module | lib/util.lua declares `@module util` with documented functions, but it is not in config.ld, so it has no page on the site. |
| medium | accuracy (inconsistent, needs a decision) | install instructions across pages | All 21 example READMEs use `sudo make examples_install`, while 05-examples says `sudo make install` installs them, and AGENTS.md steers contributors away from partial targets. The Arch dependency list differs from the Debian one: no dwarves/libelf, and it adds build2. Whether Arch's `lua` package provides 5.5 was not verified. |
| medium | accuracy (coverage of commands) | tests/examples | Only `shared` has an example test; the command transcripts in the other 20 example READMEs are not exercised, so drift like the filter README's goes unseen. |
| low | contributor | Changelog or release notes | What changed per release, especially API reshapes (skb.attr became a class, notifier callback arguments). I found no CHANGELOG in the tree; whether GitHub releases carry notes is unverified. |
| low | accuracy (verified stale or wrong) | guide version strings and CLI list | 04-lua.md ('Lunatik 4.4 is based on') and the 01 REPL banner hardcode the version from lunatik.h LUNATIK_VERSION, so they drift on each release. In 02, the bullet for `run` omits `<script>`, which the usage block shows. |

