#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs all ebpf tests and reports aggregated KTAP results.
#
# Usage: sudo bash tests/ebpf/run.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

BPF_FS=/sys/fs/bpf
MAP=$BPF_FS/test_map

cleanup()
{
	rm -f "$MAP"
}

trap cleanup EXIT

cleanup

if ! mountpoint -q "$BPF_FS"; then
    mount -t bpf bpf "$BPF_FS"
fi

bpftool map create \
	"$MAP" \
	type hash \
	key 3 \
	value 3 \
	entries 128 \
	name test_map >/dev/null

bpftool map update \
	pinned "$MAP" \
	key hex 66 6f 6f \
	value hex 62 61 72

TESTS="map_values"
TOTAL=$(echo $TESTS | wc -w)

ktap_header
ktap_plan $TOTAL

for t in $TESTS; do
	mark_dmesg

	if ! lunatik run "tests/ebpf/$t" 2>/dev/null; then
		ktap_fail "ebpf/$t: script execution failed"
		continue
	fi

	errs=$(dmesg_since | grep -iE "^[^:]+: FAIL	|\.lua:[0-9]+:" || true)

	if [ -z "$errs" ]; then
		ktap_pass "ebpf/$t"
	else
		ktap_fail "ebpf/$t"
		while IFS= read -r line; do
			echo "# $line"
		done <<< "$errs"
	fi
done

ktap_totals
exit $?

