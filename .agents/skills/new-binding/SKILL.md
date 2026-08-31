---
name: new-binding
description: Create a new Lunatik kernel module binding (lib/luaX.c) with its build wiring, docs and tests. Use when adding a Lua binding for a kernel API or subsystem.
---

AGENTS.md rules everything here: rule 1 (verify in headers and `Module.symvers`), execution
contexts, the object model, C style, comments and LDoc, tests. This skill is the workflow order
and the wiring the file does not enumerate.

1. **Research first.** Read the kernel API's declaration under
   `/usr/src/linux-headers-$(uname -r)/include` and confirm every symbol is exported in
   `Module.symvers`. For anything context-sensitive (may it run in softirq? does teardown
   sleep?) find an in-tree precedent in the kernel source; a header signature is not evidence
   of context safety. Read the two closest existing bindings end to end and mirror the whole
   file: `lib/luasocket.c` (objects + try macros), `lib/luarcu.c` (registry + callbacks),
   `lib/luanetfilter.c` (per-hook skb registry), `lib/luadata.c` (shared data).
2. **Shape.** Sleeping cleanup (unregister_*, synchronize_*) only runs in process context:
   soft-stop convention — `stop()` clears the callback from the registry, the handler checks
   the registry and returns early, `release` does the real unregister at runtime teardown. A
   helper goes to `lunatik.h` only with two or more real users.
3. **Wire the build**, in alphabetical position in every list: `Kbuild`, `Kconfig`
   (`config LUNATIK_<NAME>`), `Makefile` (`LUNATIK_MODULES`), `config.ld`, the README module
   table.
4. **Docs and tests** per AGENTS.md; a suite under `tests/<name>/` (see the new-test skill).
5. **Verify** with the lunatik-cycle skill; grep every new symbol for a caller.

