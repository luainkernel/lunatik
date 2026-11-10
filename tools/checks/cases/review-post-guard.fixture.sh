#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Writes, in the empty directory <dir>, the texts review-post-guard.cases posts: a comment and a review
# that open with the note, one with the note at its end, as an issue filed elsewhere carries it, one with
# the line the note replaced, a review whose inline comment lacks the note, and under sub/, read only
# after a cd into it, the comment that opens with the note; beside them a gh on stub/ that answers, only
# with the token in key, that the posting account opened #871.
#
# Usage: bash tools/checks/cases/review-post-guard.fixture.sh <dir>

cd "$1" || exit 1
note='> [!NOTE]
> This comment was written by an LLM, not a human.'
printf '%s\n\nThe callback returns the queue and the slice.\n' "$note" > note.md
printf 'The callback returns the queue and the slice.\n\n%s\n' "$note" > late.md
printf '(posted by an agent, not by @lneto)\n\nThe callback returns the queue and the slice.\n' > line.md
mkdir -p sub
cp note.md sub/post.md

review=$(printf '%s\n\n@author, requesting changes.' "${note/comment/review}")
comment=$(cat note.md)
jq -n --arg body "$review" --arg comment "$comment" \
	'{event: "COMMENT", body: $body, comments: [{path: "a.c", line: 1, side: "RIGHT", body: $comment}]}' > review.json
jq -n --arg body "$review" \
	'{event: "COMMENT", body: $body, comments: [{path: "a.c", line: 1, side: "RIGHT", body: "The callback returns."}]}' \
	> bare.json

printf cases > key
mkdir -p stub
cat > stub/gh <<'STUB'
#!/bin/sh
[ "$GH_TOKEN" = cases ] || exit 1
case "$*" in
	*/issues/871\ *|api\ user\ *) echo cases ;;
	*) exit 1 ;;
esac
STUB
chmod +x stub/gh

