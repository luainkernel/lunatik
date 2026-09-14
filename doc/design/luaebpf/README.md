# Lua as a source language for eBPF

Working documents for `luaebpf`: compiling a Lua function into an eBPF program that the verifier
checks and the kernel runs natively, in place of the C stub that today calls a kfunc to run Lua in
the kernel interpreter.

They exist so that a contributor, with or without an AI coding assistant, can pick the work up
without first re-deriving which loader can see the verifier log, which loops the verifier accepts,
and why the compiler runs on the host that runs the program.

| Document | What it is for |
|----------|----------------|
| [plan.md](plan.md) | Expected results, where we are, the decisions and their reasons, phases, sizing, non goals, risks, definition of done |
| [api.md](api.md) | What a Lua program that becomes eBPF looks like, how it is compiled, loaded and attached, how it reaches maps and the kernel Lua runtime, with worked examples |
| [kernel-notes.md](kernel-notes.md) | Verified kernel and toolchain facts the design rests on, cited at tags: verifier limits, program types, BTF, kfuncs, who may load a program, what is exported |
| [testing.md](testing.md) | Test strategy and the matrix: a compiler is tested by what it emits and by what the verifier accepts |

Start with `plan.md`. Read `kernel-notes.md` before writing the emitter or the loader: the first
two sections settle where the loader lives and why.

## Working on this

The repository conventions that apply to every change here (build, test, style, kernel context
rules, commit discipline) are in [AGENTS.md](../../../AGENTS.md) at the root of the repository.
Read it once before the first patch. If you use an AI assistant, point it at that file and at
`kernel-notes.md`.

Three things decide whether this work goes well:

1. **The loader is the `lunatik` CLI, over `bpf(2)`, on the machine that runs the program.** A
   kernel module can load a program through `kern_sys_bpf`, but that path returns no verifier log
   (the log buffer is a user pointer, and a kernel buffer fails the load), cannot resolve the
   tree's own kfuncs (no module BTF fd), cannot open a pinned map by path, and imports a symbol its
   maintainers namespaced against exactly this use. The CLI has all four. `kernel-notes.md`
   traces each one to a line.
2. **The compiler runs the kernel's own Lua.** `lunatikc` (#742) builds the `lua/` submodule with
   `-D_KERNEL` on the host: integer-only arithmetic, `/` as integer division, the 80-opcode set.
   The translator reads the bytecode of that build and folds constants with that arithmetic, so
   what it compiles is what the kernel would have interpreted. It does not run in the kernel.
3. **Refusing is the normal outcome, and it is explicit.** The subset is what the verifier can
   check: integers, booleans, counted loops, proxies over the context, the packet and maps, calls
   to functions the translator can see. Anything else is a compile error naming the Lua line, not
   a silent fallback into the interpreter. The call into the kernel Lua runtime through the
   existing kfunc is a construct the program writes on purpose, at the point it chooses.

## Status

These documents describe the design; they do not track progress. What is in flight, and how far
along each phase is, lives on the [Lua to eBPF board](https://github.com/orgs/luainkernel/projects/6).
Each phase is an issue there and lands as its own pull request.

