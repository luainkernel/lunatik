#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the object a constant-verdict program compiles into.
#   - a file declaring two programs compiles, and loadall pins one program per xdp.program call
#   - prog run returns the verdict each program's function returns
#   - a program returning nil takes its default verdict, as one returning nothing does, since
#     the hook reads the two alike
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

output=$(luaebpf_loadall pass) || { comment "$output"; fail "luaebpf: the object did not load"; }
[ -e "$LUAEBPF_PINS/pass" ] && [ -e "$LUAEBPF_PINS/drop" ] \
	|| fail "luaebpf: loadall pinned $(ls "$LUAEBPF_PINS" | tr '\n' ' ')"
ktap_pass "luaebpf: loadall pins one program per xdp.program call"

verdict=$(luaebpf_verdict pass)
[ "$verdict" = "2" ] || fail "luaebpf: the PASS program returned '$verdict'"
verdict=$(luaebpf_verdict drop)
[ "$verdict" = "1" ] || fail "luaebpf: the DROP program returned '$verdict'"
ktap_pass "luaebpf: prog run returns the verdict the function returns"

cat > "$LUAEBPF_WORK/nilverdict.bpf.lua" <<'LUA'
local xdp    = require("bpf.xdp")
local action = require("linux.xdp").action

xdp.program(function(_)
	return
end, {name = "none", default = action.DROP})

return xdp.program(function(_)
	return nil
end, {name = "explicit", default = action.DROP})
LUA
output=$(cd "$LUAEBPF_WORK" && luaebpf_bpf "$LUAEBPF_WORK/nilverdict.bpf.o" "$LUAEBPF_WORK/nilverdict.bpf.lua" 2>&1) \
	&& output=$(bpftool prog loadall "$LUAEBPF_WORK/nilverdict.bpf.o" "$LUAEBPF_PINS" type xdp 2>&1) \
	|| { comment "$output"; fail "luaebpf: the programs returning nil did not compile and load"; }
none=$(luaebpf_verdict none)
explicit=$(luaebpf_verdict explicit)
[ "$none" = "1" ] && [ "$explicit" = "1" ] \
	|| fail "luaebpf: returning nothing gave '$none' and returning nil '$explicit', not the default 1"
ktap_pass "luaebpf: returning nil takes the default verdict, as returning nothing does"

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

