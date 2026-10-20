/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

// A review as a workflow in two phases, each short enough to survive a provider error and resumable
// from the cache when one does not: a reviewer that reads the change once, through the packet the
// machine gathers for it, and a build that runs the host only when the head was not validated, a
// fixup changed what the build reads, or an example the change touches was not run on it.
//
// Every phase appends what it finds to a checkpoint file the moment it finds it, so a phase that
// dies leaves its findings on disk and its successor continues from them instead of reading the
// branch again.
//
// Usage: Workflow({scriptPath: '.agents/skills/review-pr/review.js', args: {...}})
//   pr          the pull request, or 0 for a branch none opened yet, which has no conversation to read
//   branch      the author's branch, fetched and pushed by name
//   head, base  the head to review and the base it sits on, as full or short SHAs
//   scratch     an absolute directory for worktrees and the checkpoint
//   validated   {suite: "pass:N fail:0 skip:0", core: "<srcversion>", examples: [...]} when the exact
//               head already passed the suite, with the examples run on it through
//               tools/watchdog.sh, or null to build and run it here
//   examples    the examples the change touches, as tools/checks/examples-touched.sh lists
//               them over the changed files; the build phase runs whichever of them
//               validated does not carry
//   defects     [{patch, suite, fails}], the defect each new test is for, as implement-issue's
//               implementer writes them; the build plants each once the suite passed
//   focus       what this round is for, in the maintainer's words
//   smallest    the implementer's smallest shape, when implement-issue launches the review
//   body        the body a branch with no pull request yet opens with, which the reviewer answers
//               corrected against the final diff
//   reviewer    false to run the build phase alone, as implement-issue does after a fix
//   effort      the reviewer's reasoning effort, default "high"
//   model       the model the reviewer runs on, default the session's
//   agents      {model, effort} for each phase's agent, under review and build: review's over effort
//               and model, build's over its agent's definition, sonnet at medium effort
//   push        false where a push from an agent is refused on this machine, so a fixup stays a
//               commit on review<pr>-fixups and the session that launched the review pushes it
//   repo        the checkout the phases work in, default the repository they start in
//   machine     how this machine gets root and authenticates gh, for the build phase, whose agent
//               loads no CLAUDE.local.md; the launching session copies it from there
//   gh          false where the gh CLI is absent, so the REST calls go through curl
//   github      the repository on GitHub, owner/name, default luainkernel/lunatik; another one is
//               reviewed with this tree's packet and its own build
//   packet      the script that writes the packet, default tools/review-packet.sh of the tree under
//               review; an absolute path to this tree's where that tree carries none
//   build       what the build phase runs instead of the suite, for a tree that is not Lunatik, or
//               false where nothing runs on the host
//
// It returns each phase's answer and findings_left, every finding a phase leaves as an issue,
// with a title and a body that can be filed as they stand.

export const meta = {
  name: 'review-pr',
  description: 'Review a pull request: read it for findings over the packet the machine gathers, build and run only if needed',
  phases: [{ title: 'Review' }, { title: 'Build' }],
}

const a = args
const agents = a.agents || {}
const effort = agents.review?.effort || a.effort || 'high'
const model = agents.review?.model || a.model ? { model: agents.review?.model || a.model } : {}
const builder = { effort: (agents.build || {}).effort || 'medium', ...((agents.build || {}).model ? { model: agents.build.model } : {}) }
const github = a.github || 'luainkernel/lunatik'
const lunatik = github === 'luainkernel/lunatik'
const packetTool = a.packet || 'tools/review-packet.sh'
// a pull request of another repository shares no numbering with this one's checkpoints
const unit = a.pr ? (lunatik ? `review${a.pr}` : `review-${github.split('/')[1]}-${a.pr}`) : `review-${a.branch}`
const checkpoint = `${a.scratch}/${unit}/REVIEW.md`
const packet = `${a.scratch}/${unit}/packet.txt`
// the prompt is read by an agent with a shell, so the default resolves on the machine that runs it
const repo = a.repo || '$(git rev-parse --show-toplevel)'
// gh is not on every machine; the same REST call goes through curl where it is absent
const api = (path) => a.gh === false
  ? `curl -sS -H "Authorization: Bearer $GH_TOKEN" "https://api.github.com/${path}?per_page=100"`
  : `gh api --paginate ${path}`

