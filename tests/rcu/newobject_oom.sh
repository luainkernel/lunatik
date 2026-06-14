#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test for a use-after-free in lunatik_newobject(): the object's
# __gc finalizer used to run on uninitialized userdata memory when the private
# allocation failed *after* the metatable (and thus __gc) was already set.
#
# Requesting an rcu.table with an absurd bucket count forces that allocation to
# fail; the buggy core then dereferenced a garbage object pointer in
# lunatik_deleteobject() and oopsed. The fix publishes the object before
# arming __gc, so the failure must surface as a graceful Lua error and leave
# the kernel alive.
#
# Usage: sudo bash tests/rcu/newobject_oom.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

cleanup() { lunatik stop tests/rcu/newobject_oom 2>/dev/null; }
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

mark_dmesg
run_script tests/rcu/newobject_oom

log=$(dmesg_since)
crash=$(echo "$log" | grep -E "Oops|BUG: unable|general protection|kernel BUG at|unable to handle kernel" || true)
luaerr=$(echo "$log" | grep -E "\.lua:[0-9]+:" || true)
if [ -n "$crash" ]; then
	ktap_fail "rcu/newobject_oom: kernel crashed on failed allocation"
	echo "# ${crash%%$'\n'*}"
elif [ -n "$luaerr" ]; then
	ktap_fail "rcu/newobject_oom: Lua-level failure"
	echo "# ${luaerr%%$'\n'*}"
else
	ktap_pass "rcu/newobject_oom"
fi

ktap_totals
[ $KTAP_FAIL -eq 0 ]

