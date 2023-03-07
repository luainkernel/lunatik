#!/usr/bin/lua
--
-- Copyright (c) 2023 ring-0 Ltda.
--
-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files (the
-- "Software"), to deal in the Software without restriction, including
-- without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to
-- the following conditions:
--
-- The above copyright notice and this permission notice shall be
-- included in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
-- IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
-- CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
-- TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
-- SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
--

local lunatik = {
	copyright = "Lunatik 3.0 Copyright (C) 2023 ring-0 Ltda.",
	device = "/dev/lunatik"
}

function lunatik.prompt()
	io.write("> ")
	io.flush()
end

function lunatik.load(chunk)
	local loader <close> = io.open(lunatik.device, "w")
	loader:write(chunk)
end

function lunatik.result()
	local reader <close> = io.open(lunatik.device, "r")
	print(reader:read("a"))
end

function lunatik.dostring(chunk)
	lunatik.load(chunk)
	lunatik.result()
end

if #arg >= 1 then
	local chunk = arg[1] == '-c' and
		string.format('return string.dump(loadfile("%s"))', arg[2]) or
		string.format('dofile("%s")', arg[1])
	lunatik.dostring(chunk)
	os.exit()
end

print(lunatik.copyright)
lunatik.prompt()
for chunk in io.lines() do
	lunatik.dostring(chunk)
	lunatik.prompt()
end