// a push from an agent is refused on some machines, so the fixup stays a commit and its launcher pushes
const FIXUP = a.push === false
  ? `A finding you can fix ships as \`git commit --fixup=<the commit that introduced it>\` on the local
branch ${unit}-fixups, taken from \`${a.branch}\`. Push nothing: the session that launched this
review pushes, and your answer names every SHA it made.`
  : a.pr
  ? `A finding you can fix ships as \`git commit --fixup=<the commit that introduced it>\` in your own
worktree, detached at the head of \`${a.branch}\`, pushed as soon as made (\`git push origin HEAD:refs/heads/${a.branch}\`;
where \`origin\` is not writable from this machine, CLAUDE.local.md says how it pushes).`
  : `A finding you can fix is \`git commit --fixup=<the commit that introduced it>\` in your own worktree, detached at
\`${a.head}\`, folded into that commit before you return (\`git rebase -i --autosquash ${a.base}\`), since no pull request exists yet
and the maintainer's first review reads it squashed; push it with \`git push origin HEAD:refs/heads/${a.branch}
--force-with-lease=refs/heads/${a.branch}:<the head you started from>\` (where \`origin\` is not writable from
this machine, CLAUDE.local.md says how it pushes), and your answer's tip is the head after the fold.`

const COMMON = `
You are reviewing ${a.pr ? `pull request #${a.pr}` : `the branch \`${a.branch}\`, which has no pull request yet,`} of
${lunatik ? 'Lunatik (Lua in the Linux kernel)' : `${github}, which runs on Lunatik (Lua in the Linux kernel)`}, in the checkout at \`${repo}\`: branch \`${a.branch}\`, head \`${a.head}\`,
base \`${a.base}\`.

CHECKPOINT, before anything else: the file ${checkpoint} is the review's memory across phases and across
a phase that dies. If it exists, read it and continue from it; do not redo what it records. Append every
finding the moment you close it, one line each:
\`file:line | what | disposition\` where disposition is \`fixup <sha>\`, \`stays: <reason>\` or \`issue: <title>\`.
An \`issue:\` line is also an entry of your answer's findings_left, whose body can be filed as it stands: what
the code does and where, the trace, the fix where there is one; its severity is the label
.agents/skills/review-pr/process.md "Findings" names, and its home the open issue it belongs to, where one exists.
Your final answer is assembled from that file, not the other way round, and goes back into it under a heading
for your phase before you return, so a death between your last tool call and the runner's record still leaves
the verdict on disk.

ENVIRONMENT:
- Work in a worktree of your own under ${a.scratch}/, created with an ABSOLUTE path
  (\`git -C ${repo} worktree add --detach <abs path> <ref>\`, then \`git submodule update --init\`),
  named ${unit}-<phase>. A worktree that has the branch checked out is the launching session's, with its
  work in progress, and no phase commits, rebases or checks out there. The worktrees, the stash, the
  device and the examples are shared, as AGENTS.md "Build, install, test" and the guards it describes say.
- GitHub reads go through \`${api('<path>')}\`. DO NOT POST ANYTHING TO GITHUB.
- A command the host's policy refuses is written in the checkpoint and not tried again.

${a.focus ? 'THIS ROUND, in the maintainer\'s words: ' + a.focus : ''}
`

const REVIEW = COMMON + `
PHASE: REVIEW. The process is .agents/skills/review-pr/process.md; read its "Findings" and "Fixups" first.

Then, in your worktree at \`${a.head}\`, write the packet the machine gathers for you, and read it whole
before anything else: \`bash ${packetTool} ${a.base} ${a.head} > ${packet}\`. It carries the commits
with their bodies, the files, what every check says and the diff with each function it touches whole, so
open a file beyond it only for what it does not show: a caller, a sibling, the kernel. The rules for the
files you read load with them, from .agents/rules/.${a.pr ? `
Read the pull request's threads too (\`${api(`repos/${github}/pulls/${a.pr}/comments`)}\` and
\`${api(`repos/${github}/issues/${a.pr}/comments`)}\`), which record what the maintainer cares about,
and run tools/checks/pr-body.sh over its body.` : ''}

Every line under "# Checks" is answered in the checkpoint: a fixup, or why the code stays; a line of
function-shape.sh with the function's jobs listed, and one of kernel-answer.sh with the facility the commit
was compared with. Where a check complains about something master already does, say so with the evidence.

