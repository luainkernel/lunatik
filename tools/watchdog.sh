#!/usr/bin/env bash
# Runs a Lunatik script and stops it if the host loses the connectivity it had
# before the run: a script that cuts the machine off cannot be stopped by hand
# afterwards, since the terminal that would type the command is gone.
#
# It compares against what worked before the run and nothing else: the loopback,
# and the gateway of the default route when there is one. A check that already
# failed is not held against the script.
#
# Usage: sudo bash tools/watchdog.sh <script> [softirq|hardirq] [percpu]
#        LUNATIK_WATCHDOG_GRACE=<seconds> before the check, default 3

GRACE=${LUNATIK_WATCHDOG_GRACE:-3}
SCRIPT=$1

[ -n "$SCRIPT" ] || { echo "usage: $0 <script> [softirq|hardirq] [percpu]" >&2; exit 2; }
shift

reachable() { ping -c 1 -W 1 "$1" > /dev/null 2>&1; }

gateway=$(ip route show default 2>/dev/null | awk '/^default/ {print $3; exit}')

targets=""
for t in 127.0.0.1 $gateway; do
	reachable "$t" && targets="$targets $t"
done
[ -n "$targets" ] || echo "# watchdog: nothing was reachable before the run, nothing to compare against"

lunatik run "$SCRIPT" "$@" || exit $?
sleep "$GRACE"

lost=""
for t in $targets; do
	reachable "$t" || lost="$lost $t"
done
[ -n "$lost" ] || exit 0

echo "watchdog: $SCRIPT took the host off the network, unreachable now:$lost; stopping it" >&2
if timeout 30 lunatik stop "$SCRIPT"; then
	for t in $lost; do
		reachable "$t" || echo "watchdog: $t is still unreachable after the stop" >&2
	done
else
	echo "watchdog: the stop did not return; the device is wedged and only a reboot clears it" >&2
fi
exit 1

