#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Names a message to the session that asks rather than directs: one with a question mark, or one
# that opens with an interrogative, in Portuguese or English. A question about state ("what is
# left?", "is it ready?") is answered, and what the answer recommends is proposed and not done.
# A tag that ends the message as a clause of its own, as in "...; entendido?", asks for an
# acknowledgement of what came before, and its question mark does not count; "ok?" alone asks.
# Prints "question" for such a message, nothing otherwise.
#
# Usage: bash tools/checks/question.sh <file>

[ -f "$1" ] || exit 0
tag='entendido|ok|certo|beleza|blz|understood|got it|right'
sed -zE "s/([^[:space:]])[[:space:]]*([,;:.!]|\n)[[:space:]]*($tag)[[:space:]]*\?+[[:space:]]*\$/\1/I" "$1" |
	grep -qE '\?' && { echo question; exit 0; }
grep -qiE '^[[:space:]]*(pq|por ?que|o que|qual|quais|quem|como|onde|quando|cad[eê]|why|what|which|how|where|who|when)([[:space:]]|$)' "$1" &&
	echo question
exit 0

