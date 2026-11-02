#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Harshdeep Singh
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs all linux tests and reports aggregated KTAP results.
#
# random: linux.random(m, n) and linux.random(n) stay within their range, a negative one included,
# linux.random(m, m) answers m and [0, math.maxinteger], as wide as an interval it takes, holds its
# draws; a draw from [0, 3 * 2^61 - 1] falls below 2^62 two times in three, where a reduction of
# get_random_u64() by modulo gives three in four: the count of 10000 draws is nearer the first,
# the two being 17 sigma apart.
#
# fsnotify: linux.fsnotify carries each event mask at the value the FAN_* and IN_* uapi pins it to,
# each entry is a single bit and no bit repeats, and it carries none of the composites and private
# names the include list of autogen/specs.lua leaves out: MOVE, IN_IGNORED, DN_MULTISHOT and
# EVENTS_POSS_ON_CHILD.
#
# notifier: linux.netdev.cmd carries the events of enum netdev_cmd and linux.vt.event the notifier events of
# <linux/vt.h>, and neither carries another name under its prefix. The case reads the names and no
# value: enum netdev_cmd is internal, and the kernel renumbers it when it inserts an event.
#
# signal: linux.signal carries the signals, HUP, KILL and TERM at their uapi numbers, and none of the
# names that share the SIG prefix: the how of sigprocmask (SIG_BLOCK), the sigevent notifications
# (SIGEV_*) and the signal stack size (SIGSTKSZ).
#
# task: linux.task carries the task states of <linux/sched.h> and nothing else: not its bounds,
# TASK_STATE_MAX and TASK_REPORT_MAX, nor TASK_COMM_LEN, nor an architecture's TASK_SIZE. The case
# reads the names and no value: the states are internal to the kernel.
#
# lookup: linux.lookup answers nil for a name no build can emit and for an absent symbol, answers a
# lightuserdata for kallsyms_lookup_name, and refuses a value that is not a string as string
# expected. A softirq and a hardirq runtime resolve the symbol in their body and again resumed past
# it, the armed state a hook calls from, where the absent one stays nil. Skipped without
# CONFIG_KPROBES.
#
# constants: the unsigned constants past INT_MAX, the signed ones below zero and those within
# INT_MAX that the script names keep their value. The eleven syscalls asm-generic/unistd.h defines
# as the name of their __NR3264_ number are in linux.syscall.numbers, and linux.errno holds each
# errno positive, keyed by the name linux.errname gives it.
#
# netns: linux.netns resolves pid 1 in a process runtime, in its body and resumed
# past it, and in the body of a softirq and a hardirq runtime; resumed past theirs,
# the armed state a hook calls from, each answers the call without a pid and
# refuses a pid. The case runs on a build without the refusal too: the resume takes
# the runtime's lock in process context, which cannot have interrupted a holder of
# the task's lock on its CPU, so such a build resolves the pid and fails, not spins.
#
# errname: linux.errname names an errno given with either sign and answers "unknown"
# for INT_MAX and -INT_MAX; it refuses INT_MIN, whose absolute value an int cannot
# hold, and a number past an int, as out of bounds, where a truncating build names
# (1 << 32) | ENOENT as ENOENT.
#
# ifindex: linux.ifindex resolves lo to its index and linux.hwaddr that index to
# lo's address, and each answers nil, alone, for a name or an index no device has.
#
# schedule: linux.schedule refuses a timeout outside 0 to 2^31 - 1 as out of bounds, asking first
# for one past msecs_to_jiffies's unsigned int, which a build without the bound truncates and naps
# on, so that build fails there before -1 and 2^31, which it reads as forever and sleeps on.
# It takes 0, and a 1 ms nap returns 0 left in a process runtime and in the body of a softirq and a
# hardirq runtime, which runs in process context; resumed past it, the armed state a hook calls
# from, each refuses the call as not allowed once the runtime is armed. Skipped unless the loaded
# lualinux is the installed one and carries that refusal.
#
# tracing: linux.tracing turns kernel tracing off and on given false and true, and answers the
# state it leaves, in a process, a softirq and a hardirq runtime resumed past their body, the armed
# state a hook calls from; given nothing or nil it reads the state and changes nothing, and it
# refuses any other value as boolean expected, changing nothing. The script leaves tracing as it
# found it. Skipped without CONFIG_TRACING, where the kernel's three are stubs.
#
# time: linux.clock carries REALTIME, MONOTONIC and BOOTTIME at their uapi ids and no other clock.
# linux.time reads the real time given nothing or nil, between two reads of REALTIME; two reads of
# MONOTONIC or of BOOTTIME never decrease, MONOTONIC read first is never past BOOTTIME read after it,
# BOOTTIME falls between two reads of /proc/uptime, to the centisecond it shows, and REALTIME read
# after BOOTTIME is ahead of it by the btime /proc/stat shows, to its second. It refuses
# CLOCK_TAI, -1 and an id past an int as invalid clock, and an armed softirq and an armed hardirq
# runtime, the state a hook calls from, read each clock. The case runs again from a time namespace
# whose offsets shift MONOTONIC by a billion seconds and BOOTTIME by a million: linux.time reads the
# initial namespace's clocks there, where /proc/uptime adds the boottime offset and btime takes it
# off, so the script takes back the offset run.sh writes for that run, and a build that applied
# the offsets reads MONOTONIC past BOOTTIME, a billion seconds being past any time a host has spent
# suspended. That run is skipped without time namespaces. MONOTONIC and BOOTTIME differ by the time
# suspended alone, nothing on a host that has not suspended, so the case cannot tell one from the
# other there; and that setting the wall clock moves REALTIME alone is not run, since the clock is
# the whole host's: do_settimeofday64() moves wall_to_monotonic, offs_real and offs_tai, which
# neither of the two reads.
#
# socket: linux.socket.ip carries the IP_ options net/ipv4/ip_sockglue.c takes, at their
# uapi/linux/in.h values, and no other IP_ name: not the IP_MTU_DISCOVER values or the multicast
# defaults, nor IP_ORIGDSTADDR, the control message IP_RECVORIGDSTADDR asks for, or IP_RECVRETOPTS,
# BSD's name for IP_RETOPTS.
#
# Usage: sudo bash tests/linux/run.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

