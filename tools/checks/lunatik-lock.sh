#!/usr/bin/env bash
# PreToolUse (Bash) hook: one lunatik operation at a time. Concurrent ones wedge
# /dev/lunatik and leave processes in D state, which only a reboot clears, so a
# command that touches the device is refused (exit 2) while another is running:
# a CLI process, which the shebang shows as lua5.4 .../sbin/lunatik and, once its
# command line is gone, as [lunatik]; or a test script, installed or in the tree.
# Reads the tool command on stdin. Pass LUNATIK_LOCK_OK=1 to override, once the
# processes it names are known to be stale.

input=$(cat)

case "$input" in
	*"lunatik test"*|*"lunatik reload"*|*"lunatik load"*|*"lunatik unload"*|\
	*"lunatik run"*|*"lunatik spawn"*|*"lunatik stop"*|*"make install"*|\
	*"bash tests/"*|*"/run.sh"*|*"watchdog.sh"*) ;;
	*) exit 0 ;;
esac
case "$input" in
	*LUNATIK_LOCK_OK=1*) exit 0 ;;
esac

busy=$(ps -eo pid,stat,args | awk '
	$3 == "[lunatik]" || ($3 ~ /lua/ && $4 ~ /bin\/lunatik$/) ||
	($3 ~ /(^|\/)(ba)?sh$/ && $4 ~ /tests\/([a-z]+\/)*[a-z_]+\.sh$/) { print "  " $0 }')
[ -n "$busy" ] || exit 0

{
	echo "lunatik-lock: the device is busy; a second operation wedges it:"
	echo "$busy"
	echo "lunatik-lock: wait for it; one in D state never returns, and only a reboot clears it. Re-run with LUNATIK_LOCK_OK=1 as a command prefix only when what is listed is known to be stale."
} >&2
exit 2

