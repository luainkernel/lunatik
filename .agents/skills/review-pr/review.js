// A pull request review as a workflow in phases, each one short enough to
// survive a provider error and resumable from the cache when one does not.
//
// Every phase appends what it finds to a checkpoint file the moment it finds it,
// so a phase that dies leaves its findings on disk and its successor continues
// from them instead of reading the branch again. The build phase runs only when
// the head has not been validated already, an example the change touches has not been
// run on it, or the branch moved past the validated head in a file the build, the
// install or the suite reads; a fixup to documentation or the harness leaves the
// validated run standing.
//
// Usage: Workflow({scriptPath: '.agents/skills/review-pr/review.js', args: {...}})
//   pr          pull request number
//   branch      the author's branch, fetched and pushed by name
//   head, base  the head to review and the base it sits on, as full or short SHAs
//   scratch     an absolute directory for worktrees and the checkpoint
//   validated   {suite: "pass:N fail:0 skip:0", core: "<srcversion>", examples: [...]} when the exact
//               head already passed the suite, with the examples run on it through
//               tools/watchdog.sh, or null to build and run it here
//   examples    the examples the change touches, as tools/checks/examples-touched.sh lists
//               them over the changed files; the build phase runs whichever of them
//               validated does not carry
//   focus       what this round is for, in the maintainer's words
//   effort      per-phase reasoning effort, default "high"
//   model       the model each phase runs on, default the session's
//   push        false where a push from an agent is refused on this machine, so a fixup stays a
//               commit on review<pr>-fixups and the session that launched the review pushes it
//   repo        the checkout the phases work in, default the repository they start in
//   sudo        how a command gets root, default `sudo`
//   gh          false where the gh CLI is absent, so the REST calls go through curl
//
// It returns each phase's answer and findings_left, every finding a phase leaves as an issue,
// with a title and a body that can be filed as they stand.

export const meta = {
  name: 'review-pr',
  description: 'Review a pull request in phases: hunt findings, check the rules, build and run only if needed',
  phases: [{ title: 'Hunt' }, { title: 'Rules' }, { title: 'Build' }],
}

const a = args
const effort = a.effort || 'high'
const model = a.model ? { model: a.model } : {}
const checkpoint = `${a.scratch}/review${a.pr}/REVIEW.md`
// the prompt is read by an agent with a shell, so the default resolves on the machine that runs it
const repo = a.repo || '$(git rev-parse --show-toplevel)'
const sudo = a.sudo || 'sudo'
// gh is not on every machine; the same REST call goes through curl where it is absent
const api = (path) => a.gh === false
  ? `curl -sS -H "Authorization: Bearer $GH_TOKEN" "https://api.github.com/${path}?per_page=100"`
  : `gh api --paginate ${path}`

// a push from an agent is refused on some machines, so the fixup stays a commit and its launcher pushes
const FIXUP = a.push === false
  ? `A finding you can fix ships as \`git commit --fixup=<the commit that introduced it>\` on the local
branch review${a.pr}-fixups, taken from \`${a.branch}\`. Push nothing: the session that launched this
review pushes, and your answer names every SHA it made.`
  : `A finding you can fix ships as \`git commit --fixup=<the commit that introduced it>\` on
\`${a.branch}\`, pushed as soon as made (\`git push origin ${a.branch}:${a.branch}\`; where \`origin\`
is not writable from this machine, CLAUDE.local.md says how it pushes).`

