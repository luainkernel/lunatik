-- SPDX-FileCopyrightText: (c) 2024 jperon <cataclop@hotmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only

-- Filter TLS packets based on SNI

-- Assuming that this script is transpiled into in /lib/modules/lua/sniblock/match.lua,
-- and libxt_sniblock.so is installed:
--
-- > sudo lunatik run sniblock/match false
-- > sudo iptables  -A OUTPUT [-p tcp] [--dport 443] -m sniblock -j REJECT
-- > sudo ip6tables -A OUTPUT [-p tcp] [--dport 443] -m sniblock -j REJECT

-- To disable it:
--
-- > sudo iptables  -D OUTPUT [-p tcp] [--dport 443] -m sniblock -j REJECT
-- > sudo ip6tables -D OUTPUT [-p tcp] [--dport 443] -m sniblock -j REJECT
-- > sudo lunatik stop sniblock/match

-- Once enabled, to add entries to whitelist:
-- > echo add DOMAIN > /dev/sni_whitelist
-- To remove entries:
-- > echo del DOMAIN > /dev/sni_whitelist
-- To get a list of entries (formatted as a Lua table):
-- > head -1 /dev/sni_whitelist

import concat from table
xt = require"xtable"
import UNSPEC from xt.family
device = require"device"
linux = require"linux"
import IRUSR, IWUSR from linux.stat
IRWUSR = IRUSR | IWUSR
import auto_ip, TCP, TLS, TLSHandshake, TLSExtension from require"sniblock.ipparse"
import handshake from TLS.types
import hello from TLSHandshake.types
import server_name from TLSExtension.types

whitelist = {}


nop = ->  -- Do nothing


get_first = (fn) =>  -- Returns first value of a table that matches the condition defined in function fn.
  for v in *@
    return v if fn v

device.new{
  name: "sni_whitelist", mode: IRWUSR
  open: nop, release: nop
  read: (len) => ('{\"' .. concat([ k for k in pairs whitelist ], '","') .. '"}\n')\gsub '""', ''
  write: (s) =>
    for action, domain in s\gmatch"(%S+)%s(%S+)"
      if action == "add"
        whitelist[domain] = true
      elseif action == "del"
        whitelist[domain] = nil
}


xt.match{
  name: "sniblock", revision: 1, family: UNSPEC, proto: 0
  checkentry: nop, destroy: nop, hooks: 0
  match: (par) =>
    ip = auto_ip @
    assert ip.data_off == par.thoff
    tcp = TCP ip.data
    tls = TLS tcp.data
    return if tls\is_empty!
    if tls.type == handshake
      hshake = TLSHandshake tls.data
      if hshake.type == hello
        if sni = (get_first hshake.extensions, => @type == server_name).server_name
          if whitelist[sni]
              print"#{sni} allowed."
              return false
          sni_parts = [ part for part in sni\gmatch"[^%.]+"]
          for i = 2, #sni_parts
            domain = concat [ part for part in *sni_parts[i,] ], "."
            if whitelist[domain]
              print"#{sni} allowed as a subdomain of #{domain}."
              return false
          print"#{sni} BLOCKED."
          return true

    false
}

