#!/usr/bin/env bash
# PreToolUse (Bash) hook: one lunatik operation at a time. Concurrent ones wedge
# /dev/lunatik and leave processes in D state, which only a reboot clears, so a
# command that touches the device is refused (exit 2) while another is running.
# Reads the tool command on stdin. Pass LUNATIK_LOCK_OK=1 to override, once the
# processes it names are known to be stale.

input=$(cat)

case "$input" in
	*"lunatik test"*|*"lunatik reload"*|*"lunatik load"*|*"lunatik unload"*|\
	*"lunatik run"*|*"lunatik spawn"*|*"lunatik stop"*|*"make install"*) ;;
	*) exit 0 ;;
esac
case "$input" in
	*LUNATIK_LOCK_OK=1*) exit 0 ;;
esac

busy=$(ps -eo pid,stat,args | awk '
	$3 ~ /lunatik$/ || $0 ~ /sbin\/lunatik (test|reload|load|unload|run|spawn|stop)/ ||
	$0 ~ /share\/lunatik\/tests/ || $0 ~ /tests\/[a-z]+\/run\.sh/ { print "  " $0 }')
[ -n "$busy" ] || exit 0

{
	echo "lunatik-lock: the device is busy; a second operation wedges it."
	echo "$busy"
	echo "Wait for it to finish. A process in D state never will: that is a wedged device,"
	echo "which the maintainer clears with a reboot. Override with LUNATIK_LOCK_OK=1 only"
	echo "when what is listed is known to be stale."
} >&2
exit 2

