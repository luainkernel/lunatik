#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests what the command line owes a compiled program, refused before anything is created, so
# before the runtime starts: no root exists afterwards and `lunatik list` does not name the
# script. A misused option exits 2 with the usage, a name the loader cannot serve exits 1.
#   - an XDP program with no `--dev`, refused naming the option
#   - an execution context for a script with no kernel side to run in it
#   - a name with a dot, which bpffs refuses in a pin root and which could climb out of it
#   - a script with no object at all, which runs exactly as it did before: exit 0, the runtime
#     registered and no pin root
#
# Usage: sudo bash tests/luaebpf/notarget.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

LUAEBPF_RUNS="loader alone plain"
trap cleanup EXIT

luaebpf_start 4
luaebpf_device || fail "luaebpf: the case could not create $LUAEBPF_DEV"

output=$(luaebpf_stage loader) || { comment "$output"; fail "luaebpf: loader.bpf.lua did not compile"; }
luaebpf_undone "an XDP program with no device is refused naming the option" \
	loader 2 'tests/luaebpf/loader needs --dev'

output=$(luaebpf_stage alone) || { comment "$output"; fail "luaebpf: alone.bpf.lua did not compile"; }
luaebpf_undone "an execution context is refused where there is no kernel script to take it" \
	alone 2 'has no kernel script' --context=softirq --dev="$LUAEBPF_DEV"

luaebpf_undone "a name with a dot is refused before a root is made of it" \
	../luaebpf/loader 1 'a root takes no dot' --dev="$LUAEBPF_DEV"

output=$(lunatik run tests/luaebpf/plain 2>&1)
status=$?
listed=$(lunatik list)
rooted=$(ls -d "$LUAEBPF_ROOT/plain" 2>/dev/null)
lunatik stop tests/luaebpf/plain > /dev/null 2>&1

[ "$status" -eq 0 ] && [ -z "$output" ] || { comment "$output"; fail "luaebpf: the run of plain exited $status"; }
[ -z "$rooted" ] || fail "luaebpf: a script with no object made '$rooted'"
grep -qxF tests/luaebpf/plain <<< "$listed" || fail "luaebpf: a script with no object registered no runtime"
ktap_pass "luaebpf: a script with no compiled program runs as it did before, with no pin root"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

