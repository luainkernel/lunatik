---
name: explain-pr
description: Explain in a few lines what a Lunatik pull request does and why, for a maintainer deciding whether to merge it. Use when asked to explain, summarise or describe a PR, a branch or a merged commit.
---

The question behind "explain #NNN" is a merge decision, not a description. The answer names the
mechanism that made the change necessary and what it costs the tree, and it is short enough to be
read in one pass.

# Where the answer comes from

- The diff, not the body. `gh api repos/luainkernel/lunatik/pulls/<N>` for base and head, then
  `git diff <base>...<head>` for the change the PR owns. A stacked PR is diffed against its own
  base, and the base of record is the `base.ref` field, not the commit's parent.
- The source the change rests on, read here: the kernel under `/usr/src/linux-headers-$(uname -r)`
  or a full tree, the vendored Lua under `lua/`, the sibling binding. A mechanism named from the
  pull request body is a claim repeated, not an explanation.
- The commit bodies are the author's account of why. Read them, then confirm the part the
  explanation will assert. Where they and the code disagree, the code wins and the disagreement is
  worth one line.

# What the answer says

1. One sentence for what it does, in the tree's own vocabulary.
2. What the code did before and what that cost, traced: the kernel function that charges, the API
   that sleeps, the reference nobody held. This is the half the maintainer cannot get from the
   title, and the half worth the words.
3. The shape of the change, minimally. Not a walk of the diff.
4. What it brings in tests, one line, and for a test-only change what the case proves and what makes
   it discriminate.

# What it does not say

- No verdict on merit and no praise. Whether it is worth merging is the maintainer's call; the
  explanation gives him what he needs to make it.
- Nothing inferred. Every mechanism named is one read in the source; what was not verified is said
  to be not verified, in the same breath.
- No restating the diff, no bullet list of every hunk, no headers on an answer this short.
- No em dashes: the text is often pasted somewhere public.

# Length

"In a few words" is a few short paragraphs. A change with one mechanism is three sentences. A stack,
or a change whose reason is a kernel contract, earns a table only when the items are genuinely
parallel, as a matrix of cases is.

