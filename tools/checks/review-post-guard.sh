#!/usr/bin/env bash
# PreToolUse (Bash) hook: a GitHub review, a review body, or a PR comment is
# posted only after its exact text was shown to the maintainer and approved,
# and a fixup it references is a full commit URL, since a backtick'd SHA
# renders as code and does not link. This blocks (exit 2) a gh write to
# reviews/comments that lacks the REVIEW_POST_OK marker, set by hand once the
# text has an OK, or that carries a backtick'd SHA; silent (exit 0) on
# everything else. The marker forces the show-then-post step; it cannot check
# that the text was shown, only that it was set on purpose.
# Matches the raw hook input, which embeds the command verbatim.

input=$(cat)

case "$input" in
	*"gh api"*reviews*|*"gh api"*comments*|*"gh pr review"*|*"gh pr comment"*) ;;
	*) exit 0 ;;
esac

# a read carries no body, field, or method flag; only a write is guarded
case "$input" in
	*"-X POST"*|*"-X PATCH"*|*"-X PUT"*|*"--method"*|*"-f "*|*"-F "*|*"--field"*|*"--raw-field"*|*"--input"*|*"gh pr review"*|*"gh pr comment"*) ;;
	*) exit 0 ;;
esac

if printf '%s' "$input" | grep -Eq '`[0-9a-f]{7,40}'; then
	echo "review-post-guard: a fixup reference is a backtick'd SHA, which GitHub renders as code, not a link. Use a full commit URL: https://github.com/<owner>/<repo>/commit/<sha>" >&2
	exit 2
fi

case "$input" in
	*REVIEW_POST_OK=1*) exit 0 ;;
esac

echo "review-post-guard: show the exact text, get the maintainer's OK, then re-run with REVIEW_POST_OK=1 as a command prefix." >&2
exit 2

