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
#   - a syntax error names the file and line; -p parses without writing a chunk; 250 inputs compile
#     in one call, since the host build does not take the kernel's LUAI_MAXSTACK
#   - a chunk with a stock (float) number format is rejected by the header check, in the kernel and
#     as an input to lunatikc
#   - load() with mode "t" rejects a chunk inside the kernel
#
# Usage: sudo bash tests/luac/run.sh

SCRIPT="tests/luac/hello_bc"
SCRIPTS_PATH="/lib/modules/lua"
SRC="$SCRIPTS_PATH/tests/luac"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	for s in hello_bc hello_s user textmode; do lunatik stop "tests/luac/$s" 2>/dev/null; done
	rm -f "$SRC"/*_bc.lua "$SRC"/*_s.lua "$SRC"/stock.lua
	[ -z "$TMP" ] || rm -rf "$TMP"
}
trap cleanup EXIT
cleanup
TMP=$(mktemp -d)

skip() { ktap_header; ktap_plan 1; ktap_skip "$1"; ktap_totals; exit 0; }

command -v lunatikc >/dev/null || skip "luac: lunatikc not installed"

ktap_header
ktap_plan 13

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

printf 'local = 1\n' > "$TMP/bad.lua"
output=$(lunatikc -p "$TMP/bad.lua" 2>&1) && fail "luac: syntax error accepted"
echo "$output" | grep -q "bad.lua:1:" || fail "luac: syntax error without file and line: $output"
ktap_pass "luac: a syntax error names the file and line"

(cd "$TMP" && lunatikc -p "$SRC/hello.lua" && [ ! -e luac.out ]) || fail "luac: -p failed or wrote a chunk"
ktap_pass "luac: -p parses without writing a chunk"

for i in $(seq 250); do printf 'return %d\n' "$i" > "$TMP/f$i.lua"; done
lunatikc -p "$TMP"/f*.lua || fail "luac: 250 inputs refused"
ktap_pass "luac: 250 inputs compile in one call"

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

output=$(lunatikc -l "$SRC/stock.lua" 2>&1) && fail "luac: stock chunk accepted as input"
echo "$output" | grep -q "Lua number format mismatch" || fail "luac: stock chunk as input: $output"
ktap_pass "luac: stock number format is rejected as input"

mark_dmesg
run_script "tests/luac/textmode"
check_dmesg || { ktap_totals; exit 1; }
dmesg_since | grep -q "luac: text-only load rejects bytecode" || fail "luac: textmode did not run"
ktap_pass "luac: load() with mode t rejects a chunk"

ktap_totals

