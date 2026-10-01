--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netlink umbrella test (see umbrella.sh).

local netlink = require("netlink")

assert(netlink.rt and netlink.genl and netlink.nl80211, "netlink should carry rt, genl and nl80211")

