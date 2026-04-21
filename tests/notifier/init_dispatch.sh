#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test for sync-dispatch during script init.
#
# register_netdevice_notifier replays NETDEV_REGISTER (+ NETDEV_UP) synchronously
# for each existing netdev when a new notifier block is registered. Calling
# notifier.netdevice(cb) directly at script init triggers this replay while the
# script is still inside lua_pcall. Under the old design (private published only
# after pcall), luanotifier_call took the islocked sentinel path and entered
# lunatik_handle with runtime->private = NULL, oopsing on lua_gettop(NULL).
#
# Expected: script runs without Lua error, callback fires at least once (lo is
# always present), and no kernel oops lands in dmesg.
#
# Usage: sudo bash tests/notifier/init_dispatch.sh

SCRIPT="tests/notifier/init_dispatch"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 2

mark_dmesg

output=$(lunatik run "$SCRIPT" 2>&1)
echo "$output" | grep -qE "\.lua:[0-9]+:" && \
	fail "Lua error during init-time notifier registration: $output"
ktap_pass "notifier.netdevice() at script init runs without Lua error"

oops=$(dmesg_since | grep -E "Oops:|BUG:|kernel BUG at|NULL pointer dereference|general protection" || true)
[ -n "$oops" ] && fail "kernel oops during init-time notifier replay: ${oops%%$'\n'*}"
ktap_pass "no kernel oops during init-time NETDEV_REGISTER replay"

ktap_totals

