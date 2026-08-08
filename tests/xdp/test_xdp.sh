#!/bin/bash

#
# SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#

# Tests the XDP dispatch path by loading an XDP program with bpftool,
# attaching it to an interface, and running a Lunatik XDP script.
#
# Usage: sudo bash tests/xdp/run.sh

MODULE="luaxdp"
IFACE="docker0"
PIN="/sys/fs/bpf/xdp"
TARGET=$(ip -4 addr show "$IFACE" | awk '/inet / {sub(/\/.*/, "", $2); print $2}')

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

ktap_header
ktap_plan 1

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}

command -v bpftool > /dev/null 2>&1 || {
	echo "# SKIP: bpftool not available"
	ktap_totals
	exit 0
}

cleanup()
{
	bpftool net detach xdp dev "$IFACE" 2>/dev/null
	rm -f "${PIN}_PASS"
	rm -f "${PIN}_DROP"
}

trap cleanup EXIT

make -C tests/xdp || { ktap_fail "failed to build XDP program"; ktap_totals; exit 1; }

ktap_plan 2

run_case()
{
	local obj="$1" pin="$2" script="$3" expect_reachable="$4" label="$5"

	bpftool prog load "tests/xdp/$obj" "$pin" type xdp ||
		{ ktap_fail "$label: failed to load XDP program"; return 1; }
	bpftool net attach xdp pinned "$pin" dev "$IFACE" ||
		{ ktap_fail "$label: failed to attach XDP program"; bpftool prog unpin "$pin"; return 1; }

	mark_dmesg
	run_script "tests/xdp/$script" softirq percpu
	check_dmesg || { ktap_fail "$label: script raised an error"; return 1; }

	docker run --rm alpine ping -c 1 -W 2 "$TARGET" > /dev/null 2>&1
	local reached=$?

	bpftool net detach xdp dev "$IFACE" 2>/dev/null
	rm -f "$pin"

	dmesg_since | grep -qF "$label test pass" || { ktap_fail "$label: verdict callback did not run"; return 1; }

	if [ "$expect_reachable" = "yes" ] && [ "$reached" -ne 0 ]; then
		ktap_fail "$label: expected PASS but ping was blocked"; return 1
	fi
	if [ "$expect_reachable" = "no" ] && [ "$reached" -eq 0 ]; then
		ktap_fail "$label: expected DROP but ping got through"; return 1
	fi

	ktap_pass "$label: verdict enforced correctly"
}

run_case xdp_pass.bpf.o "${PIN}_PASS" pass.lua yes "xdp pass"
run_case xdp_drop.bpf.o "${PIN}_drop" drop.lua no "xdp drop"

ktap_totals