Look for the smallest shape first: for every mechanism the diff adds (a registration path, a new API argument,
a helper, a name), write the smaller change that would leave the same defect unreachable and why it was not
taken; where correctness is equal and the shape is smaller, that is a finding, shipped as the fixup that
makes it. Your answer's smallest is that reading of the whole diff: the smallest shape, its size beside the
diff's, and what each mechanism past it buys.${a.smallest ? `
The implementer's own reading, which yours is not bound by: ${JSON.stringify(a.smallest)}` : ''}${a.body && !a.pr ? `
The pull request opens with this body once the build passes; read it with the commit bodies, and your answer's
body is this text with what the final diff, your fixups included, makes untrue corrected, the rest as it stands:
${JSON.stringify(a.body)}` : ''}
For every mechanism the diff builds over a kernel primitive, name the kernel's own answer to the problem it
solves, from Documentation/ and the primitive's users in the kernel tree, and say why the diff's shape and not
that one. For every field the diff adds beside an embedded kernel object, say what the object already records.
For every read the diff removes, name what was stored, sized or kept only for that read. Then residues of
the path: anything in the final diff that exists because of how the branch grew rather than because the final
shape needs it, names first, then comments, LDoc, commit bodies, the pull request body, READMEs and
doc/capi.md. Then what the change duplicates: a field that keeps its own copy of a value another field
carries, every reader of the original, and which of the two each one wants. Then the reach of a core change:
for every primitive the diff touches, the arm the bug takes and the arms the fix moves. Then correctness:
for every raise, what is held and who releases it; every get against its put; the execution context of every
path; the teardown order. Then the matrix the change is held to, operation by type by outcome including the
successes, and what the tests prove.

Before a finding is written, read the code once more to refute it: one whose stimulus is a script out of
contract (AGENTS.md, "Deciding what to change") is dismissed, neither fixed nor left as an issue, and one
the code does not reach is dropped.

${FIXUP} Its SHA goes in the checkpoint line. Ask of each one whether the finding is answered by removing
rather than adding. A fixup that changes C must at least \`make\` clean before it leaves your phase; the suite
is the Build phase's.
`

const unrun = (a.examples || []).filter(e => !(a.validated?.examples || []).includes(e))

const BUILD = (tip) => `
PHASE: BUILD of ${a.pr ? `pull request #${a.pr}` : `the branch \`${a.branch}\``} of ${github}, in the checkout at \`${repo}\`.
${a.machine ? 'THIS MACHINE: ' + a.machine : 'Root commands run as `sudo <cmd>`; confirm that works without a prompt (`sudo -n true`) and, where it does not, skip the build and say so.'}

