#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Saves what a reboot erases, for every session on the host and not only the one that asks for the
# reboot, into scratch/reboot-<time>/ of the checkout: the last oops, the Lunatik modules loaded with
# what holds them and the build they came from, the processes in D state, and the files each session
# keeps under /tmp/claude-<uid>/<project>/<session>, where Claude Code puts a session's scratchpad.
#
# Usage: bash tools/prereboot.sh

common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || { echo "prereboot: not in a checkout" >&2; exit 1; }
out="$(dirname "$common")/scratch/reboot-$(date +%F-%H%M)"
mkdir -p "$out" || exit 1

{
	echo "== $(date) $(uname -r), up since $(uptime -s)"
	echo "== modules"
	lsmod | awk 'NR == 1 || /^lua/'
	for module in /sys/module/lua* /sys/module/lunatik*; do
		[ -d "$module" ] || continue
		echo "${module##*/} refcnt=$(cat "$module/refcnt") srcversion=$(cat "$module/srcversion" 2>/dev/null)" \
			"holders=$(ls "$module/holders" | tr '\n' ' ')"
	done
	installed=$(modinfo -n lunatik 2>/dev/null)
	echo "== installed: $installed, $(stat -c %y "$installed" 2>/dev/null)"
	echo "== host lock: $(cat /tmp/lunatik-host/lock.holder 2>/dev/null || echo free)"
	echo "== processes in D state"
	ps -eo pid,stat,etime,cmd | awk 'NR == 1 || $2 ~ /D/'
} > "$out/state.txt"

bash "$(dirname "$0")/oops.sh" > "$out/oops.txt" 2> /dev/null || rm -f "$out/oops.txt"

for session in /tmp/claude-"$(id -u)"/*/*/; do
	[ -n "$(ls -A "$session")" ] || continue
	project=$(basename "$(dirname "$session")")
	[ "$project" = bash-edit-diff ] && continue # Claude Code's own state, not a session's
	mkdir -p "$out/tmp/$project" && cp -a "${session%/}" "$out/tmp/$project/"
done

echo "prereboot: saved under $out"
(cd "$out" && find . -maxdepth 3 -mindepth 1 | sort | sed 's|^\./|  |')

