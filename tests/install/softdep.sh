#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# lunatik_run makes /dev/lunatik from a script that requires device, which the kernel's require
# finds only in a module already loaded, and it uses no symbol of luadevice, so the order reaches
# modprobe as a soft dependency: modprobe --show-depends lunatik_run, read in the host's module
# tree as make install left it, lists luadevice.ko before lunatik_run.ko. Nothing is loaded.
#
# Usage: sudo bash tests/install/softdep.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

ktap_header
ktap_plan 1

order=$(modprobe --show-depends lunatik_run 2>&1) || fail "install: modprobe found no lunatik_run: $order"

if sed '/\/lunatik_run\.ko/q' <<< "$order" | grep -q '/luadevice\.ko'; then
	ktap_pass "install: modprobe lunatik_run loads luadevice first"
else
	comment "$order"
	ktap_fail "install: modprobe lunatik_run does not load luadevice first"
fi

ktap_totals

