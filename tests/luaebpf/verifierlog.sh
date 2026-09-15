#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests that a verifier rejection reaches the command line as the verifier's own log, with the
# Lua line the object's line_info carries, rather than as a bare errno. The program file is the
# loader's own, compiled with the emitter's test hook dropping the write to R0; load.sh loads
# the same file compiled without the hook, so the grep discriminates between a rejected program
# and any program at all. undo.sh covers what the failure leaves behind; this covers its text.
#
# Usage: sudo bash tests/luaebpf/verifierlog.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 1
luaebpf_device || fail "luaebpf: the case could not create $LUAEBPF_DEV"

output=$(luaebpf_install loader verdict)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: loader.bpf.lua did not compile"; }

output=$(lunatik run tests/luaebpf/loader dev="$LUAEBPF_DEV" 2>&1)
status=$?
lunatik stop tests/luaebpf/loader > /dev/null 2>&1
rm -rf "$LUAEBPF_ROOT/loader"

[ "$status" -ne 0 ] || { comment "$output"; fail "luaebpf: a rejected program loaded"; }
echo "$output" | grep -qE 'loader\.bpf\.lua:[0-9]+' \
	|| { comment "$output"; fail "luaebpf: the rejection does not quote the Lua line"; }
ktap_pass "luaebpf: a verifier rejection reaches the command line quoting the Lua line"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

