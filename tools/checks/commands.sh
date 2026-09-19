# Sourced by the command guards, lunatik-lock.sh and crash-guard.sh: what a tool command runs,
# read from the raw hook input, which embeds the command verbatim.

# a suite's run.sh as the command, bare or under sudo, bash or sh; a mention of the file, a path
# handed to git or to a check, is not a run, and the bare substring read every one of those as one
runs_suite() {
	printf '%s' "$1" | grep -Eq '(^|[;&|("])[[:space:]]*((sudo|bash|sh)[[:space:]]+)*[^[:space:]]*run\.sh([[:space:]]|$|[;&|)"\\])'
}

