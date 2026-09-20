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
#
# The text of a post is read from the files the command names (body=@<file>,
# --body-file, --input) and run through machine-leak.sh, since a review comment
# is how the machine escaped into GitHub before any file did, and through the
# check that every text, the review body and each inline comment, opens by
# saying an agent wrote it, since the account it posts under is the
# maintainer's. The raw input is not scanned: it carries the working directory
# on every command, so a scan of it would fire on every post. Text the guard
# cannot read, passed inline or on stdin, is refused rather than skipped.

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

flag="(body=@|--body-file[ =]|--input[ =])"
# the quotes gh is written with are not part of the path: skipped before it, excluded from it
files=$(printf '%s' "$input" | grep -oE "$flag[\"'\\\\]*[^[:space:]\"'\\\\]+" | sed -E "s/^$flag[\"'\\\\]*//")

if [ -z "$files" ]; then
	case "$input" in
		*body=*|*"--body "*|*"--body="*)
			echo "review-post-guard: the text of a post is read from a file: pass it as -F body=@<file>." >&2
			exit 2 ;;
	esac
fi

for f in $files; do
	[ -f "$f" ] && continue
	echo "review-post-guard: the text of a post is read from a file, and $f is not one. A path written as a shell variable arrives here unexpanded: spell it out." >&2
	exit 2
done

leaked=$(for f in $files; do bash "$(dirname "$0")/machine-leak.sh" "$f"; done)
if [ -n "$leaked" ]; then
	echo "review-post-guard: the text carries what belongs to the machine it was written on:" >&2
	echo "$leaked" >&2
	echo "review-post-guard: rewrite the line and re-run." >&2
	exit 2
fi

untraced=$(for f in $files; do bash "$(dirname "$0")/untraced.sh" "$f"; done)
if [ -n "$untraced" ]; then
	echo "review-post-guard: $untraced" >&2
	exit 2
fi

# the account is the maintainer's, so every text opens by saying an agent wrote it
agentline='\(posted by an agent, not by @'
unsigned=$(for f in $files; do
	case "$(head -c 1 "$f")" in
		"{") grep -oE '"body"[[:space:]]*:[[:space:]]*"(\\.|[^"\\]){0,40}' "$f" | grep -vE "^\"body\"[[:space:]]*:[[:space:]]*\"$agentline" ;;
		*) head -n 1 "$f" | grep -qE "^$agentline" || echo "$f: $(head -n 1 "$f")" ;;
	esac
done)
if [ -n "$unsigned" ]; then
	echo "review-post-guard: a text posted under the maintainer's account opens with \"(posted by an agent, not by @<handle>)\", the review body and each inline comment alike; these do not:" >&2
	echo "$unsigned" >&2
	exit 2
fi

if printf '%s' "$input" | grep -Eq '`[0-9a-f]{7,40}'; then
	echo "review-post-guard: a fixup reference is a backtick'd SHA, which GitHub renders as code, not a link. Use a full commit URL: https://github.com/<owner>/<repo>/commit/<sha>" >&2
	exit 2
fi

case "$input" in
	*REVIEW_POST_OK=1*) exit 0 ;;
esac

echo "review-post-guard: show the exact text, get the maintainer's OK, then re-run with REVIEW_POST_OK=1 as a command prefix." >&2
exit 2

