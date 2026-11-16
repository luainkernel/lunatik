#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# luarcu hands each entry a write replaces or removes to call_srcu, and an scx callback writes
# with its CPU's runqueue lock held. A srcu_struct initialised at its first call_srcu allocates
# its node tree there with GFP_ATOMIC, whose kswapd wakeup takes a runqueue lock, on a kernel
# that sizes the tree at init: 128 possible CPUs or srcutree.convert_to_big=1, which
# /sys/module/srcutree/parameters/convert_to_big reads as 1 once srcu_init has decided, 17 with
# contention sizing beside it. luarcu initialises its own as the module loads.
#
# The CLI frees an entry before it runs a script, lunatik.runner.startup storing lunatik._ENV's
# two tables back over themselves, so the first free since luarcu loaded is never a script's. The
# case unloads the modules, and a kmalloc tracepoint, in a trace instance of the test's own
# filtered to the tasks named lunatik, is on before `lunatik run` loads them again: modprobe's
# task, which runs luarcu's init, is outside the filter, and every free the CLI's task makes from
# the load on is inside it, the runner's and the one srcu_init.lua makes by replacing an entry.
# The trace holds the entries' allocations and none whose call site is SRCU's.
#
# Skips on a kernel that sizes the tree only once contended, where no build allocates in the
# write; 7.0 and later defer the tree where the caller cannot sleep, so no build allocates there
# either.
#
# Usage: sudo bash tests/rcu/srcu_init.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

SCRIPT="tests/rcu/srcu_init"
CASE="rcu/srcu_init: a write's first free allocates nothing for SRCU"
INSTANCE="$TRACING/instances/lunatik_srcu_init"
EVENT="$INSTANCE/events/kmem/kmalloc"
SIZING="/sys/module/srcutree/parameters/convert_to_big"
INIT=1		# SRCU_SIZING_INIT
CONTEND=16	# SRCU_SIZING_CONTEND, a flag beside the mode

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	if [ -d "$INSTANCE" ]; then
		echo 0 > "$EVENT/enable" 2>/dev/null
		rmdir "$INSTANCE"
	fi
}
trap cleanup EXIT
cleanup

sizing=$(cat "$SIZING" 2>/dev/null)
[ -n "$sizing" ] && [ $((sizing & ~CONTEND)) -eq $INIT ] ||
	skip_script "$CASE: SRCU sizes a tree at its first use only with srcutree.convert_to_big=1 or 128 CPUs"

mkdir "$INSTANCE" 2>/dev/null &&
	echo 'comm == "lunatik"' > "$EVENT/filter" &&
	echo 1 > "$EVENT/enable" || skip_script "$CASE: couldn't trace kmem:kmalloc in an instance of its own"

ktap_header
ktap_plan 2

mark_dmesg
lunatik unload > /dev/null 2>&1
[ ! -e /sys/module/luarcu ] || fail "$CASE: luarcu did not unload"
run_script "$SCRIPT"
echo 0 > "$EVENT/enable"
lunatik stop "$SCRIPT" > /dev/null 2>&1

trace=$(cat "$INSTANCE/trace")
srcu=$(grep -E 'kmalloc:.*call_site=[^ ]*srcu' <<< "$trace" || true)
if ! grep -qE 'kmalloc:.*call_site=luarcu_' <<< "$trace"; then
	ktap_fail "$CASE"
	echo "# the trace holds no allocation of the entry the script wrote"
elif [ -n "$srcu" ]; then
	ktap_fail "$CASE"
	echo "# ${srcu%%$'\n'*}"
else
	ktap_pass "$CASE"
fi

check_dmesg && ktap_pass "rcu/srcu_init: no Lua errors, kernel warnings or oopses"

ktap_totals

