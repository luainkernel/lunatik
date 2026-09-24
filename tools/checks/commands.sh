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
# word, another heredoc data
commands() {
	command_text "$1" | awk '
	function word() {
		if (w == "" && !quoted)
			return
		if (redirect)
			redirect = 0
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
	function nested(s,   d, t, h) {
		d = delim; t = tab; h = shell
		parse(s)
		delim = d; tab = t; shell = h
	}
	# prints the command W holds; returns whether it is a shell that reads its commands from stdin
	function command(   i, k, c, stdin, line) {
		word()
		for (i = 1; i <= n; i++) {
			k = W[i]
			sub(/.*\//, "", k)
			if (W[i] ~ /^[A-Za-z_][A-Za-z_0-9]*=/ || k ~ /^(!|\{|if|then|elif|else|do|while|until|time|command|exec|nohup|lunatik-host|lua[0-9.]*)$/)
				continue
			if (k == "sudo")
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
				nested(join(i + 1))
				return 0
			}
			else if (k ~ /^(ba|da)?sh$/) {
				for (c = stdin = 0; ++i <= n && W[i] ~ /^[-+]./ && W[i] != "--"; ) {
					c = c || W[i] ~ /^-[^-]*c/
					stdin = stdin || W[i] ~ /^-[^-]*s/
					if (W[i] ~ /^[-+][^-]*[oO]$/)
						i++
				}
				i += i <= n && W[i] == "--"
				line = i <= n ? W[i] : ""
				if (c || stdin || i > n) {
					n = 0
					if (c && line != "")
						nested(line)
					return !c
				}
				i-- # the script is the command
			}
			else
				break
		}
		line = join(i)
		gsub(/\n/, " ", line) # a quoted newline is not a new command
		if (line != "")
			print line
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
			nested(body)
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
		for (q = 1; q <= nq; q++)
			parse(Q[q])
	}'
}

# the CLI as the command, with a verb and what follows it matching the extended regex <rest>
runs_lunatik() {
	printf '%s\n' "$1" | grep -Eq "^([^ ]*/)?lunatik $2"
}

runs_install() {
	printf '%s\n' "$1" | grep -Eq '^([^ ]*/)?make( .*)? install( |$)'
}

# a suite's run.sh or a script under tests/ as the command; a path to one handed to git or to a
# check is not a run, and the bare substring read every one of those as one
runs_test() {
	printf '%s\n' "$1" | grep -Eq '^([^ ]*/)?(run|tests/[^ ]*)\.sh( |$)'
}

runs_watchdog() {
	printf '%s\n' "$1" | grep -Eq '^([^ ]*/)?watchdog\.sh( |$)'
}

# the gh commands among <cmds> that write where the extended regex <path> points: a gh command whose
# noun and verb match <cli>, as `pr create`, past a -R before the verb, or gh api on a matching endpoint
# with a method other than GET, or with a field and no method, which gh sends as a POST
gh_writes() {
	printf '%s\n' "$1" | path="$3" awk -v cli="^($2)\$" '
	$1 !~ /^([^ ]*\/)?gh$/ {
		next
	}
	{
		verb = 3
		while ($verb ~ /^(-R|--repo)$/ || $verb ~ /^--repo=/)
			verb += $verb ~ /^--repo=/ ? 1 : 2
	}
	($2 " " $verb) ~ cli {
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
			else if ($i !~ /^-/ && $i ~ ENVIRON["path"]) # -v would read the backslashes in it as escapes
				hit = 1
		if (hit && (method != "" ? method != "GET" : fields))
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

# what carries the text of the gh write <post>: "file <path>", "input <path>" for the JSON gh api sends
# whole, "inline" for text on the command line, nothing for a write without text; the flags are the
# form's, since -F names a file to gh pr and gh issue and a field to gh api
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
			else if ($i ~ /^(-b|--body)$/ || $i ~ /^(-b.|--body=)/) {
				print "inline"
				exit
			}
	}'
}

