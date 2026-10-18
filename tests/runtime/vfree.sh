#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A block the runtimes' allocator took from vmalloc and frees with interrupts off goes back on a
# kernel worker: vfree may sleep, and it BUGs in NMI, where x86 runs an int3 kprobe's handler.
#
# kvmalloc takes a block past KMALLOC_MAX_SIZE from vmalloc whatever memory is free, and a body
# allocates with GFP_KERNEL, a hardirq runtime's included, so the blocks the test frees are vmalloc's
# by construction; this script writes a page past KMALLOC_MAX_SIZE, which lib.sh's kmalloc_max reads
# from /proc/buddyinfo, into vfree_sizes.lua.
# vfree.lua, a process runtime, hands a data of that size to a hardirq runtime of vfree_blocks.lua,
# whose body builds a string of it, and resumes it: under that runtime's lock, with interrupts off,
# the function its body returns drops and collects the string and resizes the data to a byte, which
# moves it. vfree_probe.lua, a hardirq script, builds both in its body and runs the same frees from
# a handler on the personality syscall, which nothing else on an idle host calls and one setarch
# calls once.
#
# A trace instance of the test's own says where the frees ran: the function tracer, filtered to
# vfree, sees none on a task with interrupts off, which the first flag of its line reads, and a
# kprobe on vfree none inside the handler, which the kernel counts as a miss of the probe rather
# than a hit; /proc/vmallocinfo, which names lunatik_alloc as the caller of each block, says every
# one went back. The kprobe's own line cannot read the flag: on arm64 its handler runs in the debug
# exception, interrupts masked, so every hit reads them off. A build that frees in place
# fails those reads on arm64, where the free is otherwise silent. The test skips unless the loaded
# core exports lunatik_free, which a core whose lunatik_free is kvfree lacks: that core frees in
# place in the handler, where vfree may sleep.
#
# Usage: sudo bash tests/runtime/vfree.sh

SCRIPT="tests/runtime/vfree"
PROBE="tests/runtime/vfree_probe"
SIZES="/lib/modules/lua/tests/runtime/vfree_sizes.lua"
FIX="lunatik_free"
EVENT="lunatik_vfree/vfree"
BLOCKS=2 # a string and a data's buffer, in each case

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

INSTANCE="$TRACING/instances/${EVENT%%/*}"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	lunatik stop "$PROBE" > /dev/null 2>&1
	kprobe_remove "$EVENT"
	rm -f "$SIZES"
}

skip_all() { ktap_header; ktap_plan 1; ktap_skip "$1"; ktap_totals; exit 0; }

# the calls the function tracer saw on a task, outside an interrupt, with interrupts off: a free
# that ran under the lock
inplace() { awk '$5 == "vfree" && $3 ~ /^[dD].\./' "$INSTANCE/trace" | wc -l; }
# the hits the kernel took inside another kprobe's handler
misses() { awk -v event="${EVENT#*/}" '$1 == event { print $3 }' "$TRACING/kprobe_profile"; }
# the blocks of the test's size the runtimes' allocator holds from vmalloc
held() { awk -v size="$kmalloc" '$3 ~ /^lunatik_alloc\+/ && $2 > size' /proc/vmallocinfo | wc -l; }
freed() { [ "$(held)" -eq 0 ]; }

trap cleanup EXIT
cleanup

grep -Eq " $FIX[[:space:]]\[lunatik\]$" /proc/kallsyms || skip_all "the loaded core does not export $FIX: it frees in place in a probe handler"
command -v setarch > /dev/null 2>&1 || skip_all "setarch not available"
kprobe_place "$EVENT" vfree || skip_all "couldn't place a kprobe on vfree"
{ echo vfree > "$INSTANCE/set_ftrace_filter" && echo function > "$INSTANCE/current_tracer"; } 2>/dev/null ||
	skip_all "couldn't trace vfree with the function tracer"

page=$(getconf PAGESIZE)
kmalloc=$(kmalloc_max)
printf 'return {vmalloc = %d}\n' "$((kmalloc + page))" > "$SIZES"

ktap_header
ktap_plan 5

mark_dmesg
run_script "$SCRIPT"
awaited freed
left=$(held)
lunatik stop "$SCRIPT" > /dev/null 2>&1

under=$(inplace)
if [ "$left" -ne 0 ]; then
	ktap_fail "$left blocks a resumed hardirq runtime freed are still allocated"
elif [ "$under" -ne 0 ]; then
	ktap_fail "$under vfree calls ran under the lock of a resumed hardirq runtime"
else
	ktap_pass "a block a resumed hardirq runtime frees, collected or moved, goes back off its lock"
fi

run_script --context=hardirq "$PROBE"
built=$(held)
[ "$built" -eq "$BLOCKS" ] || fail "the probe script's body holds $built vmalloc'd blocks, not $BLOCKS"
ktap_pass "a hardirq runtime's body takes a block past KMALLOC_MAX_SIZE from vmalloc"

before=$(misses)
setarch "$(uname -m)" -R true > /dev/null 2>&1
awaited freed
left=$(held)
inside=$(($(misses) - before))
lunatik stop "$PROBE" > /dev/null 2>&1

if [ "$left" -eq 0 ]; then
	ktap_pass "a block a probe handler frees, collected or moved, goes back"
else
	ktap_fail "$left blocks a probe handler freed are still allocated"
fi

if [ "$inside" -eq 0 ]; then
	ktap_pass "a probe handler frees no block in place"
else
	ktap_fail "$inside vfree calls ran inside a probe handler"
fi

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

