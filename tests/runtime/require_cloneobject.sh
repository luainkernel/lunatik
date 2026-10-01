#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# An object resumed into a runtime whose script never required its module
# arrives with its class's metatables: lunatik_cloneobject creates them there
# from the class's methods, through lunatik_require, and adds no package.loaded
# entry. The receiver empties package.searchers, so a clone that went through
# require would find nothing, and asserts package.loaded holds nothing under
# the class name of what it got.
#
# A data object crosses into a softirq receiver, where the clone runs under the
# spinlock of the monitored resume and must not sleep. set.labeled, the crypto
# classes and the bpf maps cross into a process receiver, the context the crypto
# classes need. crypto_comp exists on 6.14 and earlier, so its case skips where
# luacrypto carries no luacrypto_comp_new; the bpf maps are pinned with bpftool,
# and their case skips where it cannot pin them.
#
# Usage: sudo bash tests/runtime/require_cloneobject.sh

SCRIPT="tests/runtime/require_cloneobject"
COMP="tests/runtime/require_cloneobject_comp"
BPF="tests/runtime/require_cloneobject_bpf"
MODULE="luadata"

BPF_FS=/sys/fs/bpf
HASH_MAP=$BPF_FS/test_require_cloneobject_hash
QUEUE_MAP=$BPF_FS/test_require_cloneobject_queue

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" 2>/dev/null
	lunatik stop "$COMP" 2>/dev/null
	lunatik stop "$BPF" 2>/dev/null
	rm -f "$HASH_MAP" "$QUEUE_MAP"
}
trap cleanup EXIT
cleanup

# runs the sender <script> and reports <description> on what it does
clones()
{
	if run_test "$1"; then
		ktap_pass "$2"
	else
		ktap_fail "$2"
	fi
}

ktap_header
ktap_plan 3

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}

clones "$SCRIPT" "data, set.labeled and crypto.shash, skcipher, aead and rng reach a runtime that never required them"

if grep -qw luacrypto_comp_new /proc/kallsyms; then
	clones "$COMP" "crypto.comp reaches a runtime that never required crypto"
else
	ktap_skip "crypto.comp: the binding is not built on this kernel"
fi

mountpoint -q "$BPF_FS" || mount -t bpf bpf "$BPF_FS"
if bpftool map create "$HASH_MAP" type hash key 4 value 4 entries 1 name test_clone_hash > /dev/null 2>&1 &&
	bpftool map create "$QUEUE_MAP" type queue key 0 value 4 entries 1 name test_clone_queue > /dev/null 2>&1; then
	clones "$BPF" "bpf.hash and bpf.queue reach a runtime that never required bpf"
else
	ktap_skip "bpf.hash and bpf.queue: bpftool cannot pin the maps"
fi

ktap_totals

