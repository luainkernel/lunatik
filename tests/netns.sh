#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Shared setup for the tests that talk to a network namespace of their own.
# Source it after lib.sh, with NETNS set to the namespace's name.
#
# A kernel script reaches a namespace through the pid of a task inside it, the
# pid socket.new takes, so netns_up creates the named namespace and keeps a
# process there, NSPID, which enters that namespace and no other; the test hands
# the pid to its script as the module PIDMOD. netns_down undoes all of it, and
# runs in the trap and once up front.

PIDMOD="/lib/modules/lua/tests/netns_pid.lua"
# bounds a process a killed run leaves holding the namespace
NETNS_HOLD=300

netns_up() {
	local ns

	ip netns add "$NETNS" 2> /dev/null || return 1
	nsenter --net="/run/netns/$NETNS" sleep "$NETNS_HOLD" &
	NSPID=$!
	disown "$NSPID" # the test kills it, and bash would report that on the KTAP output
	ns=$(stat -Lc %i "/run/netns/$NETNS")
	for _ in $(seq 1 50); do
		[ "$(stat -Lc %i "/proc/$NSPID/ns/net" 2> /dev/null)" = "$ns" ] && return 0
		sleep 0.1
	done
	return 1
}

netns_down() {
	rm -f "$PIDMOD"
	[ -n "$NSPID" ] && kill "$NSPID" 2> /dev/null
	ip netns pids "$NETNS" 2> /dev/null | xargs -r kill 2> /dev/null
	ip netns del "$NETNS" 2> /dev/null
}

