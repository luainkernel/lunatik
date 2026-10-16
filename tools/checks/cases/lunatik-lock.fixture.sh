#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Starts, from the empty directory <dir>, the process lunatik-lock.cases is read against: a test script
# run by a shell, which the guard reads in the process table as an operation on the device. It ends once
# cases.sh removes <dir>, and after 30 seconds if nothing does, since every session on the machine reads
# the device as busy while it runs.
#
# Usage: bash tools/checks/cases/lunatik-lock.fixture.sh <dir>

mkdir -p "$1/tests/hold" || exit 1
printf 'for _ in $(seq 300); do [ -d "%s" ] || exit 0; sleep 0.1; done\n' "$1" > "$1/tests/hold/wait.sh"
bash "$1/tests/hold/wait.sh" < /dev/null > /dev/null 2>&1 &
# the guard reads the script's path, which the process carries once bash has started it
for _ in $(seq 50); do
	ps -o args= -p $! | grep -q 'tests/hold/wait\.sh$' && exit 0
	sleep 0.02
done
exit 1

