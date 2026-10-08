---
paths:
  - "**/*.c"
  - "**/*.h"
  - "**/*.lua"
  - "**/*.sh"
  - "**/*.md"
  - "**/config.ld"
  - "**/bin/**"
  - "**/tools/**"
---

# Comments and documentation

* Comments describe the present, not the history. No "was", "no longer", "used to".
* No comments restating obvious kernel or Lua API usage. Non obvious rationale is welcome.
* A consumer does not document the API it calls: what a binding does belongs to its doc block and to
  the example's own `README.md`, and a copy in the script that calls it rots on the next change.
  `examples/ifquarantine` carried `notifier.netdevice(callback) -- replays a REGISTER for each device
  that already exists`, which `notifier.netdevice`'s own block and the example's README paragraph
  already say.
* A comment is one line carrying the reason the code is not obvious, nothing the code below already
  says. State the why; the what and the how are the code's job. A second clause defending the choice,
  or walking the mechanism a second time, is neither and reads as doubt: `/* a bottom-half unlock with
  IRQs off runs the pending softirqs inline, inside a kprobe handler */` gives the reason and stops.
* A comment about a specific call goes on that call's line, not above the function signature, and
  the call is the one the fact is about: `%pe keeps the sign` is about the `snprintf` that formats
  the errno, and the `buf + 1` on the line below reads on from it; put on the `lua_pushstring`
  instead, it reads as a note about pushing a string, and #990 merged that way before it was
  noticed.
* Code that serves a range of kernels says the range, above the line it applies to: `-- v6.11 and
  later: sk_skb_reason_drop(sk, skb, reason)` above that entry of a table, `-- v6.10 and earlier:
  kfree_skb_reason(skb, reason)` above the other. What changed at the release, `v6.11 turned
  kfree_skb_reason into a static inline over sk_skb_reason_drop`, is history and goes in the commit
  body; written above the table instead, with an order its entries did not need, it left the reader
  to work out which entry served which kernel, and the review of #929 called it ready to merge before
  the maintainer asked for the range on each entry. `comment-style.sh` names a comment that pairs a
  release with a verb of change, and one that names a release above the opening of a table.
* A literal in a comment is either the rule or marked as one instance of it. `/* "-ENOENT":
  errname keeps the sign */` read as a case special to that errno until the maintainer asked
  whether it was only an example; `/* %pe keeps the sign, e.g. "-ENOENT" */` says the rule and
  shows one value of it. A bare example reads as the whole.
* When the surprise is the call itself, a `put` where the tree would `stop`, the comment on the
  call's line gives the one reason it is not the expected call, `/* last reference: a stop would
  lock, and this can run in softirq */`; when the alternative is the other arm of the same `if`,
  the reason alone, `else /* this arm may sleep */`. The comment states the choice, not the world
  behind it; the invariant the choice rests on is the commit body's.
* Reaching for a comment is a signal to reconsider the code's clarity first: a name that states the
  intent, a helper that names the step, an enum instead of a bare constant. Comment what the code
  cannot be made to say, not what a clearer shape would.
* A condition that needs a comment to say what it tests is a predicate that has not been named yet:
  give it one in the `lunatik_isirq` family's shape, one expression over one argument, defined where
  its reader is, with the line of reason on the definition and nothing on the use. #797 carried
  `if (in_task() && notifier->registrant == current) /* the replay... */` until the maintainer asked
  for `luanotifier_isreplay(notifier)`. So is a condition of three tests or more, or one that runs
  onto the next line, comment or not: #1705's `checksum()` spelled two until the maintainer asked
  for `luaskb_iswhole4` and `luaskb_iswhole6`, and `tools/checks/idioms.sh` names them.
* A comment on a definition says what the definition is, not what its one caller concludes from it;
  when the name already says the subject, it takes no comment at all.
* An internal `static inline` helper carries no block comment — `lunatik.h` keeps none on any of its
  own. A comment describing what such a helper does restates the code; the fix is removing it, not
  trimming it. A block survives only for a reason the code cannot state, as `checkkey`'s zero-size
  note does.
* Public functions and object types get LDoc comments. Use `@type <class>` names that do not collide
  with a function name, or LDoc will attach the wrong things.
* LDoc does not surface a method a class inherits. To show it on the subclass's page, add a doc-only
  `@function <class>:<method>` block there, with no function under it. A `--` comment placed directly
  before a `---` doc block silences that block; keep any rationale note above the doc block or inside
  the function.
* A new module needs an entry in `config.ld`, inserted in alphabetical order; the site lists it from
  there.
* Do not insert code between a doc block and the function it documents.
* A doc block states the contract, not how it was found. Keep the debugging story — the crash that
  motivated a guard, the scenario that produced a stale state — in the commit body, where history
  belongs.
* The same holds for inline rationale: say why the code is what it is, not what it would take if
  something changed. Speculation about a future refactor ages badly and reads as doubt.
* Enumerate in one place only, and prefer none: a list of modules that adopt a rule rots on the next
  adoption, and the list of who calls a guard is the code. Restrictions on using a function are
  documented on that function, in its own `@raise`, where the caller reads.
* A doc block and the code it describes share vocabulary: an `@raise` states its condition in the
  same words as the error message it documents, and a rename in the code is a rename in the prose
  above it. An error message that names an API element quotes its canonical name, `rcu.table` and
  not a paraphrase of it; the name is looked up, never composed.