const COMMON = `
You are reviewing pull request #${a.pr} of Lunatik (Lua in the Linux kernel), in the checkout at \`${repo}\`:
branch \`${a.branch}\`, head \`${a.head}\`, base \`${a.base}\`.

CHECKPOINT, before anything else: the file ${checkpoint} is the review's memory across phases and across
a phase that dies. If it exists, read it and continue from it; do not redo what it records. Append every
finding the moment you close it, one line each:
\`file:line | what | disposition\` where disposition is \`fixup <sha>\`, \`stays: <reason>\` or \`issue: <title>\`.
An \`issue:\` line is also an entry of your answer's findings_left, whose body can be filed as it stands: what
the code does and where, the trace, the fix where there is one; its severity is the label AGENTS.md "Findings"
names, and its home the open issue it belongs to, where one exists.
Your final answer is assembled from that file, not the other way round, and goes back into it under a heading
for your phase before you return, so a death between your last tool call and the runner's record still leaves
the verdict on disk.

ENVIRONMENT:
- Root commands run as \`${sudo} <cmd>\`; confirm that works without a prompt (\`${sudo} true\`) before
  the Build phase, and where it does not, say so and skip the build rather than ask for a password.
- Work in a worktree of your own under ${a.scratch}/, created with an ABSOLUTE path
  (\`git -C ${repo} worktree add <abs path> <ref>\`, then \`git submodule update --init\`),
  named review${a.pr}-<phase>. The worktrees, the stash, the device and the examples are shared, as AGENTS.md
  "Build, install, test" and the guards it describes say.
- GitHub reads go through
  \`${api('<path>')}\` with \`GH_TOKEN\` from the environment${a.gh === false ? '' : ' (`gh pr view` fails, no read:org)'};
  where \`GH_TOKEN\` is unset, report that the conversation could not be read. DO NOT POST ANYTHING TO GITHUB.
- A command the host's policy refuses is written in the checkpoint and not tried again: six retries of one
  refused push is how a nine hour run returned nothing for the pull request it was on.

${FIXUP} Its SHA goes in the checkpoint line. Ask of each one
whether the finding is answered by removing rather than adding: a fix that grows a layer over the one it
found is the finding half read, and the shape that answers it is usually shorter than what is there. A fixup
that changes C must at least \`make\` clean before it leaves your phase; the suite is the Build phase's.

${a.focus ? 'THIS ROUND, in the maintainer\'s words: ' + a.focus : ''}
`

const HUNT = COMMON + `
PHASE: HUNT. Read the whole change cold, as one diff against \`${a.base}\`, every changed file end to end,
and the pull request's threads (\`${api(`repos/luainkernel/lunatik/pulls/${a.pr}/comments`)}\`),
which record what the maintainer cares about.

Hunt the smallest shape first: for every mechanism the diff adds (a registration path, a new API argument,
a helper, a name), write the smaller change that would leave the same defect unreachable and why it was not
taken; where correctness is equal and the shape is smaller, that is a finding, shipped as the fixup that
makes it. Then residues of the path: anything in the final diff that exists because of how the branch grew rather
than because the final shape needs it. Names first: for every identifier the diff introduces or renames,
ask what it distinguishes from in the final tree and whether master already had a name for the same thing.
Then comments, LDoc, commit bodies, the pull request body, READMEs and doc/capi.md: a sentence that answers
a question an earlier shape raised is a residue. Then what the change duplicates: a field that keeps its
own copy of a value another field carries has decided the two can differ, so grep every reader of the
original and say which of the two each one wants, and read an architecture this host cannot run for every
use, not only the one the diff touches. Then the reach of a core change: for every primitive the diff
touches (\`CHECK_BASE=${a.base} bash tools/checks/blast-radius.sh lunatik.h lunatik_*.[ch]\`), name the arm
the bug takes and the arms the fix moves; a fix that moves an arm the bug does not take is a finding,
whatever the commit body says. Then correctness: for every raise, what is held and who releases
it; every get against its put; the execution context of every path; the teardown order.

A finding whose stimulus is a script out of contract (AGENTS.md, "Deciding what to change") is dismissed,
neither fixed nor left as an issue.

Write each finding to the checkpoint as you close it. Fix what you can as fixups.
`

const RULES = COMMON + `
PHASE: RULES. The Hunt phase's findings are in the checkpoint; read them first and do not repeat them.

Go through AGENTS.md section by section (Object model, C style, Lua style, Comments and documentation,
Tests, Deciding what to change, Patches and commits, Before opening a pull request) and for each rule say
applies or not, and if it applies, pass or fail, with the line. Where a rule can be checked by a grep or a
script, run it rather than read for it. Run every check in tools/checks/ over the full changeset
(\`git diff --name-only ${a.base}..${a.head}\`), and pr-body.sh on the pull request body; consumers.sh reads
\`LUNATIK_CONSUMERS\` from the environment and is silent where it is unset, so report that the consumer check
did not run rather than that no consumer was found. Where a check complains about something master already
does, say so with the evidence. Write the coverage matrix, operation by type by outcome including the
successes, and say what the tests prove and what nothing on this kernel can see.

Append each failing rule and each gap to the checkpoint as a finding; fix what you can as fixups.
`

const unrun = (a.examples || []).filter(e => !(a.validated?.examples || []).includes(e))
const UNBUILT = 'a Markdown file, or a path under doc/, .agents/, .claude/, .github/ or tools/checks/, or config.ld'

