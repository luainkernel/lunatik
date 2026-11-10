#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Sourced by the command guards: what a tool command runs, read from the raw hook input, which
# embeds the command verbatim.

# the command field, closed by the first bare quote, escapes undone: a line of its own is a command
command_text() {
	printf '%s' "$1" | awk '
	{ s = (NR > 1 ? s "\n" : "") $0 }
	END {
		if (!match(s, /"command"[ \t]*:[ \t]*"/))
			exit
		for (i = RSTART + RLENGTH; (c = substr(s, i, 1)) != "\"" && c != ""; i++) {
			if (c == "\\") {
				c = substr(s, ++i, 1)
				c = c == "n" ? "\n" : c == "t" ? "\t" : c
			}
			printf "%s", c
		}
	}'
}

# the simple commands the command field runs, one a line, split into words as the shell splits them
# and past the words that only lead into a command: an assignment, a keyword, sudo, env, timeout,
# setsid, ip netns exec, tools/lunatik-host, a shell or a lua given a script. A shell's -c string,
# an eval, a substitution and a heredoc a shell reads are commands too; other quoted text is one
# word, another heredoc data. With -v redirections=1, the files the redirections write instead; with
# -v assignments=1, each command after the names of the variables it runs under, NAME=, its own and
# those of the shell that reads it
COMMAND_PARSER='
	function word() {
		if (w == "" && !quoted)
			return
		if (redirect) {
			if (write && redirections)
				print w
			redirect = write = 0
		}
		else if (delim == "?")
			delim = w
		else
			W[++n] = w
		w = ""
		quoted = 0
	}
	# the index past the options from i on, where an option matching arg takes the next word
	function options(i, arg) {
		for (; i <= n && W[i] ~ /^-./; i++)
			if (W[i] == "--")
				return i + 1
			else if (arg && W[i] ~ arg)
				i++
		return i
	}
	function join(i,   line) {
		for (line = i <= n ? W[i] : ""; ++i <= n; )
			line = line " " W[i]
		return line
	}
	function nested(s, set,   d, t, h, o) {
		d = delim; t = tab; h = shell; o = outer
		outer = set
		parse(s)
		delim = d; tab = t; shell = h; outer = o
	}
	# prints the command W holds; returns whether it is a shell that reads its commands from stdin
	function command(   i, k, c, stdin, noexec, line, set) {
		word()
		set = outer
		for (i = 1; i <= n; i++) {
			k = W[i]
			sub(/.*\//, "", k)
			if (W[i] ~ /^[A-Za-z_][A-Za-z_0-9]*=/)
				set = set substr(W[i], 1, index(W[i], "=")) " "
			else if (k ~ /^(!|\{|if|then|elif|else|do|while|until|time|command|exec|nohup|lunatik-host|lua[0-9.]*)$/)
				continue
			else if (k == "sudo")
				i = options(i + 1, "^-[^-]*[CDghpRrTtUu]$") - 1
			else if (k == "env")
				i = options(i + 1, "^-[^-]*[CSu]$") - 1
			else if (k == "timeout")
				i = options(i + 1, "^-[^-]*[ks]$") # and the duration
			else if (k == "setsid")
				i = options(i + 1) - 1
			else if (k == "ip" && W[i + 1] == "netns" && W[i + 2] == "exec")
				i += 3 # and the namespace
			else if (k == "eval") {
				nested(join(i + 1), set)
				return 0
			}
			else if (k ~ /^(ba|da)?sh$/) {
				for (c = stdin = noexec = 0; ++i <= n && W[i] ~ /^[-+]./ && W[i] != "--"; ) {
					c = c || W[i] ~ /^-[^-]*c/
					stdin = stdin || W[i] ~ /^-[^-]*s/
					noexec = noexec || W[i] ~ /^-[^-]*n/
					if (W[i] ~ /^[-+][^-]*[oO]$/)
						i++
				}
				i += i <= n && W[i] == "--"
				if (noexec) { # a syntax check reads the script and runs nothing
					n = 0
					return 0
				}
				line = i <= n ? W[i] : ""
				if (c || stdin || i > n) {
					n = 0
					if (c && line != "")
						nested(line, set)
					piped = set
					return !c
				}
				i-- # the script is the command
			}
			else
				break
		}
		line = join(i)
		gsub(/\n/, " ", line) # a quoted newline is not a new command
		if (line != "" && !redirections)
			print (assignments ? set : "") line
		n = 0
		return 0
	}
	# a command substitution at i is a command of its own and part of the word; returns where it ends
	function substitution(s, i,   j, depth, dollar) {
		if (!(dollar = substr(s, i, 1) == "$"))
			j = i + index(substr(s, i + 1), "`")
		else
			for (j = i + 1; j <= length(s); j++)
				if (!(depth += (substr(s, j, 1) == "(") - (substr(s, j, 1) == ")")))
					break
		if (j == i || j > length(s))
			j = length(s)
		Q[++nq] = substr(s, i + 1 + dollar, j - i - 1 - dollar)
		O[nq] = outer # it runs under the variables of the shell that reads it
		w = w substr(s, i, j - i + 1)
		return j
	}
	# the body of the heredoc whose operator line ends at i, read as commands when a shell on that line
	# reads its stdin; returns where the delimiter line ends
	function heredoc(s, i,   j, line, body) {
		while (i < length(s)) {
			j = index(substr(s, i + 1), "\n")
			line = j ? substr(s, i + 1, j - 1) : substr(s, i + 1)
			i = j ? i + j : length(s)
			if (tab)
				sub(/^\t+/, "", line)
			if (line == delim)
				break
			body = body line "\n"
		}
		if (shell)
			nested(body, piped)
		delim = ""
		shell = 0
		return i
	}
	function parse(s,   i, c, d, j) {
		n = quoted = redirect = shell = 0
		w = delim = ""
		for (i = 1; i <= length(s); i++) {
			c = substr(s, i, 1)
			if (c == "\\") {
				if ((d = substr(s, ++i, 1)) != "\n") {
					w = w d
					quoted = 1
				}
			}
			else if (c == "\047") {
				j = index(substr(s, i + 1), "\047")
				j = j ? j : length(s) - i + 1
				w = w substr(s, i + 1, j - 1)
				i += j
				quoted = 1
			}
			else if (c == "\"") {
				for (i++; i <= length(s) && (d = substr(s, i, 1)) != "\""; i++)
					if (d == "`" || d == "$" && substr(s, i + 1, 1) == "(")
						i = substitution(s, i)
					else if (d == "\\" && index("\"\\$`", substr(s, i + 1, 1)))
						w = w substr(s, ++i, 1)
					else
						w = w d
				quoted = 1
			}
			else if (c == "`" || c == "$" && substr(s, i + 1, 1) == "(")
				i = substitution(s, i)
			else if (c == " " || c == "\t")
				word()
			else if (c == "#" && w == "" && !quoted)
				while (i < length(s) && substr(s, i + 1, 1) != "\n")
					i++
			else if (c == "<" || c == ">" || c == "&" && substr(s, i + 1, 1) == ">") {
				if (w ~ /^[0-9]+$/ && !quoted)
					w = "" # the descriptor the redirection names
				word()
				if (substr(s, i, 3) == "<<<") {
					i += 2
					redirect = 1 # a here-string is data
				}
				else if (substr(s, i, 2) == "<<") {
					tab = substr(s, i + 2, 1) == "-"
					i += 1 + tab
					delim = "?"
				}
				else {
					while (index("<>&|", substr(s, i + 1, 1)))
						i++
					redirect = 1
					write = c != "<"
				}
			}
			else if (index(";&|()\n", c)) {
				if (command() && delim != "")
					shell = 1
				if (c == "\n" && delim != "" && delim != "?")
					i = heredoc(s, i)
			}
			else
				w = w c
		}
		command()
	}
	{ text = (NR > 1 ? text "\n" : "") $0 }
	END {
		parse(text)
		for (q = 1; q <= nq; q++) {
			outer = O[q]
			parse(Q[q])
		}
	}'

commands() {
	command_text "$1" | awk "$COMMAND_PARSER"
}

# the files the command field's redirections write, one a line, with the quotes taken off
redirections() {
	command_text "$1" | awk -v redirections=1 "$COMMAND_PARSER"
}

# the commands the command field runs, each after the names of the variables it runs under, NAME=
assignments() {
	command_text "$1" | awk -v assignments=1 "$COMMAND_PARSER"
}

# git past its global options, -C with its word and -c with its key=value, a value commands prints
# with the quotes taken off and so with any space it held
GIT_COMMAND='^([^ ]*/)?git( -C [^ ]+| -c [^ =]+=([^ -][^ ]*( [^ -][^ ]*)*)?| -[^ ]+)*'

# the directory dir a walk over commands, one a line, has reached: each cd moves it, under it or to an
# absolute path
FOLLOW_CD='
	function under(base, path) {
		return path ~ /^\// ? path : base "/" path
	}
	$1 == "cd" && NF > 1 {
		dir = under(dir, $2)
	}'

# each git <verb> among <cmds>, run from the directory <cwd>: the directory it runs in, resolved against
# every cd before it and its own -C, a tab, and its words past <verb>
git_runs() {
	printf '%s\n' "$1" | awk -v dir="${2:-.}" -v verb="$3" -v run="$GIT_COMMAND $3( |\$)" "$FOLLOW_CD"'
	$0 ~ run {
		d = dir
		for (i = 2; $i != verb; i++)
			if ($i == "-C")
				d = under(d, $++i)
		rest = ""
		for (i++; i <= NF; i++)
			rest = rest (rest == "" ? "" : " ") $i
		print d "\t" rest
	}'
}

git_pushes() {
	git_runs "$1" "$2" push
}

# the CLI as the command, with a verb and what follows it matching the extended regex <rest>
runs_lunatik() {
	printf '%s\n' "$1" | grep -Eq "^([^ ]*/)?lunatik $2"
}

# the CLI as the command with no verb, the REPL, or with -e or -i: a chunk written to the device
runs_repl() {
	printf '%s\n' "$1" | grep -Eq '^([^ ]*/)?lunatik( -(e|i)( |$)| --(eval|interactive)( |=|$)|$)'
}

MAKE_INSTALL='^([^ ]*/)?make( .*)? install( |$)'

runs_install() {
	printf '%s\n' "$1" | grep -Eq "$MAKE_INSTALL"
}

# the directory each make install among <cmds> runs in, from the directory <cwd>: resolved against every
# cd before it and its own -C, as git_runs resolves git's
install_dirs() {
	printf '%s\n' "$1" | awk -v dir="$2" -v run="$MAKE_INSTALL" "$FOLLOW_CD"'
	$0 ~ run {
		d = dir
		for (i = 2; i <= NF; i++)
			if ($i == "-C" || $i == "--directory")
				d = under(d, $++i)
			else if ($i ~ /^(-C|--directory=)./)
				d = under(d, substr($i, $i ~ /^-C/ ? 3 : 13))
		print d
	}'
}

# a suite's run.sh or a script under tests/ as the command; a path to one handed to git or to a
# check is not a run, and the bare substring read every one of those as one
runs_test() {
	printf '%s\n' "$1" | grep -Eq '^([^ ]*/)?(run|tests/[^ ]*)\.sh( |$)'
}

runs_watchdog() {
	printf '%s\n' "$1" | grep -Eq '^([^ ]*/)?watchdog\.sh( |$)'
}

# whether the word <i> of a gh api command is its endpoint, its one positional argument: the word after
# api, or any word not an option when that word is one. commands prints a substitution's text into the
# word that carries it, so a field can hold the endpoint of a gh api nested in it
GH_ENDPOINT='
	function endpoint(i) {
		return $i !~ /^-/ && (i == 3 || $3 ~ /^-/)
	}'

# the gh commands among <cmds> that write where the extended regex <path> points: a gh command whose
# noun and verb match <cli>, as `pr create`, or gh api on a matching endpoint with a method other than
# GET, or with a field and no method, which gh sends as a POST. Each is printed with its noun and its
# verb as the second and the third word: a repository option, which gh takes anywhere in any spelling
# and obeys the last of, is dropped where it stands and the last one put at the end as -R <repo>. gh api
# takes none, so a -R among its words is text of a field, and stays where it is
gh_writes() {
	printf '%s\n' "$1" | path="$3" awk -v cli="^($2)\$" "$GH_ENDPOINT"'
	$1 !~ /^([^ ]*\/)?gh$/ {
		next
	}
	$2 != "api" {
		repo = line = ""
		for (i = 1; i <= NF; i++)
			if ($i ~ /^(-R|--repo)$/)
				repo = $(++i)
			else if ($i ~ /^(-R|--repo=)./)
				repo = substr($i, $i ~ /^-R=/ ? 4 : $i ~ /^-R/ ? 3 : 8)
			else
				line = line (i > 1 ? " " : "") $i
		if (repo != "")
			$0 = line " -R " repo
	}
	($2 " " $3) ~ cli {
		print
		next
	}
	$2 == "api" {
		method = ""
		fields = hit = 0
		for (i = 3; i <= NF; i++)
			if ($i == "-X" || $i == "--method")
				method = toupper($(++i))
			else if ($i ~ /^(-X|--method=)./)
				method = toupper(substr($i, $i ~ /^-X/ ? 3 : 10))
			else if ($i ~ /^(-f|-F|--field|--raw-field|--input)$/) {
				fields = 1
				i++
			}
			else if ($i ~ /^(-[fF]|--field=|--raw-field=|--input=)./)
				fields = 1
			else if ($i ~ /^(-H|--header|-q|--jq|-t|--template|-p|--preview|--hostname|--cache)$/)
				i++
			else if (endpoint(i) && $i ~ ENVIRON["path"]) # -v would read the backslashes in it as escapes
				hit = 1
		if (hit && (method != "" ? method != "GET" : fields))
			print
	}'
}

# the commands the hook input <input> runs, as commands prints them, with each file a gh command reads, a
# body, notes, the JSON gh api sends or a field's @<file>, spelled as the path gh reads it from: under the
# input's cwd, or the hook's directory when it names none, moved by every cd before it as git_runs moves it
gh_commands() {
	local cwd
	cwd=$(printf '%s' "$1" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
	commands "$1" | awk -v dir="${cwd:-$PWD}" "$FOLLOW_CD"'
	# the file <path> names, with the quotes gh_body takes off taken off; - is stdin
	function at(path) {
		gsub(/^["\047\\]+|["\047\\]+$/, "", path)
		return path == "" || path == "-" ? path : under(dir, path)
	}
	# the gh api field at <i>, read from a file when it is <name>=@<file>
	function field(i,   j) {
		if (j = index($i, "=@"))
			$i = substr($i, 1, j + 1) at(substr($i, j + 2))
	}
	$1 ~ /^([^ ]*\/)?gh$/ {
		for (i = 3; i <= NF; i++)
			if (i < NF && ($i ~ /^--(input|body-file|notes-file)$/ || $i == "-F" && $2 != "api")) {
				i++
				$i = at($i)
			}
			else if (match($i, /^--(input|body-file|notes-file)=/))
				$i = substr($i, 1, RLENGTH) at(substr($i, RLENGTH + 1))
			else if ($2 == "api" && $i ~ /^(-F|--field)$/)
				field(++i)
			else if ($2 == "api" && $i ~ /^(-F|--field=)./)
				field(i)
	}
	{
		print
	}'
}

# the GitHub token the command in the hook input <input> runs with: GH_TOKEN from the environment, or
# the file the command reads it from with GH_TOKEN=$(cat <file>)
gh_token() {
	[ -n "$GH_TOKEN" ] && { printf '%s' "$GH_TOKEN"; return; }
	cat "$(command_text "$1" | grep -oE 'GH_TOKEN=\$\(cat [^)"]+\)' | head -n 1 |
		sed -E 's/^GH_TOKEN=\$\(cat (.*)\)$/\1/')" 2>/dev/null
}

# the repository the gh write <post> targets, owner/name, from gh api's endpoint or from the -R gh_writes
# puts at the end of any other; nothing when it names none
gh_repo() {
	printf '%s\n' "$1" | awk "$GH_ENDPOINT"'
	$2 == "api" {
		for (i = 3; i <= NF; i++)
			if (endpoint(i) && $i ~ /^(https:\/\/api\.github\.com)?\/?repos\// && match($i, /repos\/[^\/]+\/[^\/]+/))
				repo = substr($i, RSTART + 6, RLENGTH - 6)
		next
	}
	{
		for (i = 1; i <= NF; i++)
			if ($i == "-R")
				repo = $(i + 1)
	}
	END {
		print repo
	}'
}

# whether the gh write <post> publishes to this repository or a fork of it, as one that names no other does
gh_ours() {
	case "$(gh_repo "$1")" in
		""|*/lunatik) return 0 ;;
	esac
	return 1
}

# the issue or pull request the gh write <post> targets, by its number; nothing when it names none
gh_number() {
	printf '%s\n' "$1" | awk "$GH_ENDPOINT"'
	$2 == "api" {
		for (i = 3; i <= NF; i++)
			if (endpoint(i) && match($i, /repos\/[^\/]+\/[^\/]+\/(issues|pulls)\/[0-9]+/)) {
				s = substr($i, RSTART, RLENGTH)
				sub(/.*\//, "", s)
				print s
			}
		exit
	}
	$4 ~ /^[0-9]+$/ {
		print $4
	}' | head -n 1
}

# the file listing, a line each as gh_heldkey names it, the issues and pull requests review-post-guard
# held a post on in the session the hook input <input> comes from
gh_held() {
	local session
	session=$(printf '%s' "$1" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
	printf '%s/held-%s' "${LUNATIK_GUARD_DIR:-/tmp/lunatik-guards}" "${session:-none}"
}

# the issue or pull request the gh write <post> targets as gh_held lists it: its number on this
# repository, a fork of it or the one gh fills {owner}/{repo} with, and <owner>/<name>#<number> on
# another, in lower case and without a host, since gh and GitHub take a repository so spelled as the
# same one; nothing when it names none
gh_heldkey() {
	local number repo
	number=$(gh_number "$1")
	[ -n "$number" ] || return 0
	repo=$(gh_repo "$1" | tr '[:upper:]' '[:lower:]' | awk -F/ 'NF > 1 { print $(NF - 1) "/" $NF }')
	case $repo in
		""|*/lunatik|'{owner}/{repo}') printf '%s\n' "$number" ;;
		*) printf '%s#%s\n' "$repo" "$number" ;;
	esac
}

# what carries the text of the gh write <post>: "file <path>", "input <path>" for the JSON gh api sends
# whole, "inline" for text on the command line, nothing for a write without text; the flags are the
# form's, since -F names a file to gh pr, gh issue and gh release and a field to gh api
gh_body() {
	printf '%s\n' "$1" | awk '
	function bare(s) {
		gsub(/^["\047\\]+|["\047\\]+$/, "", s)
		return s
	}
	# a gh api field, body=@<file> read from the file when typed, body=<text> otherwise
	function field(v, typed) {
		v = bare(v)
		if (v !~ /^body=/)
			return 0
		v = substr(v, 6)
		print (typed && v ~ /^@/ ? "file " bare(substr(v, 2)) : "inline")
		return 1
	}
	$2 == "api" {
		for (i = 3; i <= NF; i++)
			if ($i ~ /^(-F|--field|-f|--raw-field)$/) {
				if (field($(i + 1), $i ~ /^(-F|--field)$/))
					exit
				i++
			}
			else if ($i ~ /^(-[Ff]|--field=|--raw-field=)./) {
				if (field(substr($i, $i ~ /^-[Ff]/ ? 3 : $i ~ /^--field=/ ? 9 : 13), $i ~ /^(-F|--field=)/))
					exit
			}
			else if ($i == "--input") {
				print "input " bare($(i + 1))
				exit
			}
			else if ($i ~ /^--input=/) {
				print "input " bare(substr($i, 9))
				exit
			}
		exit
	}
	{
		for (i = 3; i <= NF; i++)
			if ($i == "-F" || $i == "--body-file") {
				print "file " bare($(i + 1))
				exit
			}
			else if ($i ~ /^--body-file=/) {
				print "file " bare(substr($i, 13))
				exit
			}
			else if ($i == "--notes-file") {
				print "file " bare($(i + 1))
				exit
			}
			else if ($i ~ /^--notes-file=/) {
				print "file " bare(substr($i, 14))
				exit
			}
			else if ($i ~ /^(-b|--body|-n|--notes)$/ || $i ~ /^(-b.|--body=|-n.|--notes=)/) {
				print "inline"
				exit
			}
	}'
}

# the gh api field <name> the write <post> passes, -f <name>=<value> in any spelling gh takes
gh_field() {
	printf '%s' "$1" | grep -oE -- "(-f|-F|--raw-field|--field)[ =]?$2=[\"']?[^[:space:]\"']+" | head -n 1 | sed "s/.*$2=[\"']\{0,1\}//"
}

# the value the gh pr write <post> passes to its option <long>, or to <short>
gh_option() {
	printf '%s\n' "$1" | awk -v long="$2" -v short="$3" '
	{
		for (i = 3; i <= NF; i++)
			if ($i == long || $i == short) {
				print $(i + 1)
				exit
			}
			else if (index($i, long "=") == 1) {
				print substr($i, length(long) + 2)
				exit
			}
	}'
}

# the base and the head, "<base> <head>", the gh write <post> names: head= and base= or the JSON gh api
# sends, or gh pr's --head and --base, master when it names no base
gh_named() {
	local base head body
	if [ "$(printf '%s' "$1" | awk '{ print $2 }')" = pr ]; then
		base=$(gh_option "$1" --base -B)
		head=$(gh_option "$1" --head -H)
	else
		body=$(gh_body "$1")
		if [ "${body%% *}" = input ]; then
			base=$(jq -r '.base // empty' "${body#* }" 2> /dev/null)
			head=$(jq -r '.head // empty' "${body#* }" 2> /dev/null)
		else
			base=$(gh_field "$1" base)
			head=$(gh_field "$1" head)
		fi
	fi
	printf '%s %s\n' "${base:-master}" "$head"
}

# the base and the head, "<base> <head>", of the pull request the gh write <post> opens or edits: a
# create's those it names; an edit's from GitHub's pulls/<N>, asked with the credential the hook input
# <input> carries, the base too, since a retarget moves none of its commits, and one onto master after
# its base merged by rebase would read that base's commits, under their old SHAs, as its own; none from
# a lookup that fails, whose error body gh prints where the answer would be
gh_refs() {
	local base head repo number answer
	number=$(gh_number "$2")
	if [ -n "$number" ]; then
		repo=$(gh_repo "$2")
		answer=$(GH_TOKEN=$(gh_token "$1") gh api "repos/${repo:-{owner\}/{repo\}}/pulls/$number" \
			--jq '.head.sha + " " + .base.ref' 2> /dev/null) || answer=
		read -r head base <<< "$answer"
	else
		read -r base head <<< "$(gh_named "$2")"
	fi
	printf '%s %s\n' "${base:-master}" "$head"
}

# the commit the change from <base> to <head> is read from, then the files it carries, on one line,
# read in the checkout <project>; it fails when the checkout cannot read one of them. A stacked pull
# request's change is what its head adds to the branch below it, and read against master it carries
# that branch's too, so the base is the tip GitHub has, in the repository the gh write <post> targets,
# asked with the credential the hook input <input> carries.
# A push through a URL moves no remote-tracking ref, so one fetched before the base was rebased reads a
# change of master as the pull request's own; the remote-tracking ref stands in when GitHub does not
# answer or names a commit this checkout lacks, and the local branch when neither is there
gh_change() {
	local repo ref
	repo=$(gh_repo "$2")
	ref=$(GH_TOKEN=$(gh_token "$1") gh api "repos/${repo:-{owner\}/{repo\}}/branches/$3" --jq .commit.sha 2> /dev/null)
	git -C "$5" cat-file -e "$ref^{commit}" 2> /dev/null || ref=origin/$3
	git -C "$5" rev-parse -q --verify "$ref^{commit}" > /dev/null || ref=$3
	ref=$(git -C "$5" merge-base "$ref" "$4" 2> /dev/null) || return 1
	echo "$ref" $(git -C "$5" diff --name-only "$ref" "$4")
}

