#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Writes, in the empty directory <dir>, the messages message-guard.cases commits: hash.msg, whose body
# holds a line that opens with an issue's number, and plain.msg, whose body holds none.
#
# Usage: bash tools/checks/cases/message-guard.fixture.sh <dir>

cd "$1" || exit 1
printf 'amend! set: a subject\n\nset: a subject\n\n#1905 settles the format.\n' > hash.msg
printf 'amend! set: a subject\n\nset: a subject\n\nIssue #1905 settles the format.\n' > plain.msg

