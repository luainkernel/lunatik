#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Checks a lunatik framework file (lib/lua*.c|h or the core lunatik.h /
# lunatik_*.h|c) for comment/LDoc style deviations from the framework.
# Heuristic: it nudges a review, it does not rewrite.
# Usage: module-conventions.sh <file>...
# Prints each finding as <file>:<line>: <what>; exits 1 when there are
# any. Files outside its scope are skipped silently, so callers can pass
# any path.

rc=0

check() {
	local file="$1" module=0

	case "$file" in
		*.mod.c|*/lunatik_sym.h|lunatik_sym.h) return 0 ;;  # generated
		*/lib/lua*.c|*/lib/lua*.h|lib/lua*.c|lib/lua*.h|*/lunatik.h|lunatik.h|*/lunatik_*.h|*/lunatik_*.c|lunatik_*.h|lunatik_*.c) ;;
		*) return 0 ;;
	esac
	[ -f "$file" ] || return 0

	# module-only checks: the core legitimately defines and uses the raw
	# primitives that the modules must reach through the framework wrappers.
	case "$file" in
		*lib/lua*.c|*lib/lua*.h) module=1 ;;
	esac

	finding() { local n; while IFS=: read -r n _; do echo "$file:$n: $1"; done; }

	# doc-block lines (leading '*') may quote code that legitimately uses //,
	# e.g. a BPF C snippet in an @usage example.
	grep -nE '(^|[^:"/])//' "$file" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*\*' | \
		finding "uses // line comments; the framework uses /* */ block comments only"
	grep -n '@section' "$file" 2>/dev/null | \
		finding "uses @section; no module uses it (it is only for merged files like luacrypto)"
	grep -nE '={4,}|-{4,}|#{3,}' "$file" 2>/dev/null | \
		finding "has a decorative banner (==== / ---- / ####); the framework uses none"
	grep -nE '\}[[:space:]]+else' "$file" 2>/dev/null | \
		finding "has } else on the same line; else goes on its own line"
	[ "$(tail -c2 "$file" | tr '\n' 'N')" = "NN" ] || awk 'END { print NR }' "$file" | \
		finding "does not end with a trailing blank line"
	grep -nE '\braw_cpu_ptr\(' "$file" 2>/dev/null | \
		finding "uses raw_cpu_ptr; a per-CPU access names its guarantee: this_cpu_ptr where preemption is off, per_cpu_ptr with an explicit id"
	grep -nE '__percpu[[:space:]]+\*[[:space:]]*\)' "$file" 2>/dev/null | grep -v '__force' | \
		finding "casts into __percpu without __force; a cast into an annotated address space carries __force, as the opt constants do"
	grep -nE 'lunatik_toobject\(L, *(-?[0-9]+|ix)\)->private' "$file" 2>/dev/null | grep -vE 'lunatik_getregistry|_key\)' | \
		finding "reads ->private through lunatik_toobject on an argument; lunatik_toobject returns NULL for a non-userdata, so a checker (lunatik_checkobject) goes first"
	grep -nE '(object|[a-z]+)->class *== *&lua[a-z_]+_class' "$file" 2>/dev/null | \
		finding "tests the class by hand; LUNATIK_PRIVATECHECKER and lunatik_argcheckclass take the class, LUNATIK_PRIVATECHECKERS a list of them"
	# a method that reads private as its own type right after lunatik_checkobject, which
	# accepts any Lunatik object, skips the class check; a checker tests the class in between.
	awk '
		/lunatik_checkobject\(L, *(-?[0-9]+|ix)\)/ { hold=NR }
		hold && /argcheckclass|argexpected/ { hold=0 }
		hold && NR<=hold+3 && /->private/ { print NR; hold=0 }
	' "$file" 2>/dev/null | \
		finding "reads ->private right after lunatik_checkobject, which accepts any Lunatik object; check the class first (lunatik_argcheckclass, or luaL_argexpected over the classes the method accepts)"

	# a function past thirty lines of body hides a step that wants a name.
	awk '
		/^[A-Za-z_][^;]*\(/ && !/;$/ { name=$0; signature=NR; next }
		/^\{$/ && name != "" { start=NR; next }
		/^\}$/ && start { if (NR-start-1 > 30) { sub(/\(.*/, "", name); sub(/.* /, "", name); print signature, name, NR-start-1 } start=0; name="" }
	' "$file" 2>/dev/null | while read -r signature name body; do
		finding "$name has $body lines of body; a step of it wants a name as a helper (.agents/rules/c.md)" <<< "$signature"
	done
	# (a) a comment right after a preprocessor branch usually restates the condition.
	awk '
		prev ~ /^[[:space:]]*#[[:space:]]*(if|ifdef|ifndef|else|elif|endif)/ \
			&& $0 ~ /^[[:space:]]*(\/\*|\*[[:space:]\/]|\/\/)/ { print NR }
		{ prev=$0 }
	' "$file" 2>/dev/null | \
		finding "has a comment right after a preprocessor branch (#if/#else/#endif); the condition already documents the branch — drop it unless it adds non-obvious rationale"

	# (b) a comment whose words reappear as an identifier on the next code line is
	# likely restating the code (e.g. /* sorts the array */ above luaXXX_sort()).
	awk '
		function sig(s,   n, a, i, o) { n=split(s, a, /[^A-Za-z0-9_]+/)
			for (i=1;i<=n;i++) if (length(a[i])>=6) o=o" "a[i]; return o }
		cw != "" && $0 !~ /^[[:space:]]*(\/\*|\*[[:space:]\/]|\/\/)/ && $0 !~ /^[[:space:]]*$/ {
			gsub(/"([^"\\]|\\.)*"/, "\"\"")
			n=split(cw, w, " ")
			for (i=1;i<=n;i++) if (w[i]!="" && $0 ~ ("[^A-Za-z0-9_]" w[i] "[^A-Za-z0-9_]")) { print pn; break }
			cw="" }
		{ if ($0 ~ /^[[:space:]]*(\/\*|\*[[:space:]\/]|\/\/)/) { cw=sig($0); pn=NR } else if ($0 !~ /^[[:space:]]*$/) cw="" }
	' "$file" 2>/dev/null | \
		finding "has a comment that repeats an identifier used on the next line; it likely restates the code — remove it unless it explains non-obvious rationale"

	if [ "$module" = 1 ]; then
		grep -nE '\b(kmalloc|kzalloc|kcalloc|kvmalloc|kvzalloc|kvcalloc|krealloc|kvrealloc|kfree|kvfree|vmalloc|vzalloc|vfree)\b' "$file" 2>/dev/null | \
			finding "calls a raw kernel allocator; lunatik wraps these (lunatik_malloc / lunatik_checkalloc / lunatik_checkzalloc / lunatik_realloc / lunatik_free). Confirm there is no framework API in lunatik.h for what you are introducing before using the kernel one directly"
		grep -nE '#define[[:space:]]+lua[a-z]+_pushoptinteger' "$file" 2>/dev/null | \
			finding "defines its own *_pushoptinteger macro; use the shared lunatik_pushoptinteger from lunatik.h"
		if ! grep -q '@module' "$file"; then
			grep -nE '^(LUNATIK|LUAKFUNC)_NEWLIB\(' "$file" | finding "is a module but has no @module LDoc header"
		fi
		# @classmod documents the whole file as the class (as crypto does), so it
		# groups the methods just as @type does inside a @module.
		if ! grep -qE '@type|@classmod' "$file"; then
			grep -nE '^[[:space:]]*\.methods[[:space:]]*=' "$file" | \
				finding "defines a class with methods but has no @type (or @classmod) block to group them"
		fi
		# a raise right below the acquisition is the well-formed idiom (acquire,
		# validate); what deserves a look is a raise further down, with the
		# resource already stashed somewhere.
		awk '/^static .*\(|^[a-zA-Z_].*\(.*\)$/ { fn=$0; acq=0 }
			/^}/ { fn=""; acq=0 }
			fn != "" && /(_get\(|_inc\(|lunatik_newobject|kref_get)/ { acq=FNR; next }
			fn != "" && acq && /(luaL_argcheck|luaL_argerror|lunatik_throw)/ {
				if (FNR - acq > 2) print FNR
				acq=0
			}' "$file" | \
			finding "raises (argcheck/throw) after acquiring a resource in the same function; walk the error-path matrix — for each raise, what is already held and who releases it. Validate before acquiring whenever the check does not need the resource"
		awk '/@type[[:space:]]+[A-Za-z_]/ { types[$3]=NR }
			/\{"[a-z_]+",/ { name=$0; sub(/^[^"]*"/, "", name); sub(/".*/, "", name); fns[name]=1 }
			END { for (t in types) if (t in fns) print types[t] }' "$file" | \
			finding "names an LDoc type after a registered function: @treturn resolves to the function page, not to the type. Name the type after the class, as crypto does with crypto_shash alongside crypto.shash"
	fi
}

for f in "$@"; do
	findings=$(check "$f")
	[ -n "$findings" ] && { echo "$findings"; rc=1; }
done
exit $rc

