# Proposed interface: `lunatikc`

This is a design proposal, not a specification. Names are open for review (`lunatikc` avoids
shadowing the distribution `luac`; `lunatik compile` as a CLI subcommand is a possible wrapper);
the constraints behind the behavior (`kernel-notes.md`) are not.

## Command line

```
lunatikc [-s] [-o output] [-n chunkname] [-e big|little] input.lua [input.lua ...]
```

| Option | Meaning | Default |
|--------|---------|---------|
| `-s` | strip debug information (`lua_dump` strip): no line numbers, local or upvalue names, no source name | off |
| `-o output` | output file; with several inputs, a directory | `<input>.luac` next to each input |
| `-n chunkname` | chunk name baked into the dump, as `lua_load` would receive it (`@path` or `=name`) | `@<input>` |
| `-e big\|little` | target byte order (phase 4) | host |

* Input is always parsed as **text** (`luaL_loadbufferx(..., "t")`); a binary input is an error.
* Exit status 0 only if every input compiled and was written; otherwise the first error goes to
  stderr as `lunatikc: <input>:<line>: <message>` and the status is 1. Nothing is written for a
  failed input.
* No `-l` listing and no `-p` parse-only in phase 1. `-p` is cheap to add (`-o /dev/null`);
  listing needs a fork of `luac.c`'s printer with the float cases removed and is not worth it
  until someone needs to read kernel opcodes.

Examples:

```sh
lunatikc examples/echod/daemon.lua                         # -> examples/echod/daemon.luac
lunatikc -s -n @/lib/modules/lua/net.lua -o /lib/modules/lua/net.lua lib/net.lua
lunatikc -s -o build/ lib/lunatik/*.lua                    # one .luac per input in build/
```

## Build and install

```sh
make                 # also builds bin/lunatikc with the host compiler
make install         # installs lunatikc next to lunatik (LUNATIK_INSTALL_PATH)
BYTECODE=1 make install   # phase 3: ships kernel Lua libs and examples as stripped chunks
```

`lunatikc` is built from the same `lua/` sources and `_KERNEL` configuration as `lunatik.ko`, so
its chunks always match the installed kernel module built from the same tree. Mixing a tool and a
module from different `lua/` revisions is caught by the chunk header only when the format
changes; keep them from the same build.

## Using the output

A chunk is installed **under the `.lua` name** and used exactly like source:

```sh
sudo cp hello.luac /lib/modules/lua/hello.lua
sudo lunatik run hello
```

`require("foo")` in the kernel resolves `/lib/modules/lua/foo.lua` through the same loader, so
libraries can be chunks too. `lunatik spawn` is no different.

## Kernel side

No new API. The only change in phase 1 is that `lunatik_conf.h` becomes host-includable: the
number configuration shared by the kernel and the tool stays at the top, the kernel-only part is
under `#ifdef __KERNEL__`. The kernel build sees the same macros with the same values.

Possible later knobs (not in phase 1; each is its own decision):

* a module parameter / Kconfig forcing text-only loads (`"t"`) — the parser as a sanity filter;
* `CONFIG_LUNATIK_BYTECODE_ONLY` — no parser in the kernel at all;
* a `"b"` option in `darken.run` for encrypted chunks.

