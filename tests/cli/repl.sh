#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# The REPL and -e: a chunk runs in the kernel and prints what it returns, and a
# session on a pipe prints only what its lines return.
#
# - -e and --eval= run a chunk and print its values tab-separated, exit 0;
# - -e of a chunk that raises, or that does not load, exits 1 with the message on
#   stderr and nothing on stdout;
# - a piped session, n = 40 + 2, then n, then n + 1, prints 42 and 43 and
#   nothing else: no banner and no prompt;
# - a line that raises in a piped session prints its message on stderr, and the
#   session goes on;
# - -i after -e enters the REPL with what the chunk left.
#
# Usage: sudo bash tests/cli/repl.sh

TAB=$'\t'
NL=$'\n'

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() { :; }

ktap_header
ktap_plan 6

mark_dmesg

cli -e "return 40 + 2"
[ "$status" -eq 0 ] && [ "$out" = 42 ] && [ -z "$err" ] || fail "-e exited $status with '$out' and '$err'"
cli --eval="return 1, 'a'"
[ "$status" -eq 0 ] && [ "$out" = "1${TAB}a" ] || fail "--eval= exited $status with '$out'"
ktap_pass "-e and --eval= print the chunk's values, exit 0"

cli -e 'error("boom", 0)'
[ "$status" -eq 1 ] && [ -z "$out" ] && [ "$err" = "lunatik: boom" ] ||
	fail "-e of a chunk that raises exited $status with '$out' on stdout and '$err' on stderr"
cli -e "return ("
[ "$status" -eq 1 ] && [ -z "$out" ] && [[ "$err" == "lunatik: "*"near <eof>" ]] ||
	fail "-e of a chunk that does not load exited $status with '$out' on stdout and '$err' on stderr"
ktap_pass "-e of a chunk that raises or does not load exits 1 with the message on stderr"

cli <<< "n = 40 + 2${NL}n${NL}n + 1"
[ "$out" = "42${NL}43" ] && [ -z "$err" ] || fail "a piped session printed '$out' and '$err'"
ktap_pass "a piped session prints what its lines return and nothing else"

cli <<< "error(\"boom\", 0)${NL}return 7"
[ "$out" = 7 ] && [ "$err" = boom ] || fail "a piped session with a raising line printed '$out' and '$err'"
ktap_pass "a line that raises in a piped session prints its message on stderr, and the session goes on"

cli -e "n = 7" -i <<< n
[ "$out" = 7 ] || fail "-i after -e printed '$out' and '$err'"
ktap_pass "-i after -e enters the REPL with what the chunk left"

check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"

ktap_totals

