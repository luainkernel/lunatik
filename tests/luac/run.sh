#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the bytecode compiler: compiles the installed test scripts with lunatikc on the host,
# installs the chunks under /lib/modules/lua/tests/luac and runs them in the kernel.
#   - a compiled chunk runs, full and stripped (-s), with integer semantics
#   - a compiled library is found by require()
#   - errors name the chunk name given with -n; stripped errors are "?:?:"
#   - a chunk with a stock (float) number format is rejected by the header check
#   - load() with mode "t" rejects a chunk inside the kernel
#   - the tool's own refusals leave no output: a syntax error, a binary input, several inputs
#     with -n; and the default output is <input>.luac next to the input
#
# Usage: sudo bash tests/luac/run.sh

SCRIPT="tests/luac/hello_bc"
SCRIPTS_PATH="/lib/modules/lua"
SRC="$SCRIPTS_PATH/tests/luac"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	rm -f "$SRC"/*_bc.lua "$SRC"/*_s.lua "$SRC"/stock.lua "$SRC"/bad.lua "$SRC"/*.luac
}
trap cleanup EXIT
cleanup

skip() { ktap_header; ktap_plan 1; ktap_skip "$1"; ktap_totals; exit 0; }
command -v lunatikc >/dev/null || skip "luac: lunatikc not installed"

ktap_header
ktap_plan 12

# name the chunks as the kernel will see them, so that error messages point at the installed file
compile() {
	local name="$1" strip="$2"; shift 2
	lunatikc $strip -n "@$SRC/$name.lua" -o "$SRC/$name.lua" "$@"
}

compile hello_bc "" "$SRC/hello.lua" || fail "luac: compile hello"
compile hello_s -s "$SRC/hello.lua" || fail "luac: compile hello -s"
compile lib_bc -s "$SRC/lib.lua" || fail "luac: compile lib -s"
compile err_bc "" "$SRC/err.lua" || fail "luac: compile err"
compile err_s -s "$SRC/err.lua" || fail "luac: compile err -s"
ktap_pass "luac: lunatikc compiles the test scripts"

mark_dmesg
run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }
dmesg_since | grep -q "luac: hello from bytecode" || fail "luac: compiled chunk did not run"
ktap_pass "luac: compiled chunk runs"

mark_dmesg
run_script "tests/luac/hello_s"
check_dmesg || { ktap_totals; exit 1; }
dmesg_since | grep -q "luac: hello from bytecode" || fail "luac: stripped chunk did not run"
ktap_pass "luac: stripped chunk runs"

mark_dmesg
run_script "tests/luac/user"
check_dmesg || { ktap_totals; exit 1; }
dmesg_since | grep -q "luac: require of a compiled library" || fail "luac: require did not load the chunk"
ktap_pass "luac: require() loads a compiled library"

output=$(lunatik run tests/luac/err_bc)
echo "$output" | grep -q "^$SRC/err_bc.lua:8: attempt to index a nil value (local 't')" \
	|| fail "luac: full chunk error: $output"
ktap_pass "luac: error names the chunk name and line"

output=$(lunatik run tests/luac/err_s)
echo "$output" | grep -q "^?:?: attempt to index a nil value" || fail "luac: stripped chunk error: $output"
ktap_pass "luac: stripped error has no source or line"

# a stock luac writes lua_Number as a double: patch the header probe (last 8 bytes of the
# 4 size+value blocks) with the IEEE-754 image of -370.5
cp "$SRC/hello_bc.lua" "$SRC/stock.lua"
printf '\x00\x00\x00\x00\x00\x28\x77\xc0' | dd of="$SRC/stock.lua" bs=1 seek=32 conv=notrunc status=none
output=$(lunatik run tests/luac/stock)
echo "$output" | grep -q "Lua number format mismatch" || fail "luac: stock chunk accepted: $output"
ktap_pass "luac: stock number format is rejected"

mark_dmesg
run_script "tests/luac/textmode"
check_dmesg || { ktap_totals; exit 1; }
dmesg_since | grep -q "luac: text-only load rejects bytecode" || fail "luac: textmode did not run"
ktap_pass "luac: load() with mode t rejects a chunk"

printf 'local x = = 1\n' > "$SRC/bad.lua"
output=$(lunatikc "$SRC/bad.lua" 2>&1) && fail "luac: syntax error accepted"
echo "$output" | grep -q "^lunatikc: $SRC/bad.lua:1: " || fail "luac: syntax error message: $output"
[ ! -e "$SRC/bad.luac" ] || fail "luac: syntax error left an output"
ktap_pass "luac: a syntax error names the file and line and leaves no output"

output=$(lunatikc "$SRC/hello_bc.lua" 2>&1) && fail "luac: binary input accepted"
echo "$output" | grep -q "binary chunk" || fail "luac: binary input message: $output"
[ ! -e "$SRC/hello_bc.luac" ] || fail "luac: binary input left an output"
ktap_pass "luac: a binary input is refused"

lunatikc -n "=x" "$SRC/hello.lua" "$SRC/lib.lua" 2>/dev/null && fail "luac: several inputs with -n accepted"
[ ! -e "$SRC/hello.luac" ] && [ ! -e "$SRC/lib.luac" ] || fail "luac: refused inputs left an output"
ktap_pass "luac: several inputs with -n are refused"

lunatikc "$SRC/hello.lua" || fail "luac: default output"
[ -f "$SRC/hello.luac" ] || fail "luac: hello.luac not written next to the input"
ktap_pass "luac: the default output is <input>.luac next to the input"

ktap_totals

