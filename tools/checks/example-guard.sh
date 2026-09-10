#!/usr/bin/env bash
# PreToolUse (Bash) hook: an example is loaded through tools/watchdog.sh, which
# stops it when the host loses the connectivity it had. An example arms real
# hooks on the machine that runs it, and one that cuts the network off cannot be
# stopped afterwards: the command that would stop it has nowhere to be typed.
# Blocks (exit 2) a lunatik run or spawn of anything under examples/ that does
# not go through the watchdog. Reads the tool command on stdin. Pass
# NETWORK_LOSS_OK=1 to run one bare, on a machine whose connectivity is expendable.

input=$(cat)

case "$input" in
	*"lunatik run examples/"*|*"lunatik spawn examples/"*) ;;
	*) exit 0 ;;
esac
case "$input" in
	*NETWORK_LOSS_OK=1*|*watchdog.sh*) exit 0 ;;
esac

{
	echo "example-guard: load an example through the watchdog, which stops it if the host loses the connectivity it had:"
	echo "  sudo bash tools/watchdog.sh <script> [softirq|hardirq] [percpu]"
	echo "example-guard: an example that takes the network down cannot be stopped by hand afterwards. Re-run with NETWORK_LOSS_OK=1 as a command prefix only on a machine whose connectivity is expendable."
} >&2
exit 2

