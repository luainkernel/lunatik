#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Names a message to the session that asks for a table, "tabela" or "table", in Portuguese or
# English. Claude Code draws a table only while its cells are short and prints its rows as
# "Header: value" lines past that, so the reply to such a message is told how much a cell may hold.
# Prints "table" for such a message, nothing otherwise.
#
# Usage: bash tools/checks/table.sh <file>

[ -f "$1" ] || exit 0
grep -qiwE 'tabelas?|tables?' "$1" && echo table
exit 0

