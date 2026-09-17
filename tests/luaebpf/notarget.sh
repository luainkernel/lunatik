#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests what the command line owes a compiled program, and the row that keeps the loader out of
# the path it does not own. Every refusal here is read before anything is created, which is what
# "before the runtime starts" means: the checks are that no root exists and that `lunatik list`
# does not name the script.
#   - an XDP program with no `dev=`, refused with the option named
#   - an option the object does not ask for, named back
#   - an execution context for a script that has no kernel side to run it
#   - a script with no object at all, which runs exactly as it did before: exit 0, the runtime
#     registered and no pin root
#
# Usage: sudo bash tests/luaebpf/notarget.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 4
luaebpf_device || fail "luaebpf: the case could not create $LUAEBPF_DEV"

output=$(luaebpf_install loader)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: loader.bpf.lua did not compile"; }
luaebpf_undone "an XDP program with no device is refused with the option named" \
	loader 'needs dev='
luaebpf_undone "an option the object does not ask for is refused by name" \
	loader "takes no 'foo'" dev="$LUAEBPF_DEV" foo=bar

output=$(luaebpf_install alone)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: alone.bpf.lua did not compile"; }
luaebpf_undone "an execution context is refused where there is no kernel script to take it" \
	alone "has no kernel script for 'softirq'" softirq dev="$LUAEBPF_DEV"

output=$(lunatik run tests/luaebpf/plain 2>&1)
status=$?
listed=$(lunatik list)
rooted=$(ls -d "$LUAEBPF_ROOT/plain" 2>/dev/null)
lunatik stop tests/luaebpf/plain > /dev/null 2>&1

[ "$status" -eq 0 ] && [ -z "$output" ] \
	|| { comment "$output"; fail "luaebpf: a script with no object exited $status"; }
[ -z "$rooted" ] || fail "luaebpf: a script with no object created '$rooted'"
case "$listed" in
*tests/luaebpf/plain*) ;;
*) fail "luaebpf: a script with no object did not register a runtime" ;;
esac
ktap_pass "luaebpf: a script with no compiled program runs as it did before, with no pin root"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

