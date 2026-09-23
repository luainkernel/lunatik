# Sourced by pr-body.sh and tools/issues.sh: how a pull request body closes an issue, with the
# keyword GitHub closes it on when the pull request merges, and how it names one it leaves open.
# Each takes the issue number, any when none is given, and prints an extended regex matched
# without regard to case, as GitHub matches the keyword.

closes() {
	printf '%s' "(^|[^[:alnum:]])(close[sd]?|fix(e[sd])?|resolve[sd]?):? +#${1:-[0-9]+}([^0-9]|\$)"
}

leaves() {
	printf '%s' "#${1:-[0-9]+},? which it does not close"
}

# the words that tie a body to an issue without acting on it, matched as written
ties() {
	printf '%s' '(^|[.:;] +)(Part|Top|Bottom) of[^.#]*#[0-9]+|Answers ([^.#]* )?#[0-9]+|[Rr]eported as #[0-9]+'
}

