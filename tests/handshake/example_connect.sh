#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs the tls_connect example as the tree installs it. With no agent on the
# host the client hello is where the example stops, so ESRCH is the reading
# that socket.new and connect ran before it and the socket reached the upcall
# connected and carrying a file. A listener holds the port the example dials
# for the length of the run, since a socket that never connected answers
# ECONNREFUSED before the upcall is reached at all.
#
# This is not socket_tls.sh a second time: that one drives a test script
# through the same three calls, this one drives the file the tree ships, which
# is what rots when a binding it calls is reshaped. A broken example answers
# with a loader or a Lua error instead of the bare errno, so the assertion is
# that the run said exactly ESRCH.
#
# What the run reaches is the example down to the hello. The keyed socket a
# completed handshake hands back is not covered, and neither are the setsockopt,
# the send and the receive the example makes on it, which sit below the raise:
# all of that needs ktls-utils on the host. Skipped whole where tlshd is
# installed or running, for the same reason socket_tls.sh is, and where the
# example is not installed.
#
# Usage: sudo bash tests/handshake/example_connect.sh

SCRIPT="examples/tls_connect"
LISTENER="tests/handshake/example_listener"
MODULE="luahandshake"
EXAMPLE="/lib/modules/lua/examples/tls_connect.lua"

# what tls_client_hello_anon answers where genl_has_listeners finds no agent
NOAGENT="ESRCH"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	lunatik stop "$LISTENER" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

CASE="example_connect: the client example reaches the upcall"

ktap_header
ktap_plan 1

skip_all()
{
	echo "# SKIP: $1"
	ktap_skip "$CASE"
	ktap_totals
	exit 0
}

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || skip_all "$MODULE not loaded"
[ -f "$EXAMPLE" ] || skip_all "the tls_connect example is not installed"
command -v tlshd > /dev/null 2>&1 && skip_all "tlshd is installed, so an agent may answer"
pgrep -x tlshd > /dev/null 2>&1 && skip_all "a tlshd process is running"

mark_dmesg
run_script "$LISTENER"
out=$(lunatik run "$SCRIPT" 2>&1)

# both scripts are stopped before the verdict is read
cleanup
check_dmesg || { ktap_totals; exit 1; }

[ "$out" = "$NOAGENT" ] || fail "$CASE: lunatik run said: $out"
ktap_pass "$CASE"

ktap_totals

