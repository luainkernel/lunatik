#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test for NULL-deref in luanotifier_release on context-mismatch
# cleanup.
#
# luanotifier_new calls lunatik_newobject (which kzallocs the notifier)
# before lunatik_checkruntime. Running a hardirq-class constructor from a
# process runtime makes checkruntime raise luaL_error with notifier->runtime
# still NULL. lua_close on the failing runtime then triggers __gc -> release,
# which without the guard oopses on lunatik_putobject(NULL).
#
# The Lua script invokes notifier.keyboard() from the default process
# runtime. Expected: Lua error "runtime context mismatch" in the script
# output and zero kernel oops entries in dmesg.
#
# Usage: sudo bash tests/notifier/context_mismatch.sh

SCRIPT="tests/notifier/context_mismatch"

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
echo "$output" | grep -q "runtime context mismatch" || \
	fail "expected 'runtime context mismatch' error, got: $output"
ktap_pass "hardirq-class constructor in process runtime errors cleanly"

oops=$(dmesg_since | grep -E "Oops:|BUG:|kernel BUG at|NULL pointer dereference|general protection" || true)
[ -n "$oops" ] && fail "kernel oops during context-mismatch cleanup: ${oops%%$'\n'*}"
ktap_pass "no kernel oops during context-mismatch cleanup"

ktap_totals

