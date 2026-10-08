#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Names a message to the session that asks rather than directs: one with a question mark, or one
# that opens with an interrogative, in Portuguese or English. A question about state ("what is
# left?", "is it ready?") is answered, and what the answer recommends is proposed and not done.
# Prints "question" for such a message, nothing otherwise.
#
# Usage: bash tools/checks/question.sh <file>

[ -f "$1" ] || exit 0
grep -qE '\?' "$1" && { echo question; exit 0; }
grep -qiE '^[[:space:]]*(pq|por ?que|o que|qual|quais|quem|como|onde|quando|cad[eê]|why|what|which|how|where|who|when)([[:space:]]|$)' "$1" &&
	echo question
exit 0

