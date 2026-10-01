-- LDoc configuration file for the Lunatik project
-- Place this file at the root of your project and run 'ldoc .'

-- The name of your project
project = 'Lunatik'

description = 'Lunatik is a framework for scripting the Linux kernel with Lua.'

-- The title for the generated documentation
title = 'Lunatik API Documentation'

-- Source files to document, listed by module name; LDoc scans directories
-- recursively and sort_modules keeps the menu in that order.
sort_modules = true
file = {
	'./lib/luabpf.c',
	'./lib/bpf/map.lua',
	'./lib/luabyteorder.c',
	'./lib/class.lua',
	'./lib/luacompletion.c',
	'./lib/luacpu.c',
	'./lib/luacrypto_core.c',
	'./lib/crypto/hkdf.lua',
	'./lib/luacrypto_aead.c',
	'./lib/luacrypto_comp.c',
	'./lib/luacrypto_rng.c',
	'./lib/luacrypto_shash.c',
	'./lib/luacrypto_skcipher.c',
	'./lib/luadarken.c',
	'./lib/luadata.c',
	'./lib/luadevice.c',
	'./lib/luafifo.c',
	'./lib/luafsnotify.c',
	'./lib/luahid.c',
	'./lib/lighten.lua',
	'./lib/lualinux.c',
	'./lib/linux',
	'./lunatik_core.c',
	'./lunatik_percpu.c',
	'./lib/lunatik/runner.lua',
	'./lib/mailbox.lua',
	'./lib/net.lua',
	'./lib/luanetfilter.c',
	'./lib/netlink.lua',
	'./lib/luanetlink.c',
	'./lib/netlink/genl.lua',
	'./lib/netlink/message.lua',
	'./lib/netlink/nl80211.lua',
	'./lib/netlink/nl80211/ap.lua',
	'./lib/netlink/nl80211/interface.lua',
	'./lib/netlink/nl80211/station.lua',
	'./lib/netlink/nl80211/wiphy.lua',
	'./lib/netlink/rt.lua',
	'./lib/netlink/rt/addr.lua',
	'./lib/netlink/rt/link.lua',
	'./lib/netlink/rt/route.lua',
	'./lib/netlink/rt/rule.lua',
	'./lib/netlink/session.lua',
	'./lib/luanotifier.c',
	'./lib/luaprobe.c',
	'./lib/luarcu.c',
	'./lib/luascx.c',
	'./lib/luaset.c',
	'./lib/luasignal.c',
	'./lib/luaskb.c',
	'./lib/luasocket.c',
	'./lib/socket/inet.lua',
	'./lib/socket/raw.lua',
	'./lib/socket/unix.lua',
	'./lib/struct.lua',
	'./lib/luasyscall.c',
	'./lib/syscall/table.lua',
	'./lib/luatask.c',
	'./lib/luatc.c',
	'./lib/luathread.c',
	'./lib/util.lua',
	'./lib/luaxdp.c',
}

-- examples = "./examples"

-- The directory where LDoc will output the generated documentation.
dir = 'doc'

-- The markup of comments and topics: discount renders tables, which the built-in markdown leaves as text.
format = 'discount'

-- LDoc writes a backticked name out as <code> before discount runs, so SmartyPants reaches inside it.
local unsmart = {ndash = '--', mdash = '---', hellip = '...'}
postprocess_html = function(html)
	return (html:gsub('<code>(.-)</code>', function(code)
		return '<code>' .. code:gsub('&(%a+);', unsmart) .. '</code>'
	end))
end

style = './doc/style'
template = './doc/style'

-- The template renders README.md as the home page and the other topics as the guide.
topics = {
	'README.md',
	'./doc/guide/01-getting-started.md',
	'./doc/guide/02-running-scripts.md',
	'./doc/guide/03-percpu.md',
	'./doc/guide/04-lua.md',
	'./doc/guide/05-examples.md',
	'./doc/guide/06-development.md',
	'./doc/guide/07-resources.md',
	'./doc/capi.md',
}
use_markdown_titles = true

manual_url 'https://www.lua.org/manual/5.5/manual.html'

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

