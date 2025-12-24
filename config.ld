-- LDoc configuration file for the Lunatik project
-- Place this file at the root of your project and run 'ldoc .'

-- The name of your project
project = 'Lunatik'

description = 'Lunatik is a framework for scripting the Linux kernel with Lua.'

-- The title for the generated documentation
title = 'Lunatik API Documentation'

-- Source files to document.
-- LDoc will recursively scan directories.
-- By manually specifying order, we ensure menu order.
file = {
	'./lib/luacompletion.c',
	'./lib/luacpu.c',
	'./lib/crypto/aead.lua',
	'./lib/luacrypto_comp.c',
	'./lib/luacrypto_rng.c',
	'./lib/luacrypto_shash.c',
	'./lib/luacrypto_skcipher.c',
	'./lib/luadata.c',
	'./lib/luadevice.c',
	'./lib/luafib.c',
	'./lib/luafifo.c',
	'./lib/luahid.c',
	'./lunatik_core.c',
	'./lib/lunatik/runner.lua',
	'./lib/lualinux.c',
	'./lib/mailbox.lua',
	'./lib/net.lua',
	'./lib/luanetfilter.h',
	'./lib/luanetfilter.c',
	'./lib/luanotifier.c',
	'./lib/luaprobe.c',
	'./lib/luarcu.c',
	'./lib/luasocket.c',
	'./lib/socket/inet.lua',
	'./lib/socket/unix.lua',
	'./lib/luasyscall.c',
	'./lib/syscall/table.lua',
	'./lib/luathread.c',
	'./lib/luaxdp.c',
	'./lib/luaxtable.c',
}

-- examples = "./examples"

-- The directory where LDoc will output the generated documentation.
dir = 'doc'

-- The output format. Common options: 'markdown', 'html'.
-- 'markdown' is good for GitHub pages or further processing.
-- 'html' generates a browsable website.
format = 'markdown'

-- For HTML output, you can specify a style.
-- style = '!fixed' -- A common built-in style
-- style = '!menu'  -- Another built-in style with a navigation menu
-- new_style = true -- Use with '!menu' for a more modern look

-- If you have a README.md file you'd like to use as the main page content:
readme = 'README.md'

boilerplate = true

-- Merge documentation for modules that might be split across multiple files
-- or have parts in C and Lua.
merge = true

-- Sort modules and functions alphabetically in the output.
sort = true

-- By default, LDoc only documents exported functions and tables.
-- Set to true to document everything, including local functions (usually not for API docs).
-- all = false -- This is the default

-- For more LDoc options, see: https://github.com/lunarmodules/LDoc