TESTS="random fsnotify notifier signal task lookup constants schedule netns errname ifindex tracing time socket"
# the time case again, from a time namespace
TOTAL=$(( $(echo $TESTS | wc -w) + 1 ))

# lunatik_lookup reaches kallsyms_lookup_name through a kprobe, so without kprobes every lookup is nil
CONFIG=$({ zcat /proc/config.gz || cat "/boot/config-$(uname -r)"; } 2>/dev/null)

MODULE=lualinux
REFUSAL="not allowed once the runtime is armed"

# a lualinux without the refusal sleeps under an armed runtime's spinlock, and a run by hand reaches what is loaded
carries_refusal() {
	[ "$(cat /sys/module/$MODULE/srcversion 2> /dev/null)" = "$(modinfo -F srcversion $MODULE 2> /dev/null)" ] &&
		grep -aqF "$REFUSAL" "$(modinfo -n $MODULE 2> /dev/null)"
}

# the boottime offset, in seconds, of the namespace timens() makes, which time.lua requires from OFFSETMOD
BOOTOFFSET=1000000
OFFSETMOD="/lib/modules/lua/tests/linux/time_offset.lua"

# the CLI in a time namespace of its own: CLI=timens before run_test runs the script's body from there
timens() { unshare --time --monotonic 1000000000 --boottime $BOOTOFFSET lunatik "$@"; }

cleanup() {
	for t in $TESTS; do
		lunatik stop "tests/linux/$t" 2>/dev/null
	done
	rm -f "$OFFSETMOD"
}
trap cleanup EXIT
cleanup
echo "return {boot = 0}" > "$OFFSETMOD" # the loop's run is the initial namespace's

ktap_header
ktap_plan $TOTAL

for t in $TESTS; do
	if [ "$t" = lookup ] && [ -n "$CONFIG" ] && ! grep -q '^CONFIG_KPROBES=y' <<< "$CONFIG"; then
		ktap_skip "linux/$t: needs CONFIG_KPROBES"
		continue
	fi
	if [ "$t" = tracing ] && [ -n "$CONFIG" ] && ! grep -q '^CONFIG_TRACING=y' <<< "$CONFIG"; then
		ktap_skip "linux/$t: needs CONFIG_TRACING"
		continue
	fi
	if [ "$t" = schedule ] && ! carries_refusal; then
		ktap_skip "linux/$t: the loaded $MODULE does not carry the refusal in schedule"
		continue
	fi
	if run_test "tests/linux/$t"; then
		ktap_pass "linux/$t"
	else
		ktap_fail "linux/$t"
	fi
done

lunatik stop tests/linux/time 2> /dev/null # its run in the loop stays registered, and a second run is refused
echo "return {boot = $BOOTOFFSET}" > "$OFFSETMOD"
if ! unshare --time true 2> /dev/null; then
	ktap_skip "linux/time: from a time namespace: needs time namespaces"
elif CLI=timens run_test tests/linux/time; then
	ktap_pass "linux/time: from a time namespace"
else
	ktap_fail "linux/time: from a time namespace"
fi

RESULT=0
ktap_totals || RESULT=1

echo ""
bash "$DIR/hwaddr.sh" || RESULT=1
exit $RESULT

