#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs a command that reaches the network until it succeeds, up to <tries> times, <delay> seconds
# apart, and exits with its last status. A CI job that installs packages or downloads a release
# otherwise fails on the first mirror that times out.
# Usage: bash tools/retry.sh <tries> <delay> <command>...

tries=$1 delay=$2
shift 2

for ((try = 1; ; try++)); do
	"$@" && exit 0
	status=$?
	((try < tries)) || exit $status
	echo "retry: '$*' exited $status, try $((try + 1)) of $tries in ${delay}s" >&2
	sleep "$delay"
done

