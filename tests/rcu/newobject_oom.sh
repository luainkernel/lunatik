#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test for a use-after-free in lunatik_newobject(): the object's
# __gc finalizer used to run on uninitialized userdata memory when the private
# allocation failed *after* the metatable (and thus __gc) was already set. The
# buggy core then dereferenced a garbage object pointer in
# lunatik_deleteobject() and oopsed. The fix publishes the object before arming
# __gc, so the failure must surface as a graceful Lua error and leave the
# kernel alive.
#
# The failure is forced on the GFP_ATOMIC path: a kmalloc past KMALLOC_MAX_SIZE
# asks the page allocator for an order above MAX_PAGE_ORDER, which returns NULL.
# That holds only where KMALLOC_MAX_SIZE is below the request, which the guard
# below checks, since the kernel serves 512 MiB from kmalloc on 64K pages. In
# process context kvmalloc() falls back to vmalloc and no bucket count fails
# reliably. A runtime allocates with GFP_ATOMIC only once its script body has
# returned, so the body hands back a function and the driver runs it through
# resume().
#
# Usage: sudo bash tests/rcu/newobject_oom.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

cleanup() { lunatik stop tests/rcu/newobject_oom 2>/dev/null; }
trap cleanup EXIT
cleanup

REQUEST=$(( (1 << 23) * 8 )) # the buckets newobject_oom_atomic.lua asks for, of one hlist_head each

# KMALLOC_MAX_SIZE is 1 << (MAX_PAGE_ORDER + PAGE_SHIFT) (include/linux/slab.h), and
# MAX_PAGE_ORDER is 10 unless the architecture forces another (arch/arm64/Kconfig).
kmalloc_max()
{
	local order page bits
	order=$(grep -m1 '^CONFIG_ARCH_FORCE_MAX_ORDER=' "/boot/config-$(uname -r)" 2>/dev/null | cut -d= -f2)
	page=$(getconf PAGESIZE)
	bits=0
	while [ "$page" -gt 1 ]; do
		page=$((page / 2))
		bits=$((bits + 1))
	done
	echo $(( 1 << (${order:-10} + bits) ))
}

ktap_header
ktap_plan 1

if [ "$(kmalloc_max)" -ge "$REQUEST" ]; then
	ktap_skip "rcu/newobject_oom: kmalloc serves $REQUEST bytes here, the failure is not structural"
	ktap_totals
	exit 0
fi

mark_dmesg
run_script tests/rcu/newobject_oom

log=$(dmesg_since)
crash=$(echo "$log" | grep -E "Oops|BUG: unable|general protection|kernel BUG at|unable to handle kernel" || true)
errs=$(echo "$log" | grep -E "$KTAP_ERRORS" || true)
if [ -n "$crash" ]; then
	ktap_fail "rcu/newobject_oom: kernel crashed on failed allocation"
	echo "# ${crash%%$'\n'*}"
elif [ -n "$errs" ]; then
	ktap_fail "rcu/newobject_oom: Lua error or kernel warning"
	echo "# ${errs%%$'\n'*}"
else
	ktap_pass "rcu/newobject_oom"
fi

ktap_totals
[ $KTAP_FAIL -eq 0 ]

