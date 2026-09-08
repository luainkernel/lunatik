#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test for the tfm crypto.shash() allocated before the object that
# has to hold it. lunatik_newobject() raises for a process-context class in an
# interrupt-context runtime, so a shash asked for from an armed softirq runtime
# left the tfm behind, and a tfm holds a reference on the module implementing
# the algorithm for the rest of the boot.
#
# The kernel's own refcount is the instrument. One shash held alive names the
# module that backs sha256 here, whatever it is on this architecture: the one
# /proc/crypto lists whose reference count rose while that shash lived. The
# refusals then have to leave that count where they found it.
#
# Usage: sudo bash tests/crypto/context.sh

SCRIPT=tests/crypto/context
HOLD=tests/crypto/context_hold

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	lunatik stop "$HOLD" > /dev/null 2>&1
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

refcnt() { awk -v m="$1" '$1 == m {print $3}' /proc/modules; }

mark_dmesg

run_script "$HOLD"
held=$(cat /proc/modules)
lunatik stop "$HOLD" > /dev/null 2>&1

# only a module /proc/crypto names can be the one a live shash pinned
algmods=" $(awk '$1 == "module" {print $3}' /proc/crypto | sort -u | tr '\n' ' ')"
providers=""
while read -r name _ count _; do
	case "$algmods" in *" $name "*) ;; *) continue ;; esac
	alive=$(echo "$held" | awk -v m="$name" '$1 == m {print $3}')
	[ "${alive:-0}" -gt "$count" ] && providers="$providers $name:$count"
done < /proc/modules

leaked=""
if [ -n "$providers" ]; then
	run_script "$SCRIPT"
	lunatik stop "$SCRIPT" > /dev/null 2>&1

	for provider in $providers; do
		name=${provider%:*}
		[ "$(refcnt "$name")" -gt "${provider#*:}" ] && leaked="$leaked $name"
	done
fi

if ! check_dmesg; then
	ktap_totals
	exit 1
elif [ -z "$providers" ]; then
	ktap_skip "crypto/context: no module backs sha256 here, so a leaked tfm counts nowhere"
elif [ -n "$leaked" ]; then
	ktap_fail "crypto/context: a refused shash left a reference on$leaked"
else
	ktap_pass "crypto/context"
fi

ktap_totals
[ $KTAP_FAIL -eq 0 ]

