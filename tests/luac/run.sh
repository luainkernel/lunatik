#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the bytecode compiler: compiles the installed test scripts with lunatikc on the host,
# installs the chunks under /lib/modules/lua/tests/luac and runs them in the kernel.
#   - a compiled chunk runs, full and stripped (-s), with integer semantics
#   - a compiled library is found by require()
#   - errors name the source path and line; stripped errors are "?:?:"
#   - -l lists a compiled chunk
#   - a chunk with a stock (float) number format is rejected by the header check
#   - load() with mode "t" rejects a chunk inside the kernel
#
# Usage: sudo bash tests/luac/run.sh

SCRIPT="tests/luac/hello_bc"
SCRIPTS_PATH="/lib/modules/lua"
SRC="$SCRIPTS_PATH/tests/luac"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	rm -f "$SRC"/*_bc.lua "$SRC"/*_s.lua "$SRC"/stock.lua
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 9

if ! command -v lunatikc >/dev/null; then
	for i in $(seq 9); do ktap_skip "luac: lunatikc not installed"; done
	ktap_totals
	exit 0
fi

compile() {
	local name="$1" strip="$2"; shift 2
	lunatikc $strip -o "$SRC/$name.lua" "$@"
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
echo "$output" | grep -q "^$SRC/err.lua:8: attempt to index a nil value (local 't')" \
	|| fail "luac: full chunk error: $output"
ktap_pass "luac: error names the source path and line"

output=$(lunatik run tests/luac/err_s)
echo "$output" | grep -q "^?:?: attempt to index a nil value" || fail "luac: stripped chunk error: $output"
ktap_pass "luac: stripped error has no source or line"

lunatikc -l "$SRC/hello_bc.lua" | grep -q "^main <" || fail "luac: -l did not list the chunk"
ktap_pass "luac: -l lists a compiled chunk"

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

ktap_totals

