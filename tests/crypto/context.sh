#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A crypto object refused in an armed softirq runtime leaves no tfm behind:
# crypto.shash() and crypto.skcipher(), softirq classes, raise "not allowed once
# the runtime is armed" before they allocate one, and crypto.comp() and
# crypto.sig() raise for their process-context class before lunatik_newobject()
# returns the object that would hold it. A tfm left behind holds a reference on
# the module implementing the algorithm for the rest of the boot.
#
# The kernel's own refcount is the instrument. One object of each kind held
# alive names the modules that back sha256, ctr(aes), lz4, ecdsa-nist-p256 and
# ecdh-nist-p256 here, whatever they are on this architecture: those
# /proc/crypto lists whose reference count rose while the objects lived. The
# refusals then have to be the ones context_atomic expects, and leave those
# counts where they found them.
#
# The case only runs against the build it was installed with. The refusals are
# static inlines compiled into luacrypto, so a build from before them allocates
# the tfm first, and crypto_alloc_shash() sleeps - crypto_alg_sem, a GFP_KERNEL
# allocation, a larval wait - under the spinlock lunatik takes to resume a
# softirq runtime, which wedges the host. A later make install replaces the
# module and leaves this case behind, since it removes nothing, and lunatik
# reload leaves a module something else pinned loaded.
#
# Usage: sudo bash tests/crypto/context.sh

SCRIPT=tests/crypto/context
HOLD=tests/crypto/context_hold
MODULE=luacrypto
ATOMIC=/lib/modules/lua/tests/crypto/context_atomic.lua

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

module_installed_with_case() {
	local ko installed
	ko=$(modinfo -n "$MODULE" 2>/dev/null)
	installed=$(modinfo -F srcversion "$MODULE" 2>/dev/null)
	[ -n "$ko" ] && [ -r "$ATOMIC" ] && [ ! "$ko" -nt "$ATOMIC" ] && [ -n "$installed" ] &&
		[ "$installed" = "$(cat "/sys/module/$MODULE/srcversion" 2>/dev/null)" ]
}

mark_dmesg

run_script "$HOLD" # loads luacrypto, in process context, where no build allocates under a lock
check_dmesg || { ktap_totals; exit 1; }

module_installed_with_case || {
	ktap_skip "crypto/context: the loaded $MODULE can't be shown to be the build this case was installed with, and an older one wedges the host here"
	ktap_totals
	exit 0
}

held=$(cat /proc/modules)
lunatik stop "$HOLD" > /dev/null 2>&1

# only a module /proc/crypto names can be the one a live tfm pinned
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
	ktap_skip "crypto/context: no module backs sha256, ctr(aes), lz4, ecdsa-nist-p256 or ecdh-nist-p256 here, so a leaked tfm counts nowhere"
elif [ -n "$leaked" ]; then
	ktap_fail "crypto/context: a refused object left a reference on$leaked"
else
	ktap_pass "crypto/context"
fi

ktap_totals

