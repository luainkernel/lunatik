// A pull request review as a workflow in phases, each one short enough to
// survive a provider error and resumable from the cache when one does not.
//
// Every phase appends what it finds to a checkpoint file the moment it finds it,
// so a phase that dies leaves its findings on disk and its successor continues
// from them instead of reading the branch again. The build phase runs only when
// the head has not been validated already, a fixup changed the code, or an example
// the change touches has not been run on it.
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

export const meta = {
  name: 'review-pr',
  description: 'Review a pull request in phases: hunt findings, check the rules, build and run only if needed',
  phases: [{ title: 'Hunt' }, { title: 'Rules' }, { title: 'Build' }],
}

const a = args
const effort = a.effort || 'high'
const checkpoint = `${a.scratch}/review${a.pr}/REVIEW.md`

const COMMON = `
You are reviewing pull request #${a.pr} of Lunatik (Lua in the Linux kernel), repo /home/ubuntu/claude/lunatik:
branch \`${a.branch}\`, head \`${a.head}\`, base \`${a.base}\`. Work at maximum thoroughness within your phase.

READ FIRST, they are the authority and override anything below:
- /home/ubuntu/claude/lunatik/AGENTS.md, all of it
- /home/ubuntu/claude/lunatik/CLAUDE.local.md

CHECKPOINT, before anything else: the file ${checkpoint} is the review's memory across phases and across
a phase that dies. If it exists, read it and continue from it; do not redo what it records. Append every
finding the moment you close it, one line each:
\`file:line | what | disposition\` where disposition is \`fixup <sha>\`, \`stays: <reason>\` or \`issue: <title>\`.
Your final answer is assembled from that file, not the other way round.

ENVIRONMENT:
- sudo password is "ubuntu": \`echo ubuntu | sudo -S -p '' <cmd>\`.
- Work in a worktree of your own under ${a.scratch}/, created with an ABSOLUTE path
  (\`git -C /home/ubuntu/claude/lunatik worktree add <abs path> <ref>\`, then \`git submodule update --init\`),
  named review${a.pr}-<phase>. Never touch a worktree that is not yours; every lunatik_* worktree under
  /home/ubuntu/claude/ belongs to someone else.
- NEVER \`git stash\` anywhere in this repository: the stash stack is shared and \`stash@{0}\` is another
  agent's work. Compare revisions with a throwaway worktree or \`git show <ref>:<path>\`.
- /dev/lunatik is single: never two lunatik operations at once, check with ps first. NEVER run
  \`lunatik run examples/ifquarantine/control\` bare; any example goes through \`sudo bash tools/watchdog.sh\`.
  \`tests/probe/armed.sh\` must never run against a build without \`lunatik_checkarmed\`.
- NEVER commit to master, never \`git checkout master\`. GitHub: \`export GH_TOKEN=$(cat /home/ubuntu/.config/gh-token)\`
  then \`gh api ...\` (\`gh pr view\` fails, no read:org; pass --paginate). DO NOT POST ANYTHING TO GITHUB.
- aarch64, kernel 6.8.0-138. Kernel source: /home/ubuntu/linux-hwe-6.8-6.8.0/ . Vendored Lua 5.5.

A finding you can fix ships as \`git commit --fixup=<the commit that introduced it>\` on \`${a.branch}\`,
pushed as soon as made
(\`git push "https://x-access-token:$(cat /home/ubuntu/.config/gh-token)@github.com/luainkernel/lunatik.git" ${a.branch}:${a.branch}\`),
and its SHA goes in the checkpoint line. A fixup that changes C must at least \`make\` clean before it is
pushed; the suite is the Build phase's.

${a.focus ? 'THIS ROUND, in the maintainer\'s words: ' + a.focus : ''}
`

const HUNT = COMMON + `
PHASE: HUNT. Read the whole change cold, as one diff against \`${a.base}\`, every changed file end to end,
and the pull request's threads (\`gh api --paginate repos/luainkernel/lunatik/pulls/${a.pr}/comments\`),
which record what the maintainer cares about.

Hunt residues of the path: anything in the final diff that exists because of how the branch grew rather
than because the final shape needs it. Names first: for every identifier the diff introduces or renames,
ask what it distinguishes from in the final tree and whether master already had a name for the same thing.
Then comments, LDoc, commit bodies, the pull request body, READMEs and doc/capi.md: a sentence that answers
a question an earlier shape raised is a residue. Then what the change duplicates: a field that keeps its
own copy of a value another field carries has decided the two can differ, so grep every reader of the
original and say which of the two each one wants, and read an architecture this host cannot run for every
use, not only the one the diff touches. Then correctness: for every raise, what is held and who releases
it; every get against its put; the execution context of every path; the teardown order.

Write each finding to the checkpoint as you close it. Fix what you can as fixups.
`