const BUILD = COMMON + `
PHASE: BUILD. The head is either not yet validated, moved by a fixup, or an example the change touches
has not been run on it. In a worktree at the current tip of \`${a.branch}\`: \`make\` clean,
\`${sudo} env PWD=$PWD make install\`, \`${sudo} lunatik reload\`, \`${sudo} lunatik test\`, all
inside your turn, never armed in the background. Run the examples the change touches through tools/watchdog.sh,
not merely built, each one driven as its README says and stopped, with dmesg read after: the suite covers what a
test author thought of, an example is the binding at the rate a user drives it.
${unrun.length ? 'These have not been run on this head: ' + unrun.join(', ') + '.' : ''}
${a.validated && !unrun.length ? `Before any of that: \`${a.head}\` already passed (${a.validated.suite}, core ${a.validated.core}),
so list what the branch changed since, \`git diff --name-only ${a.head} <the tip>\`. When every path is ${UNBUILT},
which the build, the install and the suite never read, run nothing: answer skipped true, with the tip as head, the
validated totals and core, and the paths in notes.` : ''}
Report the totals, the core srcversion (\`/sys/module/lunatik/srcversion\` while loaded), the examples run, and
any kernel complaint in dmesg.
`

const LEFT = { type: 'array', items: { type: 'object', properties: {
  title: { type: 'string' }, body: { type: 'string' }, severity: { type: 'string', enum: ['high', 'medium', 'low'] },
  home: { type: 'integer', description: 'the open issue this finding belongs to' },
}, required: ['title', 'body', 'severity'] } }

const FINDINGS = {
  type: 'object',
  properties: {
    ready: { type: 'boolean' },
    findings: { type: 'array', items: { type: 'object', properties: {
      file: { type: 'string' }, line: { type: 'integer' }, what: { type: 'string' }, disposition: { type: 'string' },
    }, required: ['file', 'what', 'disposition'] } },
    fixups: { type: 'array', items: { type: 'string' } },
    findings_left: LEFT,
    notes: { type: 'string' },
  },
  required: ['ready', 'findings', 'fixups', 'findings_left', 'notes'],
}

const RULES_OUT = {
  type: 'object',
  properties: {
    rules: { type: 'array', items: { type: 'object', properties: {
      rule: { type: 'string' }, applies: { type: 'boolean' }, pass: { type: 'boolean' }, where: { type: 'string' },
    }, required: ['rule', 'applies'] } },
    checks: { type: 'array', items: { type: 'object', properties: {
      name: { type: 'string' }, result: { type: 'string' },
    }, required: ['name', 'result'] } },
    coverage: { type: 'string' },
    findings: FINDINGS.properties.findings,
    fixups: FINDINGS.properties.fixups,
    findings_left: LEFT,
  },
  required: ['rules', 'checks', 'coverage', 'findings', 'fixups', 'findings_left'],
}

const BUILD_OUT = {
  type: 'object',
  properties: {
    totals: { type: 'string' }, core: { type: 'string' }, head: { type: 'string' },
    skipped: { type: 'boolean', description: 'true when only unbuilt paths moved past the validated head' },
    examples: { type: 'array', items: { type: 'string' } }, clean: { type: 'boolean' }, notes: { type: 'string' },
    findings_left: LEFT,
  },
  required: ['totals', 'core', 'head', 'clean', 'findings_left'],
}

phase('Hunt')
const hunt = await agent(HUNT, { label: `hunt:${a.pr}`, phase: 'Hunt', effort, schema: FINDINGS, ...model })

phase('Rules')
const rules = await agent(RULES, { label: `rules:${a.pr}`, phase: 'Rules', effort, schema: RULES_OUT, ...model })

const changed = !hunt || !rules || hunt.fixups.length + rules.fixups.length > 0
let build = null
if (!a.validated || changed || unrun.length) {
  phase('Build')
  build = await agent(BUILD, { label: `build:${a.pr}`, phase: 'Build', effort: 'medium', schema: BUILD_OUT, ...model })
  if (build?.skipped)
    log(`build skipped: ${a.head} validated, and the branch moved past it only in paths the build does not read`)
} else {
  log(`build skipped: head ${a.head} already validated (${a.validated.suite}, core ${a.validated.core}, examples ${(a.validated.examples || []).join(' ') || 'none'}) and no fixup changed it`)
}

const findings_left = [hunt, rules, build].flatMap(p => p?.findings_left || [])
return { checkpoint, hunt, rules, build, validated: build && !build.skipped ? null : a.validated, findings_left }

