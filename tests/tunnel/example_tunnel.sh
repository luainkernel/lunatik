#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Drives the tlstunnel example as it is installed, rather than a copy of it:
# both example scripts are spawned, a client script connects to the example's
# own plain port, and what crossed is read out of the kernel log. It is the
# example that rots when a binding it calls is reshaped, so the file the tree
# ships is the one under test here.
#
# The record type the upstream reports is the case that separates "the relay
# worked" from "the relay worked over kTLS": on a leg that is not keyed
# receiverecord reports nil, so reading 23 is the record layer's signature. The
# stop is measured and the elapsed milliseconds are printed, the way plain.sh
# does it for the module, since a thread that does not come back round its loop
# is one kthread_stop waits on and the number is the proof rather than the
# absence of a hang.
#
# A connection that fails is the case for the two accept loops: plaintext at the
# upstream's port is no record its keyed leg can read, and a relay whose
# upstream has been stopped is refused its connect, so each half meets a failure
# of its own and the client after them has to be served all the same.
#
# Two clients at once are not covered: the example serves one connection at a
# time by design, and the README says so. A handshake in place of the fixed
# vectors is not covered either, since no host in reach carries an agent;
# tests/handshake/example_connect.sh is that path's cover.
#
# Each listener is bound in its script body rather than in the thread, so the
# last case takes the relay's port first and reads the answer off the spawn.
#
# Skipped whole where the example is not installed, or where the tls ULP is
# neither registered nor loadable.
#
# Usage: sudo bash tests/tunnel/example_tunnel.sh

SCRIPT="examples/tlstunnel/tunnel"
UPSTREAM="examples/tlstunnel/upstream"
CLIENT="tests/tunnel/example_client"
STRAY="tests/tunnel/example_stray"
HOLDER="tests/tunnel/example_holder"
MODULE="luasocket"
EXAMPLE="/lib/modules/lua/examples/tlstunnel"

# the first line of the request example_client.lua sends and of the reply
# upstream.lua answers, as the exact bytes
REQUEST="GET /tunnel HTTP/1.0"
REPLY="HTTP/1.0 200 OK"
# the TLS content type of application data
DATA=23
# the clients the relay serves: one before the two failures and one after
SERVED=2
# what a bind of a port another socket is listening on answers
TAKEN="EADDRINUSE"

# what the two stops must beat: both scripts poll their accept every 10 ms and
# the relay bounds each send at 100 ms, so a pair of stops taking a second is
# not a bounded call returning
STOPBOUND=1000

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$CLIENT" > /dev/null 2>&1
	lunatik stop "$STRAY" > /dev/null 2>&1
	lunatik stop "$HOLDER" > /dev/null 2>&1
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	lunatik stop "$UPSTREAM" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

CASES=(
	"example_tunnel: the client's request reaches the upstream through the relay"
	"example_tunnel: it arrives there as application data, so the kTLS leg carried it"
	"example_tunnel: the upstream's reply reaches the client"
	"example_tunnel: the relay's transform sees what crosses in either direction"
	"example_tunnel: a connection that fails ends itself and not the loop serving the next"
	"example_tunnel: both scripts stop and leave nothing running"
	"example_tunnel: a port already taken is the spawn's answer, not the thread's"
)