const RULES = COMMON + `
PHASE: RULES. The Hunt phase's findings are in the checkpoint; read them first and do not repeat them.

Go through AGENTS.md section by section (Object model, C style, Lua style, Comments and documentation,
Tests, Deciding what to change, Patches and commits, Before opening a pull request) and for each rule say
applies or not, and if it applies, pass or fail, with the line. Where a rule can be checked by a grep or a
script, run it rather than read for it. Run every check in tools/checks/ over the full changeset
(\`git diff --name-only ${a.base}..${a.head}\`), with
LUNATIK_CONSUMERS=/home/ubuntu/claude/dome_master:/home/ubuntu/claude/dome_private for consumers.sh and
pr-body.sh on the pull request body; where a check complains about something master already does, say so
with the evidence. Write the coverage matrix, operation by type by outcome including the successes, and say
what the tests prove and what nothing on this kernel can see.

Append each failing rule and each gap to the checkpoint as a finding; fix what you can as fixups.
`

const unrun = (a.examples || []).filter(e => !(a.validated?.examples || []).includes(e))

const BUILD = COMMON + `
PHASE: BUILD. The head is either not yet validated, a fixup changed the code, or an example the change touches
has not been run on it. In a worktree at the current tip of \`${a.branch}\`: \`make\` clean,
\`echo ubuntu | sudo -S -p '' env PWD=$PWD make install\`, \`sudo lunatik reload\`, \`sudo lunatik test\`, all
inside your turn, never armed in the background. Run the examples the change touches through tools/watchdog.sh,
not merely built, each one driven as its README says and stopped, with dmesg read after: the suite covers what a
test author thought of, an example is the binding at the rate a user drives it.
${unrun.length ? 'These have not been run on this head: ' + unrun.join(', ') + '.' : ''}
Report the totals, the core srcversion (\`/sys/module/lunatik/srcversion\` while loaded), the examples run, and
any kernel complaint in dmesg.
`

const FINDINGS = {
  type: 'object',
  properties: {
    ready: { type: 'boolean' },
    findings: { type: 'array', items: { type: 'object', properties: {
      file: { type: 'string' }, line: { type: 'integer' }, what: { type: 'string' }, disposition: { type: 'string' },
    }, required: ['file', 'what', 'disposition'] } },
    fixups: { type: 'array', items: { type: 'string' } },
    notes: { type: 'string' },
  },
  required: ['ready', 'findings', 'fixups', 'notes'],
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
  },
  required: ['rules', 'checks', 'coverage', 'findings', 'fixups'],
}

const BUILD_OUT = {
  type: 'object',
  properties: {
    totals: { type: 'string' }, core: { type: 'string' }, head: { type: 'string' },
    examples: { type: 'array', items: { type: 'string' } }, clean: { type: 'boolean' }, notes: { type: 'string' },
  },
  required: ['totals', 'core', 'head', 'clean'],
}

phase('Hunt')
const hunt = await agent(HUNT, { label: `hunt:${a.pr}`, phase: 'Hunt', effort, schema: FINDINGS })

phase('Rules')
const rules = await agent(RULES, { label: `rules:${a.pr}`, phase: 'Rules', effort, schema: RULES_OUT })

const changed = (hunt?.fixups?.length || 0) + (rules?.fixups?.length || 0) > 0
let build = null
if (!a.validated || changed || unrun.length) {
  phase('Build')
  build = await agent(BUILD, { label: `build:${a.pr}`, phase: 'Build', effort: 'medium', schema: BUILD_OUT })
} else {
  log(`build skipped: head ${a.head} already validated (${a.validated.suite}, core ${a.validated.core}, examples ${(a.validated.examples || []).join(' ') || 'none'}) and no fixup changed it`)
}

return { checkpoint, hunt, rules, build, validated: build ? null : a.validated }

