--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Generate LDoc stubs from autogen/specs.lua.
--
-- The real autogen output (`autogen/linux/*.lua`) only exists after a
-- kernel build and its contents depend on the kernel version/arch. LDoc
-- runs in CI without a kernel build, so these stubs provide the stable
-- API surface (module names, grouping, description, provenance) that
-- LDoc can render independently of any build artefact.
--
-- Stubs live at `lib/linux/` because LDoc deduces module names from the
-- source path (stripping the `lib/` base) before honoring `@module`
-- tags; a file at `lib/linux/nf.lua` resolves to `linux.nf`, which is
-- what we want. They are gitignored, cleaned by `make clean`, and not
-- copied by `scripts_install` -- only `autogen/linux/*.lua` goes to the
-- runtime path at `/lib/modules/lua/linux/`.
--
-- @script autogen/ldoc
-- @usage lua5.4 autogen/ldoc.lua [<out-dir>]

local OUT = arg[1] or "lib/linux"
local SPECS = "autogen/specs.lua"

local specs = dofile(SPECS)

local tops, order = {}, {}
for _, spec in ipairs(specs) do
	local top = spec.module:match("^[^.]+")
	if not tops[top] then
		tops[top] = {}
		table.insert(order, top)
	end
	table.insert(tops[top], spec)
end

assert(os.execute("mkdir -p '" .. OUT .. "'"))

local function provenance(spec)
	return ("`%s*` constants from `<%s>`."):format(spec.prefix, spec.header)
end

local function doclines(spec, top)
	if spec.struct then
		return ("`%s` struct layouts."):format(top),
			("Layout descriptors (per-field offset/size/signedness) generated from "
				.. "`<%s>`; consume via `require(\"struct\")`."):format(spec.header)
	end
	return provenance(spec),
		("Mirrors `%s*` defines in `<%s>`."):format(spec.prefix, spec.header)
end

local function write_block(f, lines)
	f:write("---\n")
	for _, line in ipairs(lines) do f:write("-- ", line, "\n") end
	f:write("\n")
end

local HEADER = "-- auto-generated LDoc stub (see autogen/ldoc.lua) -- do not edit\n\n"

for _, top in ipairs(order) do
	local group = tops[top]
	local f <close> = assert(io.open(OUT .. "/" .. top .. ".lua", "w"))

	f:write(HEADER)
	write_block(f, {
		"Linux kernel constants exposed under `linux." .. top .. "`.",
		"Values are populated at build time from the kernel headers.",
		"@module linux." .. top,
	})
	f:write(("local %s = {}\n"):format(top))

	local seen = {}
	for _, s in ipairs(group) do
		if not seen[s.module] then
			seen[s.module] = true
			local name = s.module == top and "constants" or s.module:sub(#top + 2)
			local default, source = doclines(s, top)
			write_block(f, { s.desc or default, source, "@table " .. name })
			f:write(("%s.%s = {}\n"):format(top, name))
		end
	end

	f:write(("\nreturn %s\n\n"):format(top))
end

