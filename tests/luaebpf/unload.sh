#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests what `lunatik unload` takes down, which `reload` and `lunatik test` run through.
#   - an unload takes down every compiled program a run attached, the one beside a kernel script
#     and the one with no kernel script, which has no runtime for the shutdown to stop: neither
#     device carries a program and nothing is left under /sys/fs/bpf/lunatik, even while another
#     pin holds a link, so the program is off the device only because the unload detached it
#   - an unload that cannot detach a pin under a link's name, a map the case pins there, still
#     detaches the other roots and removes the tree, then exits 1 with the detach's message before
#     it stops the runtimes, which a second unload then stops
#   - an unload by a user other than root exits 1 with only the device's refusal on stderr: the
#     walk of /sys/fs/bpf it cannot read says nothing
#
# Usage: sudo bash tests/luaebpf/unload.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

PINS_PATH=/sys/fs/bpf/lunatik

LUAEBPF_RUNS="loader alone"
trap cleanup EXIT

luaebpf_start 3
luaebpf_device || fail "luaebpf: the case could not create $LUAEBPF_DEV"
output=$(luaebpf_stage loader) || { comment "$output"; fail "luaebpf: loader.bpf.lua did not compile"; }
output=$(luaebpf_stage alone) || { comment "$output"; fail "luaebpf: alone.bpf.lua did not compile"; }

output=$(lunatik run --dev="$LUAEBPF_DEV" tests/luaebpf/loader 2>&1)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: the run of loader the unload is measured against failed"; }
output=$(lunatik run --dev="$LUAEBPF_PEER" tests/luaebpf/alone 2>&1)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: the run of alone the unload is measured against failed"; }
bpftool link pin pinned "$LUAEBPF_ROOT/loader/loader-link" "$LUAEBPF_PINS/held" ||
	fail "luaebpf: the case could not pin the link a second time"
output=$(lunatik unload 2>&1)
status=$?
left=$(find "$PINS_PATH" 2>/dev/null | tr '\n' ' ')
attached=$(luaebpf_attached)
alone=$(luaebpf_attached "$LUAEBPF_PEER")
rm -f "$LUAEBPF_PINS/held"
lunatik load || fail "luaebpf: the modules did not load again"

[ "$status" -eq 0 ] && [ -z "$output" ] || { comment "$output"; fail "luaebpf: the unload exited $status"; }
[ -z "$left" ] || fail "luaebpf: the unload left '$left'"
[ -z "$attached" ] && [ -z "$alone" ] ||
	fail "luaebpf: the unload left program '$attached' on $LUAEBPF_DEV and '$alone' on $LUAEBPF_PEER"
ktap_pass "luaebpf: an unload detaches every link and removes the pins, a program with no kernel script included"

output=$(lunatik run --dev="$LUAEBPF_DEV" tests/luaebpf/loader 2>&1)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: the run of loader the failed detach is measured against failed"; }
mkdir -p "$LUAEBPF_ROOT/stale"
bpftool map create "$LUAEBPF_ROOT/stale/stale-link" type array key 4 value 4 entries 1 name stale ||
	fail "luaebpf: the case could not pin a map under a link's name"
output=$(lunatik unload 2> "$LUAEBPF_WORK/stderr")
status=$?
err=$(< "$LUAEBPF_WORK/stderr")
left=$(find "$PINS_PATH" 2>/dev/null | tr '\n' ' ')
attached=$(luaebpf_attached)
lunatik unload > /dev/null 2>&1
lunatik load || fail "luaebpf: the modules did not load again"

[ "$status" -eq 1 ] && [ -z "$output" ] && grep -qE "^lunatik: couldn't (open|detach) $LUAEBPF_ROOT/stale/stale-link" <<< "$err" ||
	{ comment "$err"; fail "luaebpf: the unload with a pin it cannot detach exited $status"; }
[ -z "$left" ] || fail "luaebpf: the unload with a pin it cannot detach left '$left'"
[ -z "$attached" ] || fail "luaebpf: the unload with a pin it cannot detach left program '$attached' on $LUAEBPF_DEV"
ktap_pass "luaebpf: an unload that cannot detach a pin detaches the others, removes the tree and exits 1"

output=$(setpriv --reuid=65534 --regid=65534 --clear-groups lunatik unload 2> "$LUAEBPF_WORK/stderr")
status=$?
err=$(< "$LUAEBPF_WORK/stderr")

[ "$status" -eq 1 ] && [ -z "$output" ] && [ "$err" = "lunatik: /dev/lunatik: Permission denied" ] ||
	{ comment "$err"; fail "luaebpf: the unload by another user exited $status"; }
ktap_pass "luaebpf: an unload by a user other than root prints only the device's refusal"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

