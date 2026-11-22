# Conventions

What a page of each kind contains, the words the docs use for Lunatik's concepts, and the checks that
keep the docs true to the code. Phase 2 of [plan.md](plan.md) writes the templates into AGENTS.md and
the new-binding skill; until then this is where they are stated.

## Forms

The docs follow [Diátaxis](https://diataxis.fr/): a page is a tutorial, a how-to guide, a reference
or an explanation, and does not mix them. A reference entry does not walk the reader through a task;
a tutorial does not stop to explain; an explanation links to the reference instead of restating it.

## Module page

The module block (`@module`):

1. What a script does with the module, in one sentence with a verb: "Hook packets at a netfilter hook
   point and return a verdict", not "Lua interface to the Linux Netfilter framework".
2. **Context**: the runtime context the module requires, and where its callbacks run, in the shape of
   kernel-doc's `Context:` section ("process context, may sleep", "softirq, runs with the runtime's
   lock held").
3. **Requires**: the kernel beyond the 6.6 floor, the `CONFIG_` options, and the tools
   (`make btf_install`, bpftool), and what happens without them: the module refuses with an errno the
   script sees, or it loads and does nothing.
4. **Sharing**: whether its objects cross runtimes (SINGLE, monitor), and how it behaves in a percpu
   set (one shared registration, the callback reaching the runtime of the CPU it fires on).
5. `@usage`: a complete minimal script, with the `lunatik run [-c <context>] [-p] <script>` line
   that runs it.
6. `@see`: the how-to guide and the example that use the module.

A function block: the summary; `@tparam` and `@treturn`; a **Callback** paragraph whenever it takes a
callback, with the callback's arguments, what it returns, and what a raise or an out-of-range return
means; its context where it differs from the module's, such as "raises once armed"; `@raise` quoting
the error text as the code raises it, with no "Error if" prefix. A constructor carries `@within` the
module, so the generated page shows it as `module.new` and not as a method.

The `linux.*` constant pages keep one line and a link to the kernel header they mirror.

## Example README

`# name`, then:

1. What it does for the reader, in one sentence.
2. **Teaches**: the modules and hooks it uses, linked to their reference pages.
3. **Requires**: the context, the `CONFIG_` options, tools, and a warning where running it can cut the
   host off the network or lock its input.
4. **Files**: each script and its role.
5. **Run**: `sudo make install`, then setup, then numbered commands; the input and the expected output
   in separate blocks.
6. **Stop and clean up**: always stated, down to the umount and the bpftool detach.
7. **How it works**: at most two short paragraphs; a longer mechanism belongs on a concepts page.

## How-to guide

Titled "How to <goal>". What the reader gets; prerequisites (Lunatik installed, the context, the
`CONFIG_` options); numbered steps, one action each, each with a complete command or script; "Check it
works" with the expected output; "Clean up"; "When it fails", linking to troubleshooting; "Reference",
linking to the module pages. Every block runs as written.

## Tutorial

In the shape of bpftrace's one-liners: numbered lessons, each one command or one small script, its
output, and two or three sentences on what it showed. Everything runs on a stock host with no network
card or eBPF setup.

## Terminology

One word for one thing, across the CLI help, the guide, the LDoc blocks and the error messages, and
each term linked to the glossary on its first use in a page:

| Term | Meaning |
|------|---------|
| runtime | A Lua state and its lock, created by `lunatik run`, `lunatik spawn` or `lunatik.runtime` |
| script body | The chunk a runtime runs once when it is created, in process context |
| callback | A function the script hands a binding, which the binding calls later from a hook |
| context | What a runtime's code may do: process (may sleep), softirq or hardirq (may not) |
| armed | A runtime whose script body has returned; the error text for a call refused then is `not allowed after module load` |
| percpu set | One runtime per CPU id, from `lunatik run --percpu <script>` |
| object | A Lua value wrapping a kernel resource, of a class a binding defines |
| SINGLE | An object that cannot be handed to another runtime |
| `lunatik._ENV` | The `rcu` table every runtime shares, through which scripts exchange objects |
| binding | A kernel module under `lib/` that exposes a kernel facility as a Lua module |
| hook | A point in the kernel where a binding runs a callback: a netfilter hook, an XDP or TC program, a kprobe |

Voice: second person, present tense, active voice. AGENTS.md's rules for comments and pull requests
hold here too: no em dashes, no history words ("was", "no longer"), an API name quoted as it is.

## Checks

Phase 2 adds these to `tools/checks/`, each proved against a case that fails and one that passes:

1. **doc-coverage** (fails the run): every name in a `luaL_Reg` array other than a metamethod has an
   `@function` in its module, and every file under `lib/` or `lunatik_*.c` that carries `@module` is
   listed in `config.ld`.
2. **doc-commands** (fails the run): in the README, the guide, the example READMEs and the `@usage`
   blocks, every `lunatik run`, `spawn` or `stop` names a script that exists and carries no `.lua`, every
   `make <target>` exists in the Makefile, and every relative link and `#L` anchor resolves.
3. **doc-snippets** (fails the run): every Lua block in those files and every `@usage` parses with
   `lunatic -p`.
4. **raise-text** (annotates): the `luaL_error`, `LUNATIK_ERR_*` and `luaL_argcheck` messages a
   documented function raises appear quoted in its `@raise`.
5. **doc-version** (fails the run): a version the docs name equals `LUNATIK_VERSION`, or the docs stop
   naming it.
6. **module-summary** (annotates, in `module-conventions.sh`): the `@module` summary is a sentence with
   a verb, and a module that takes callbacks carries its context.

External links run through a link checker on a schedule rather than on every pull request.

