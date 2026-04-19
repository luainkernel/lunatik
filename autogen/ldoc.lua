--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Generate an LDoc stub from autogen/specs.lua.
--
-- The real autogen output (`autogen/linux/*.lua`) only exists after a
-- kernel build and its contents depend on the kernel version/arch. LDoc
-- runs in CI without a kernel build, so this stub provides the stable
-- API surface (sub-table names, description, provenance) that LDoc can
-- render independently of any build artefact.
--
-- The stub is emitted at `lib/linux.lua` with `@submodule linux`;
-- combined with `merge = true` in `config.ld`, LDoc folds its tables
-- into the `linux` module page (alongside what `lib/lualinux.c`
-- documents) instead of polluting the index with one page per group.
--
-- Gitignored, cleaned by `make clean`, and not copied by
-- `scripts_install` -- only `autogen/linux/*.lua` goes to the runtime
-- path at `/lib/modules/lua/linux/`.
--
-- @script autogen/ldoc
-- @usage lua5.4 autogen/ldoc.lua [<out-file>]

local OUT = arg[1] or "lib/linux.lua"
local SPECS = "autogen/specs.lua"

local specs = dofile(SPECS)

local function write_block(f, lines)
	f:write("---\n")
	for _, line in ipairs(lines) do f:write("-- ", line, "\n") end
	f:write("\n")
end

local f <close> = assert(io.open(OUT, "w"))
f:write("-- auto-generated LDoc stub (see autogen/ldoc.lua) -- do not edit\n\n")
write_block(f, { "@submodule linux" })

for _, s in ipairs(specs) do
	write_block(f, {
		s.desc or ("`%s*` from `<%s>`."):format(s.prefix, s.header),
		"Mirrors `" .. s.prefix .. "*` in `<" .. s.header .. ">`.",
		"@table " .. s.module,
	})
end

