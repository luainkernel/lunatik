#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests what `lunatik run` leaves behind for a script whose compiled program is installed
# beside it.
#   - the map the program file declares is pinned under the script's own root, the runtime is
#     registered, the link is pinned and the program id the device reports is the one the
#     pinned link holds. The order the loader promises is read off the kernel script's own
#     line: it opens the map by its pin path, which it could only do if the map was pinned
#     before the runtime started
#   - a script with an object and no kernel script runs the program alone: the link is pinned
#     and nothing is registered
#
# Usage: sudo bash tests/luaebpf/load.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 2
luaebpf_device || fail "luaebpf: the case could not create $LUAEBPF_DEV"

output=$(luaebpf_install loader) || { comment "$output"; fail "luaebpf: loader.bpf.lua did not compile"; }

mark_dmesg
output=$(lunatik run tests/luaebpf/loader dev="$LUAEBPF_DEV" 2>&1)
status=$?
pinned=$(ls "$LUAEBPF_ROOT/loader" 2>/dev/null | sort | tr '\n' ' ')
listed=$(lunatik list)
opened=$(dmesg_since | grep -c "luaebpf loader test pass")
linked=$(bpftool -j link show pinned "$LUAEBPF_ROOT/loader/loader-link" 2>/dev/null \
	| grep -oP '"prog_id":\K[0-9]+')
attached=$(bpftool net show dev "$LUAEBPF_DEV" | grep -oP 'driver id \K[0-9]+')
lunatik stop tests/luaebpf/loader > /dev/null 2>&1

[ "$status" -eq 0 ] || { comment "$output"; fail "luaebpf: the run exited $status"; }
[ -z "$output" ] || { comment "$output"; fail "luaebpf: the run printed something"; }
[ "$pinned" = "counts loader-link " ] || fail "luaebpf: the script's root holds '$pinned'"
case "$listed" in
*tests/luaebpf/loader*) ;;
*) fail "luaebpf: lunatik list says '$listed'" ;;
esac
[ "$opened" -eq 1 ] || fail "luaebpf: the kernel script did not open the map by its pin path"
[ -n "$linked" ] && [ "$linked" = "$attached" ] \
	|| fail "luaebpf: $LUAEBPF_DEV carries program '$attached', the pinned link holds '$linked'"
ktap_pass "luaebpf: a run pins the maps, starts the runtime and pins the link it attached"

output=$(luaebpf_install alone) || { comment "$output"; fail "luaebpf: alone.bpf.lua did not compile"; }

output=$(lunatik run tests/luaebpf/alone dev="$LUAEBPF_DEV" 2>&1)
status=$?
pinned=$(ls "$LUAEBPF_ROOT/alone" 2>/dev/null | tr '\n' ' ')
listed=$(lunatik list)
lunatik stop tests/luaebpf/alone > /dev/null 2>&1

[ "$status" -eq 0 ] || { comment "$output"; fail "luaebpf: the run of a program alone exited $status"; }
[ "$pinned" = "alone-link " ] || fail "luaebpf: the root of a program with no script holds '$pinned'"
case "$listed" in
*tests/luaebpf/alone*) fail "luaebpf: a program with no kernel script registered a runtime" ;;
esac
ktap_pass "luaebpf: a script with a program and no kernel script runs the program alone"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

