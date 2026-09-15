#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the object a constant-verdict program compiles into.
#   - a file declaring two programs compiles, and loadall pins one program per xdp.program call
#   - with no -o the object takes the input's own name
#   - prog run returns the verdict each program's function returns
#   - the license section reads Dual MIT/GPL, which is what libbpf accepts for a GPL helper
#   - the object's BTF carries one FUNC per program
#
# Usage: sudo bash tests/luaebpf/pass.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 6

output=$(luaebpf_compile pass) || { comment "$output"; fail "luaebpf: pass.bpf.lua did not compile"; }
ktap_pass "luaebpf: a file declaring two programs compiles"

mkdir -p "$LUAEBPF_WORK/noout" && cp "$LUAEBPF_SRC/pass.bpf.lua" "$LUAEBPF_WORK/noout/"
( cd "$LUAEBPF_WORK/noout" && lunatikc bpf pass.bpf.lua ) > /dev/null 2>&1
[ -s "$LUAEBPF_WORK/noout/pass.bpf.o" ] \
	|| fail "luaebpf: with no -o the object is $(ls "$LUAEBPF_WORK/noout" | tr '\n' ' ')"
ktap_pass "luaebpf: with no -o the object is named after the input"

output=$(luaebpf_loadall pass) || { comment "$output"; fail "luaebpf: the object did not load"; }
[ -e "$LUAEBPF_PINS/pass" ] && [ -e "$LUAEBPF_PINS/drop" ] \
	|| fail "luaebpf: loadall pinned $(ls "$LUAEBPF_PINS" | tr '\n' ' ')"
ktap_pass "luaebpf: loadall pins one program per xdp.program call"

verdict=$(luaebpf_verdict pass)
[ "$verdict" = "2" ] || fail "luaebpf: the PASS program returned '$verdict'"
verdict=$(luaebpf_verdict drop)
[ "$verdict" = "1" ] || fail "luaebpf: the DROP program returned '$verdict'"
ktap_pass "luaebpf: prog run returns the verdict the function returns"

license=$(strings "$LUAEBPF_WORK/pass.bpf.o" | grep -x "Dual MIT/GPL")
[ -n "$license" ] || fail "luaebpf: the object's license section does not read Dual MIT/GPL"
ktap_pass "luaebpf: the object is licensed Dual MIT/GPL"

funcs=$(bpftool btf dump file "$LUAEBPF_WORK/pass.bpf.o" | grep -c "FUNC '")
[ "$funcs" = "2" ] || fail "luaebpf: the BTF carries $funcs FUNC entries, not 2"
bpftool btf dump file "$LUAEBPF_WORK/pass.bpf.o" | grep -q "FUNC 'pass'" \
	|| fail "luaebpf: the BTF does not name the program"
ktap_pass "luaebpf: the BTF carries one FUNC per program"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

