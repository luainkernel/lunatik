#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A decision handed to the maintainer is one he takes in one read: what is to be decided, the
# options, and the recommendation with its reason. "Its rewording is the maintainer's" named who
# decides and not what, on #1205, and the maintainer had to ask what his decision was. A
# recommendation's reason is what the option buys: keeping an API is a cost the other options pay,
# and #1965 recommended a positional read of a struct value because the array was "the existing
# contract", where a read by name holds when a field moves and one test used the array.
# Takes text files, a review body, a comment, a pull request or issue body or a reply; when one
# hands a decision over without the three, brings one without the ID its answer names or two without
# their table, or recommends an option for keeping an API, prints the lines that do and exits 1.
#
# Usage: bash tools/checks/decision.sh <file>...

handoff='decis(a|ã)o (e |é )?(sua|dele|do maintainer)|fica (para|com) (voc(e|ê)|o maintainer)|a decis(a|ã)o fica (para|com) ele|voc(e|ê) decide|a escolha (e|é) (sua|dele)|cabe a (voc(e|ê)|ele)|levo (isso |isto )?(a|para) (voc(e|ê)|ele)|aguardo (a )?(sua )?decis|maintainer.s (call|decision)|is the maintainer.s|left to the maintainer|up to the maintainer|for the maintainer to (decide|choose|pick)|(your|his) (call|decision)[.,;:]|bring (it|this) (back )?to the maintainer'
row='^\|[[:space:]]*(\*\*)?D[0-9]+'
question="o que decidir|a decidir:|decis(a|ã)o( D[0-9]+)?:|to decide:|decision( D[0-9]+)?:|$row"
option='^[[:space:]>*-]*(\*\*)?(\(?[a-e]\)|op(c|ç)(a|ã)o [a-e1-9]|option [a-e1-9])'
recommend='recomend|recommend'
recommendation="^[[:space:]>*-]*(\*\*)?($recommend)"
kept='existing (api|contract)|(api|contract) (that )?already exists|keeps? the (existing |current |documented )?(api|contract)|without (changing|breaking) the (api|contract)|does(n.t| not) (change|break) the (api|contract)|contrato (que )?j(á|a) existe|contrato existente|api (que )?j(á|a) existe|api existente|mant(é|e)m (a api|o contrato)|n(ã|a)o (muda|quebra) (a api|o contrato)|sem (mudar|quebrar) (a api|o contrato)'

status=0
for file in "$@"; do
	[ -f "$file" ] || continue
	said=$(sed -E 's/"[^"]*"//g; s/`[^`]*`//g' "$file") # a phrase quoted is one talked about, not one said
	# a recommendation runs from its opening line to the blank line that ends its paragraph
	reasons=$(printf '%s\n' "$said" | re="$recommendation" awk 'tolower($0) ~ ENVIRON["re"] { on = 1 } /^[[:space:]]*$/ { on = 0 } on { print NR ":" $0 }' | grep -iE "$kept")
	if [ -n "$reasons" ]; then
		printf '%s\n' "$reasons" | sed "s|^|$file:|"
		echo "$file: the recommendation rests on keeping an API, which is a cost the other options pay; give its reason in what the recommended option buys, and the break as the cost of the option that makes it, with the API's users counted"
		status=1
	fi
	options=$(grep -ciE "$option" "$file")
	# a decision carries the ID its answer names, and two or more open with a table of them
	decisions=$(printf '%s\n' "$said" | grep -ciE "$recommendation")
	if [ "$decisions" -ge 1 ] && [ "$options" -ge 2 ]; then
		if ! grep -qE '\bD[0-9]+\b' "$file"; then
			echo "$file: brings a decision without its ID; number it D1, D2, kept until it is answered, so the answer names it"
			status=1
		elif [ "$decisions" -ge 2 ] && ! grep -qE "$row" "$file"; then
			echo "$file: brings $decisions decisions without a table; open with one, ID | Decision | Options | Recommendation, and give below each ID what its options change"
			status=1
		fi
	fi
	# a decision reported as taken, or said to be none, hands nothing over
	said=$(printf '%s\n' "$said" | sed -E "s/\b(foi|por|was|n(ã|a)o (pede|precisa de|exige)|needs no|is not)( a| the)? ($handoff)//gI")
	printf '%s\n' "$said" | grep -qiE "$handoff" || continue
	missing=""
	grep -qiE "$question" "$file" || missing="$missing, what is to be decided"
	[ "$options" -ge 2 ] || missing="$missing, two options or more"
	grep -qiE "$recommend" "$file" || missing="$missing, a recommendation"
	[ -z "$missing" ] && continue
	printf '%s\n' "$said" | grep -niE "$handoff" | sed "s|^|$file:|"
	echo "$file: hands a decision over without${missing#,}; write \"Decision: <the question>\", options A) and B) with what each changes, and \"Recommendation: <option>, because <reason>\""
	status=1
done
exit $status

