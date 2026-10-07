--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Writes <dir>/search.js, the index the site's search box reads, from the pages LDoc generated
-- under <dir>: each module and class with its summary, each of their functions, and each section
-- of the guide.
--
-- Usage: lua doc/style/search.lua doc

local dir = assert(arg[1], "usage: search.lua <doc dir>")

local entities = {amp = "&", lt = "<", gt = ">", quot = '"', rsquo = "'", lsquo = "'", ldquo = '"', rdquo = '"', nbsp = " "}

local function text(html)
	local plain = html:gsub("<[^>]*>", ""):gsub("&(%a+);", function (name) return entities[name] or "" end)
	return (plain:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

local function read(path)
	local file <close> = assert(io.open(path))
	return file:read("a")
end

local function pages(sub)
	local list = {}
	local ls <close> = io.popen("ls '" .. dir .. "/" .. sub .. "' 2>/dev/null")
	for name in ls:lines() do
		if name:match("%.html$") then table.insert(list, name) end
	end
	return list
end

local index = {}

local function add(name, href, where)
	table.insert(index, string.format("[%q,%q,%q]", name, href, where))
end

for _, sub in ipairs({"modules", "classes"}) do
	for _, page in ipairs(pages(sub)) do
		local html = read(dir .. "/" .. sub .. "/" .. page)
		local module = page:gsub("%.html$", "")
		local lead = html:match('<p class="lead">(.-)</p>') or ""
		add(module, sub .. "/" .. page, (sub == "modules" and "Module" or "Class") .. " · " .. text(lead))
		for anchor, name, summary in html:gmatch('<td class="name"[^>]*><a href="#([^"]+)">(.-)</a></td>%s*<td class="summary">(.-)</td>') do
			add(text(name), sub .. "/" .. page .. "#" .. anchor, module .. " · " .. text(summary))
		end
	end
end

for _, page in ipairs(pages("topics")) do
	if page ~= "README.md.html" then
		local html = read(dir .. "/topics/" .. page)
		local title = text(html:match("<h1[^>]*>(.-)</h1>") or page)
		add(title, "topics/" .. page, "Guide")
		for level, id, heading in html:gmatch('<h([23]) id="([^"]+)">(.-)</h%1>') do
			add(text(heading), "topics/" .. page .. "#" .. id, "Guide · " .. title)
		end
	end
end

local out <close> = assert(io.open(dir .. "/search.js", "w"))
out:write("window.LUNATIK_SEARCH = [\n", table.concat(index, ",\n"), "\n];\n")