In a worktree of your own under ${a.scratch}/ at \`${tip}\`, the tip of \`${a.branch}\` with every fixup
(\`git -C ${repo} worktree add --detach <abs path> ${tip}\`, then \`git submodule update --init\`): ${typeof a.build === 'string' ? a.build : `\`make\` clean, then install, reload and the whole suite through tools/lunatik-host as the
lunatik-cycle skill orders it, then the examples the change touches through tools/watchdog.sh, each one
driven as its README says and stopped, with dmesg read after.`}
${(a.examples || []).length ? `The examples the change touches: ${a.examples.join(', ')}. Your answer's examples names
the ones that ran clean, driven until they did what their README shows, spelled as they are listed here; one
that only loaded and stopped, or could not run on this host, goes in loaded instead, with why.` : 'The change touches no example.'}
${unrun.length ? 'These have not been run on this head: ' + unrun.join(', ') + '.' : ''}
${(a.defects || []).length ? `Once the suite passed, plant each defect below in turn, to watch the test it is for
fail: \`git apply <patch>\` in a call of its own, so crash-guard.sh reads the tree it leaves, then \`make\`, and only
when it builds the install, the reload and \`lunatik test <suite>\` through tools/lunatik-host; the cases it names
should fail, and no other. \`git apply -R <patch>\`, in a call of its own, reverts it before the next. After the
last, build, install and reload the tip again and run those suites once more. A patch that does not apply and a
call a guard refuses are reported, not tried another way. Your answer's discrimination says, for each patch, the
cases that failed.
${JSON.stringify(a.defects, null, 2)}` : ''}
${a.validated && !unrun.length ? `Before any of that: \`${a.head}\` already passed (${a.validated.suite}, core ${a.validated.core}),
so ask what the branch changed since in what the host reads, \`(cd ${repo} && bash tools/checks/functional.sh ${a.head} ${tip})\`.
When it names nothing, comments, spacing, documents or the harness alone having moved, run nothing: answer skipped
true, with the tip as head, the validated totals and core, and \`git diff --name-only ${a.head} ${tip}\` in notes.` : ''}
Remove your worktree when you are done (\`rm -rf <tree> && git -C ${repo} worktree prune\`).
`

const LEFT = { type: 'array', items: { type: 'object', properties: {
  title: { type: 'string' }, body: { type: 'string' }, severity: { type: 'string', enum: ['high', 'medium', 'low'] },
  contract: { type: 'string', description: 'what the documentation promises for the stimulus, quoted with its file, or "undocumented"; the severity is read against it' },
  home: { type: 'integer', description: 'the open issue this finding belongs to' },
}, required: ['title', 'body', 'severity', 'contract'] } }

const SMALLEST = { type: 'object', properties: {
  shape: { type: 'string', description: 'the smallest change that makes the defect unreachable, or meets the need' },
  lines: { type: 'integer', description: 'the lines that change adds and removes' },
  diff: { type: 'integer', description: 'the lines the pull request adds and removes' },
  beyond: { type: 'array', items: { type: 'object', properties: {
    mechanism: { type: 'string' }, buys: { type: 'string', description: 'what it buys that the smallest shape does not' },
  }, required: ['mechanism', 'buys'] } },
}, required: ['shape', 'lines', 'diff', 'beyond'] }

const FINDINGS = {
  type: 'object',
  properties: {
    ready: { type: 'boolean' },
    findings: { type: 'array', items: { type: 'object', properties: {
      file: { type: 'string' }, line: { type: 'integer' }, what: { type: 'string' }, disposition: { type: 'string' },
    }, required: ['file', 'what', 'disposition'] } },
    fixups: { type: 'array', items: { type: 'string' } },
    tip: { type: 'string', description: 'the full SHA of the branch tip after every fixup' },
    coverage: { type: 'string', description: 'the matrix the change is held to, and what nothing on this kernel can see' },
    smallest: SMALLEST,
    body: { type: 'string', description: 'the body the pull request opens with, when one was handed to correct' },
    findings_left: LEFT,
    notes: { type: 'string' },
  },
  required: ['ready', 'findings', 'fixups', 'tip', 'coverage', 'smallest', 'findings_left', 'notes'],
}

const BUILD_OUT = {
  type: 'object',
  properties: {
    totals: { type: 'string' }, core: { type: 'string' }, head: { type: 'string' },
    skipped: { type: 'boolean', description: 'true when functional.sh named nothing past the validated head' },
    examples: { type: 'array', items: { type: 'string' } }, clean: { type: 'boolean' }, notes: { type: 'string' },
    loaded: { type: 'array', items: { type: 'object', properties: {
      example: { type: 'string' }, why: { type: 'string' },
    }, required: ['example', 'why'] }, description: 'the examples that only loaded and stopped, or could not run on this host' },
    discrimination: { type: 'array', items: { type: 'object', properties: {
      patch: { type: 'string' }, failed: { type: 'array', items: { type: 'string' }, description: 'the cases that failed with the defect planted' },
      notes: { type: 'string' },
    }, required: ['patch', 'failed'] } },
    findings_left: LEFT,
  },
  required: ['totals', 'core', 'head', 'clean', 'findings_left'],
}

let reviewer = null
if (a.reviewer !== false) {
  phase('Review')
  reviewer = await agent(REVIEW, { label: `review:${a.pr || a.branch}`, phase: 'Review', effort, schema: FINDINGS, ...model })
}

const changed = a.reviewer !== false && (!reviewer || reviewer.fixups.length > 0)
let build = null
if (a.build === false)
  log('build skipped: nothing runs on the host for this tree')
else if (!a.validated || changed || unrun.length) {
  phase('Build')
  build = await agent(BUILD(reviewer?.tip || a.head), { label: `build:${a.pr || a.branch}`, phase: 'Build', agentType: 'lunatik-host', schema: BUILD_OUT, ...builder })
  if (build?.skipped)
    log(`build skipped: ${a.head} validated, and the branch moved past it only in what the build does not read`)
} else {
  log(`build skipped: head ${a.head} already validated (${a.validated.suite}, core ${a.validated.core}, examples ${(a.validated.examples || []).join(' ') || 'none'}) and no fixup changed it`)
}

const findings_left = [reviewer, build].flatMap(p => p?.findings_left || [])
return { checkpoint, reviewer, build, validated: build && !build.skipped ? null : a.validated, findings_left }

