#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs all bpf tests and reports aggregated KTAP results.
#
# Creates pinned maps with bpftool (hash, array, lru_hash, queue, stack and
# a percpu hash for the unsupported-type check), seeds the hash map, then
# exercises the bpf module API from kernel Lua scripts: per-type coverage
# in process context, a softirq-runtime script, and a Lua-to-bpftool
# interop check.
#
# Usage: sudo bash tests/bpf/run.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

BPF_FS=/sys/fs/bpf
MAP=$BPF_FS/test_map
ARRAY_MAP=$BPF_FS/test_map_array
LRU_MAP=$BPF_FS/test_map_lru
PERCPU_MAP=$BPF_FS/test_map_percpu
QUEUE_MAP=$BPF_FS/test_map_queue
STACK_MAP=$BPF_FS/test_map_stack
SOFTIRQ_SCRIPT=tests/bpf/map_softirq

skip() { ktap_header; ktap_plan 1; ktap_skip "$1"; ktap_totals; exit 0; }

command -v bpftool > /dev/null 2>&1 || skip "bpf: bpftool unavailable"

cleanup()
{
	lunatik stop "$SOFTIRQ_SCRIPT" 2>/dev/null
	rm -f "$MAP" "$ARRAY_MAP" "$LRU_MAP" "$PERCPU_MAP" "$QUEUE_MAP" "$STACK_MAP"
}

trap cleanup EXIT

cleanup

if ! mountpoint -q "$BPF_FS"; then
	mount -t bpf bpf "$BPF_FS"
fi

bpftool map create "$MAP" type hash key 3 value 3 entries 128 name test_map >/dev/null
bpftool map create "$ARRAY_MAP" type array key 4 value 4 entries 4 name test_array >/dev/null
bpftool map create "$LRU_MAP" type lru_hash key 3 value 3 entries 128 name test_lru >/dev/null
bpftool map create "$PERCPU_MAP" type percpu_hash key 3 value 3 entries 128 name test_percpu >/dev/null
bpftool map create "$QUEUE_MAP" type queue key 0 value 3 entries 128 name test_queue >/dev/null
bpftool map create "$STACK_MAP" type stack key 0 value 3 entries 128 name test_stack >/dev/null

bpftool map update pinned "$MAP" key hex 66 6f 6f value hex 62 61 72

TESTS="map_values array lru queue stack"
TOTAL=$(($(echo $TESTS | wc -w) + 2))

ktap_header
ktap_plan $TOTAL

for t in $TESTS; do
	mark_dmesg
	if ! lunatik run "tests/bpf/$t" 2>/dev/null; then
		ktap_fail "bpf/$t: script execution failed"
		continue
	fi
	errs=$(dmesg_since | grep -iE "^[^:]+: FAIL	|\.lua:[0-9]+:" || true)
	if [ -z "$errs" ]; then
		ktap_pass "bpf/$t"
	else
		ktap_fail "bpf/$t"
		while IFS= read -r line; do
			echo "# $line"
		done <<< "$errs"
	fi
done

mark_dmesg
output=$(lunatik run "$SOFTIRQ_SCRIPT" softirq 2>&1)
if ! echo "$output" | grep -qE "\.lua:[0-9]+:" && [ -z "$(dmesg_since | grep -E '\.lua:[0-9]+:' || true)" ]; then
	ktap_pass "bpf/map_softirq"
else
	ktap_fail "bpf/map_softirq"
	echo "# $output"
fi
lunatik stop "$SOFTIRQ_SCRIPT" 2>/dev/null

if bpftool map lookup pinned "$MAP" key hex 61 62 63 | grep -q "78 79 7a"; then
	ktap_pass "bpf/interop: bpftool reads Lua-written value"
else
	ktap_fail "bpf/interop: bpftool reads Lua-written value"
fi

ktap_totals
[ $KTAP_FAIL -eq 0 ]

