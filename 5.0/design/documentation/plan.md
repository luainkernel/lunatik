# Plan

## Current state

The site renders well since the README became its home page and the guide its topics. The content
does not yet match: [audit.md](audit.md) rates 104 units, 15 good, 60 adequate, 23 poor and 6
missing, and holds 206 findings against the code at `85d9a1c1c`, 15 of them high.

- **Wrong text where it matters most.** The build steps leave out `make btf_install`, without which
  xdp, tc and sched do not load; the usages of xdp, tc and sched key the runtime with a `.lua` name the
  runner never registers; `capi.md` calls `lunatik_toobject` NULL-safe while the macro dereferences.
- **Contracts only the code states.** Which context a call runs in and whether it sleeps, what a
  callback returns, what raises and with which text, what kernel and `CONFIG_` a module needs.
- **Missing kinds of page.** No tutorial, no how-to per hook, no concepts page on the site: the best
  explanation of execution contexts and the object model is in AGENTS.md, which the site does not show.
- **Pages that mix forms.** `02-running-scripts.md` is CLI reference, the explanation of contexts and a
  bytecode how-to at once; `capi.md` carries a tutorial split across its reference entries.

Symbol coverage is high: 197 of the 207 names the C bindings register have an `@function`.

## Phases

Each phase is a series of small pull requests, each one reviewable alone and naming the audit
findings it closes. The order follows one rule: wrong text is worse than missing text, so the text
that is there is corrected first, checks then keep it correct, and only then is it reorganized and
extended on a base that holds.

### Phase 0: defects in the code

The audit found the code wrong, not only its doc, in six places. Each is an issue, fixed in a pull
request of its own through the ordinary build and test cycle, and each fix updates the doc of what it
changes, closing the findings named beside it:

| Issue | Defect | Closes |
|-------|--------|--------|
| #1234 | `cpu.stats` reads past the online mask for an id at or past `nr_cpu_ids` | MC-01 |
| #1235 | `skb:data` sizes its view from the network header and runs past the head on a tc skb | MN-05 |
| #1236 | `skb:resize` of a non-linear skb warns in dmesg instead of trimming or raising | MN-11 |
| #1237 | a netfilter callback that returns no verdict drops the packet; it gets `NF_ACCEPT` | MN-02, MN-03 |
| #863 | `netfilter.register` from a hook sleeps under the runtime's lock | MN-04 |
| #1172 | `linux.schedule` has no context check (pull request #1194) | MC-02 |

This phase does not wait on the others.

### Phase 1: accuracy

Every other finding in `audit.md` is closed here, one pull request per area, each changing the text in
place: a wrong sentence corrected, a missing requirement or raise added, a broken link fixed, a short
section added where the fix is one.

| Pull request | Findings |
|--------------|----------|
| README and guide | G-01 to G-27 |
| C API | C-01 to C-32 |
| Core and utility modules, `lib/util.lua` into `config.ld` among them | MC-03 to MC-46 |
| Networking modules | MN-01, MN-06 to MN-10, MN-12 to MN-39 |
| Tracing, device, eBPF, filesystem and data-structure modules | MS-01 to MS-32 |
| Examples and the tests README, with `sudo make install` in every example | E-01 to E-30 |

A finding the text cannot fix because the code is the problem goes to an issue, as in phase 0,
and the pull request says so beside the identifier.

### Phase 2: conventions and checks

One harness pull request writes the templates of [conventions.md](conventions.md) into AGENTS.md and
the new-binding skill, settles decision 3 (LDoc `custom_tags` for Context and Requires), and adds the
checks conventions.md lists, each proved against a case that fails and one that passes. From here on
a change that drifts from its doc fails in CI instead of in a reader's hands.

### Phase 3: structure

Two pull requests that move text and write none:

1. The guide splits into the four forms: Tutorial, How-to, Concepts, Reference. `02-running-scripts.md`
   becomes the CLI reference, the contexts go to a concepts page (with AGENTS.md pointing there,
   decision 4), and the bytecode section becomes a how-to. The site's menu groups topics by form.
2. The API reference index groups the modules by area instead of alphabetically: runtime, packet hooks,
   sockets and netlink, tracing, devices and input, filesystem, shared data, crypto, and the `linux.*`
   constants; a glossary page defines runtime, context, armed, percpu set, object, class, SINGLE,
   `lunatik._ENV` and hook, and each page links a term on first use.

### Phase 4: new content

In the order the reader needs them, one pull request each:

1. Tutorial, "Your first kernel script": the REPL, a script file in `/lib/modules/lua`, run, list and
   stop, reading its `print` in dmesg, what a load error looks like, the `passwd` device.
2. Concepts: runtimes, execution contexts, the script body and its callbacks, armed, objects and
   sharing, drawing on AGENTS.md and `03-percpu.md`.
3. Troubleshooting: each error with its text as the kernel or the CLI prints it, and the fix.
4. How-to guides, one per hook in the shape of the Aya book (what the hook is, when it fires, the
   context, the kernel it needs, a complete script, cleanup): netfilter; XDP and TC; kprobes; kernel
   threads; sharing state between runtimes; devices, notifiers and fsnotify.
5. Install and deploy (Debian and Ubuntu, Arch, OpenWRT, cross-compiled bytecode, the kernel upgrade
   hook), write a binding (from `lib/luaskel.c`), embed a runtime in a kernel module, the kernel and
   `CONFIG_` matrix per module, and the security model.
6. References: the resources page grown into a bibliography of Lua in operating system kernels, every
   entry opened and its title, authors, venue and year read from the source: the project's own talks,
   papers, theses and posts (Netdev, the Lua Workshop, DLS, OOSC); the GSoC projects with their reports
   and posts; the BSD side, from Lua in the NetBSD kernel (`lua(4)`, `luactl`, NPF) to Lua in the
   FreeBSD loader; adjacent work such as ZFS channel programs; the academic papers that cite the work;
   and the press. A link that no longer resolves points to its archived copy.

The gaps by reader journey at the end of `audit.md` list what each page draws on.

### Phase 5: module pages

The module blocks rewritten to the template, one pull request per area, starting with the units rated
poor: netfilter, skb, probe, hid, sched, data, mailbox, lighten, crypto, the `linux.*` constant pages,
signal, `socket.raw` and `netlink.rt`; then those rated adequate.

### Phase 6: examples

The example READMEs to the template, with requirements, files, run, stop and clean up, and a warning
where an example can cut the host off; and the `examples` suite running each README's commands through
`tools/watchdog.sh`, asserting only that the script loads where an example needs hardware the host
lacks (hid, xiaomi, gesture), which its README says.

## Definition of done

- Every finding in `audit.md` is closed by a merged pull request that names it, or by an issue that
  holds it.
- The checks of phase 2 run in CI and pass on master.
- The guide has a tutorial, the how-to guides of phase 4, a concepts page, troubleshooting and the
  references, each in one form.
- No unit of `audit.md`'s coverage table is rated poor or missing on a re-audit.

## Non-goals

- Changing an API to make it easier to document. Where the audit found the code wrong, the fix is an
  issue of phase 0, argued on its own.
- A second documentation toolchain. The site stays LDoc with the template and stylesheet in
  `doc/style/`.
- Translating the documentation.