ktap_header
ktap_plan ${#CASES[@]}

skip_all()
{
	echo "# SKIP: $1"
	for c in "${CASES[@]}"; do ktap_skip "$c"; done
	ktap_totals
	exit 0
}

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || skip_all "$MODULE not loaded"
[ -d "$EXAMPLE" ] || skip_all "the tlstunnel example is not installed"

# registered (built in, or already loaded), or loadable: the attach autoloads
# through request_module("tcp-ulp-tls")
grep -qw tls /proc/sys/net/ipv4/tcp_available_ulp 2> /dev/null ||
	grep -q '^alias tcp-ulp-tls ' "/lib/modules/$(uname -r)/modules.alias" 2> /dev/null ||
	skip_all "the tls ULP is neither registered nor loadable"

spawn_example()
{
	local out
	out=$(lunatik spawn "$1" 2>&1)
	[ -z "$out" ] || fail "$2: lunatik spawn $1 said: $out"
}

mark_dmesg
# the upstream first: the relay connects to it as soon as a client arrives
spawn_example "$UPSTREAM" "${CASES[0]}"
spawn_example "$SCRIPT" "${CASES[0]}"
run_script "$CLIENT"
lunatik stop "$CLIENT" > /dev/null 2>&1

# a failure for each half, then the client that has to be served after them
run_script "$STRAY"
lunatik stop "$STRAY" > /dev/null 2>&1
lunatik stop "$UPSTREAM" > /dev/null 2>&1
refused=$(lunatik run "$CLIENT" 2>&1)
lunatik stop "$CLIENT" > /dev/null 2>&1
spawn_example "$UPSTREAM" "${CASES[4]}"
after=$(lunatik run "$CLIENT" 2>&1)

# everything this case started is stopped before the first check, so a failing
# check leaves nothing for the next run to trip on
lunatik stop "$CLIENT" > /dev/null 2>&1
started=$(date +%s%N)
lunatik stop "$SCRIPT" > /dev/null 2>&1
lunatik stop "$UPSTREAM" > /dev/null 2>&1
elapsed=$(( ($(date +%s%N) - started) / 1000000 ))
running=$(lunatik list)
comment "both stops returned in $elapsed ms"

# the relay's own port, held while it is stopped, so the bind the script body
# makes is the one that fails
run_script "$HOLDER"
taken=$(lunatik spawn "$SCRIPT" 2>&1)
lunatik stop "$SCRIPT" > /dev/null 2>&1
lunatik stop "$HOLDER" > /dev/null 2>&1

check_dmesg || { ktap_totals; exit 1; }

dmesg_since | grep -q "tlstunnel upstream: read $REQUEST as record" || fail "${CASES[0]}"
ktap_pass "${CASES[0]}"

dmesg_since | grep -q "tlstunnel upstream: read $REQUEST as record $DATA$" || fail "${CASES[1]}"
ktap_pass "${CASES[1]}"

dmesg_since | grep -q "tlstunnel client: read $REPLY$" || fail "${CASES[2]}"
ktap_pass "${CASES[2]}"

dmesg_since | grep -q "tlstunnel relay: $REQUEST$" || fail "${CASES[3]}: the request never reached the transform"
dmesg_since | grep -q "tlstunnel relay: $REPLY$" || fail "${CASES[3]}: the reply never reached the transform"
ktap_pass "${CASES[3]}"

dmesg_since | grep -q "tlstunnel upstream: connection failed" || fail "${CASES[4]}: the upstream took the stray connection"
[ -z "$refused" ] || fail "${CASES[4]}: the client that met the stopped upstream said: $refused"
dmesg_since | grep -q "tlstunnel relay: connection failed" || fail "${CASES[4]}: the relay reached the stopped upstream"
[ -z "$after" ] || fail "${CASES[4]}: the client after them said: $after"
served=$(dmesg_since | grep -c "tlstunnel client: read $REPLY$")
[ "$served" = "$SERVED" ] || fail "${CASES[4]}: $served clients were served"
ktap_pass "${CASES[4]}"

[ "$elapsed" -lt "$STOPBOUND" ] || fail "${CASES[5]}: the stops took $elapsed ms"
case "$running" in *tlstunnel*|*example_client*|*example_stray*) fail "${CASES[5]}: lunatik list says $running";; esac
ktap_pass "${CASES[5]}"

[ "$taken" = "$TAKEN" ] || fail "${CASES[6]}: the spawn said: $taken"
ktap_pass "${CASES[6]}"

ktap_totals

