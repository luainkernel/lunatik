#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# What the caller of a monitored method allocates with, under the object's lock.
#
# lunatik_monitor runs a method holding the object's lock, a spinlock for a softirq or
# hardirq object, and the calling runtime's state allocates under it: with the GFP_KERNEL
# of a process runtime the allocation may sleep, and one past a page that falls back to
# vmalloc hits its BUG_ON(in_interrupt()) with bottom halves off. gfp.lua, a process
# runtime, reads a shared data buffer, converts one to a string through __tostring, which
# the monitor wraps as it wraps a method, and pops a fifo, each into a string of a length of
# its own, and resumes a process, a softirq and a hardirq runtime of gfp_raise.lua, which
# reads the buffer it is handed, a monitored method of its own, and raises a message as long
# as the buffer: resume copies the message into the caller under that runtime's lock. Last,
# it allocates once more, after the hardirq runtime's raise, so the gfp it asks for is the
# one the monitor restored on a raise.
# A kmalloc tracepoint, in a trace instance of the test's own and filtered to those
# lengths, records each allocation's gfp, and its first flag says what was off: `b` bottom
# halves, `d` interrupts, `D` both. Every allocation the script's task asks for with a
# spinlock held asks for GFP_ATOMIC, an interrupt-context runtime's after a monitored method
# of its own returns included; with none held, under the process runtime's mutex and after
# the methods, they ask for GFP_KERNEL. A sleep in atomic context
# warns only on a kernel with CONFIG_DEBUG_ATOMIC_SLEEP, and these allocations stay under a
# page, short of vmalloc, and sleep only under memory pressure, so the gfp the tracepoint
# records is what tells a monitor that lowers it from one that does not, on any kernel.
#
# Usage: sudo bash tests/monitor/gfp.sh

SCRIPT="tests/monitor/gfp"
TRACING="/sys/kernel/tracing"
INSTANCE="$TRACING/instances/lunatik_gfp"
EVENT="$INSTANCE/events/kmem/kmalloc"
# the lengths gfp.lua allocates, a case to each, its allocations within WIDTH bytes past it
DATA=2100
FIFO=2400
SOFTIRQ=2700
HARDIRQ=3000
PROCESS=3300
AFTER=3600
STRING=3900
WIDTH=64

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	if [ -d "$INSTANCE" ]; then
		echo 0 > "$EVENT/enable" 2>/dev/null
		rmdir "$INSTANCE"
	fi
}

skip_all() { ktap_header; ktap_plan 1; ktap_skip "$1"; ktap_totals; exit 0; }

# the first flag and the gfp of each allocation the script's task asked for, from $1 to WIDTH past it
allocations()
{
	awk -v first="$1" -v width="$WIDTH" '$1 ~ /^lunatik-/ && $5 == "kmalloc:" {
		for (i = 6; i <= NF; i++)
			if (split($i, field, "=") == 2)
				value[field[1]] = field[2]
		if (value["bytes_req"] >= first && value["bytes_req"] < first + width)
			print substr($3, 1, 1), value["gfp_flags"]
	}' "$INSTANCE/trace"
}

# every allocation of the case starting at $1 that $3 selects matches $4, and there is one
expect()
{
	local selected
	selected=$(allocations "$1" | grep -- "$3")
	if [ -z "$selected" ]; then
		ktap_fail "$2: no allocation${3:+ matching $3}"
	elif grep -qv -- "$4" <<< "$selected"; then
		ktap_fail "$2: $(grep -v -- "$4" <<< "$selected" | head -1)"
	else
		ktap_pass "$2"
	fi
}

# a spinlock held: every allocation asks for GFP_ATOMIC
atomic() { expect "$1" "$2" '^[bdD] ' ' GFP_ATOMIC'; }
# no spinlock held: every allocation asks for GFP_KERNEL
sleepable() { expect "$1" "$2" '^\. ' ' GFP_KERNEL'; }

trap cleanup EXIT
cleanup

mkdir "$INSTANCE" 2>/dev/null &&
	echo "bytes_req >= $DATA && bytes_req < $((STRING + WIDTH))" > "$EVENT/filter" &&
	echo 1 > "$EVENT/enable" || skip_all "couldn't trace kmem:kmalloc in an instance of its own"

ktap_header
ktap_plan 9

mark_dmesg
run_script "$SCRIPT"
echo 0 > "$EVENT/enable"
lunatik stop "$SCRIPT" > /dev/null 2>&1

atomic $DATA "data: getstring on a shared buffer allocates with GFP_ATOMIC under its lock"
atomic $STRING "data: __tostring of a shared buffer allocates with GFP_ATOMIC under its lock"
atomic $FIFO "fifo: pop allocates with GFP_ATOMIC under its lock"
atomic $PROCESS "data: a process runtime's getstring inside a resume allocates with GFP_ATOMIC under its lock"
sleepable $PROCESS "runtime: resume copies a process runtime's error with GFP_KERNEL under its mutex"
atomic $SOFTIRQ "runtime: a softirq runtime keeps GFP_ATOMIC after its getstring, and resume copies its error with it"
atomic $HARDIRQ "runtime: a hardirq runtime keeps GFP_ATOMIC after its getstring, and resume copies its error with it"
sleepable $AFTER "the caller allocates with GFP_KERNEL again after a hardirq runtime's raise"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

