--
-- SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
-- SPDX-FileCopyrightText: (c) 2025-2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

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
	'./common/class.lua',
	'./lib/luacompletion.c',
	'./lib/luacpu.c',
	'./lib/luacrypto_core.c',
	'./lib/crypto/hkdf.lua',
	'./lib/luacrypto_aead.c',
	'./lib/luacrypto_comp.c',
	'./lib/luacrypto_kpp.c',
	'./lib/luacrypto_rng.c',
	'./lib/luacrypto_shash.c',
	'./lib/luacrypto_sig.c',
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
	'./lib/set/image.lua',
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

-- what the site's template reads of this project: its repository, its home page's headline, example
-- and facts, where its Donate link goes, and the areas the API is grouped by, in the menu, on the home
-- page and in the index; a module no pattern takes goes to the last area
vars = {
	github = 'https://github.com/luainkernel/lunatik',
	headline = {'Script the Linux kernel', 'with Lua'},
	donate = 'index.html#support',
	showcase = 'examples/systrack/probe.lua',
	facts = {'Process, softirq and hardirq hooks'},
	areas = {
		{'runtime', 'Runtime', 'Runtimes, kernel threads and the channels between them.',
			{'^lunatik$', '^lunatik%.', '^thread$', '^completion$', '^mailbox$', '^fifo$'},
			'M12 3l9 5-9 5-9-5 9-5zM3 13l9 5 9-5'},
		{'packets', 'Packets and eBPF', 'Netfilter, XDP and TC hooks, socket buffers and eBPF maps.',
			{'^netfilter$', '^xdp$', '^tc$', '^skb', '^bpf'},
			'M4 8h14M14 4l4 4-4 4M20 16H6M10 12l-4 4 4 4'},
		{'network', 'Sockets and netlink', 'Kernel sockets, and rtnetlink and generic netlink sessions.',
			{'^socket', '^net$', '^netlink'},
			'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zM3 12h18M12 3c3 3.2 3 14.8 0 18M12 3c-3 3.2-3 14.8 0 18'},
		{'tracing', 'Tracing and scheduling', 'Kprobes, system call addresses and sched_ext.',
			{'^probe$', '^syscall', '^scx$'},
			'M3 12h4l3-7 4 14 3-7h4'},
		{'devices', 'Devices and events', 'Character devices, HID drivers, notifier chains and fsnotify.',
			{'^device$', '^hid$', '^notifier$', '^fsnotify$'},
			'M7 7h10v10H7zM10 3v4M14 3v4M10 17v4M14 17v4M3 10h4M3 14h4M17 10h4M17 14h4'},
		{'data', 'Data', 'Memory buffers, RCU tables, sets, byte order and records.',
			{'^data$', '^rcu$', '^set$', '^byteorder$', '^struct$', '^class$'},
			'M4 6c0-1.7 3.6-3 8-3s8 1.3 8 3-3.6 3-8 3-8-1.3-8-3zM4 6v12c0 1.7 3.6 3 8 3s8-1.3 8-3V6M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3'},
		{'crypto', 'Cryptography', 'The kernel crypto API and encrypted scripts.',
			{'^crypto', '^darken$', '^lighten$'},
			'M6 11h12v10H6zM8.5 11V7.5a3.5 3.5 0 0 1 7 0V11'},
		{'system', 'System', 'The kernel as a whole: time, CPUs, tasks and signals.',
			{'^linux$', '^cpu$', '^task$', '^signal$'},
			'M3 5h18v14H3zM7 10l3 2.5L7 15M12.5 15H17'},
		{'constants', 'Constants', 'Kernel constants, generated from its headers at build time.',
			{'^linux%.'},
			'M10 3L8 21M16 3l-2 18M4 9h16M4 15h16'},
		{'other', 'Other', 'Modules outside the areas above.', {}, 'M5 12h.01M12 12h.01M19 12h.01'},
	},
}

