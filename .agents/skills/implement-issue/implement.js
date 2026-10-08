/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

// An issue implemented, reviewed, run once on the host and opened as a pull request, as one workflow:
// an implementer that traces the issue and commits what builds, review.js over the branch as a nested
// workflow, whose build phase is the one run of the suite and the examples the change touches, a fix
// of what that run fails, and the opening of the pull request on the head that passed. The host runs
// in an agent of its own, so the implementer's context never waits on a suite.
//
// Usage: Workflow({scriptPath: '.agents/skills/implement-issue/implement.js', args: {...}})
//   issue       the issue to implement
//   effort      the reasoning effort of the implementer, the hunt and a fix; required, since an agent
//               that names none runs at the session's default
//   scratch     an absolute directory for worktrees and the checkpoints
//   base        the branch the work starts from and the pull request targets, default master
//   branch      the branch the implementer creates, default one it names for the change
//   notes       what the launching session adds for the implementer, in its own words
//   focus       what the review is for, default notes
//   model       the model of the implementer, the hunt and a fix, default the session's
//   push        false where a push from an agent is refused on this machine: the implementer leaves
//               its commits on the branch, and no review runs
//   repo        the checkout's absolute path, where review.js is read and its phases work; required, since
//               a relative path resolves against the session's directory when the review starts
//   machine     how this machine gets root and authenticates gh, for the agents that load no
//               CLAUDE.local.md, the host's and GitHub's; the launching session copies it from there
//   gh          false where gh is absent: the agents write nothing to GitHub, and the pull request and
//               the filing are the session's
//
// It returns the implementer's answer, the review's, the pull request, the issues that now hold each
// entry of findings_left, and any entry left unfiled.

export const meta = {
  name: 'implement-issue',
  description: 'Implement an issue, review it, run it once on the host, and open its pull request',
  phases: [{ title: 'Implement' }, { title: 'Fix' }, { title: 'Open' }, { title: 'File' }],
}

const a = args || {}
for (const key of ['issue', 'effort', 'scratch', 'repo'])
  if (!a[key]) throw new Error(`implement-issue: args.${key} is required`)

const base = a.base || 'master'
const model = a.model ? { model: a.model } : {}
const checkpoint = `${a.scratch}/issue${a.issue}/IMPLEMENT.md`
const fileCheckpoint = `${a.scratch}/issue${a.issue}/FILED.md`
const REVIEW = `${a.repo}/.agents/skills/review-pr/review.js`
const MACHINE = a.machine ? `THIS MACHINE: ${a.machine}\n` : ''
const FIXES = 2
// where gh is absent curl reads GitHub and writes nothing to it, since no guard reads a write through curl
const github = a.gh === false
  ? 'curl against https://api.github.com with `Authorization: Bearer $GH_TOKEN`, as the review-pr skill spells it, to read only'
  : '`gh api`, as the review-pr skill spells it'
const PUSH = a.push === false
  ? 'Push nothing: the session that launched this workflow pushes the branch.'
  : 'Push each commit as a command of its own, as you make it.'

const IMPLEMENT = `
You implement issue #${a.issue} of Lunatik, in a worktree of your own under ${a.scratch}/ on
${a.branch ? `the branch \`${a.branch}\`` : 'a branch named for the change'}, started from \`origin/${base}\` as
fetched now. GitHub is read through its REST API, ${github}.
${a.notes ? '\nFROM THE SESSION THAT LAUNCHED THIS: ' + a.notes + '\n' : ''}
CHECKPOINT: ${checkpoint} is your memory across a death (AGENTS.md, "Patches and commits", on work an
agent does for a workflow). If it exists, read it first and continue from it. Append a line per step as
you take it, what you read, decided, committed and measured, and your answer before you return.

1. Read the issue and its comments, and the code and the kernel source they name; a cause is traced
   before it is written down (AGENTS.md rule 1). An issue whose stimulus is a script out of contract
   (AGENTS.md, "Deciding what to change") closes as not a defect, with no pull request.
2. Write the smallest shape that makes the defect unreachable, or meets the need, in the checkpoint
   before any other, and take a larger one only for what it buys (AGENTS.md, "Deciding what to change").
   Your answer's smallest carries that shape beside the diff, and names what each mechanism past it
   buys; the review and the maintainer read the change against it.
3. Commit as "Patches and commits" asks: one change per commit, the harness apart from the code, tests
   wired and described (the new-test skill), each doc where its reader looks. \`make\` is clean on every
   commit, and \`make C=1\` where the change touches an annotated pointer. ${PUSH}
4. Run "Before opening a pull request" with the pr-prep skill, except what needs the host: the suite and
   the examples run once, after the review, in an agent of their own, and a failure comes back to a fix.
   Run no install, reload, suite or example yourself. List the examples tools/checks/examples-touched.sh
   names over the changed files.
5. Draft the pull request's title and body as pr-prep says, into your answer; tools/checks/pr-body.sh
   passes the body, which carries \`Closes #${a.issue}\` on a line of its own and names each example as run:
   the pull request opens only on a head the host run passed with every one of them. Open nothing.

What you leave, a defect found on the way that is not this change's or a cell of the matrix no test covers,
goes in findings_left with a body that can be filed as it stands, its severity the label
.agents/skills/review-pr/process.md "Findings" names, read against the contract the entry quotes, and its
home the open issue it belongs to, where one exists; nothing is left in prose alone.
`

const FIX = (failed, head) => `
You fix what the host run of issue #${a.issue}'s branch failed, on \`${head}\`. Read ${checkpoint} first: the
implementer's memory of the change. The run reported:
${JSON.stringify(failed, null, 2)}

Trace the failure before you change anything (AGENTS.md rule 1): the test's prints, the errno, the journal
window the lunatik-cycle skill names. A failure the change causes is fixed as \`git commit --fixup=<the commit
that introduced it>\`, \`make\` clean, and pushed; one it does not cause, a host process or a test already
failing on master, is said as such with its evidence and fixes nothing. Run no install, reload, suite or
example: the host run that follows is another agent's. Append what you traced and committed to the checkpoint.
`

const OPEN = (impl, head) => `
${MACHINE}Open a pull request on luainkernel/lunatik from the branch \`${impl.branch}\` against \`${base}\`, whose head is
\`${head}\`; push the branch first if GitHub's tip of it is not that SHA. Title: ${JSON.stringify(impl.title)}

Body, as it stands:
${JSON.stringify(impl.body)}

The body goes through tools/checks/pr-body.sh before the command that opens it. Then label the pull request
\`workflow-reviewed\`, since the review ran over this head. Your answer is the pull request's number.
`

const FILE = (entries, source) => `
${MACHINE}File what the implementation of issue #${a.issue} and its review left, as issues of luainkernel/lunatik.
You post nothing on a pull request, no review and no comment.

CHECKPOINT: ${fileCheckpoint} records every entry already filed, one line each,
\`<index> | <title> | #<issue> | created\` or \`... | updated\`. Read it first and skip an entry whose index and
title it records, since an entry filed twice is a duplicate someone closes by hand; append the line the moment
the issue holds it.

For each entry:
- write its body to a file and run tools/checks/machine-leak.sh and tools/checks/untraced.sh over it; a line
  either one names is rewritten before anything is posted;
- an entry whose body carries \`Decision:\`, or whose home is an epic (a title that starts with \`Epic:\`),
  opens an issue of its own, whatever it reports, and its body ends with \`Part of #<home>.\` when it has a
  home;
- an entry whose home is an open issue goes to that issue: its body is appended to the issue's own under a
  line \`Update: <title> (#${source})\`, and the issue carries one severity label, the higher of its own and
  the entry's;
- an entry that reports what an open issue already reports, read in that issue and not guessed from its
  title, goes to it the same way;
- any other entry opens an issue with its title, its body as it stands and the label
  \`severity: <its severity>\`;
- the body carries the entry's contract on a line of its own, \`Contract: <contract>\`, the promise its
  severity was read against.

Your answer names, for every entry by its index, the issue that now holds it.

ENTRIES:
${JSON.stringify(entries.map((entry, index) => ({ index, ...entry })), null, 2)}
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

const IMPLEMENTED = {
  type: 'object',
  properties: {
    branch: { type: 'string', description: 'the branch, or empty when the issue closes with no change' },
    head: { type: 'string', description: 'the full SHA of the branch tip' },
    base: { type: 'string', description: 'the full SHA of the base the branch sits on, after any rebase' },
    commits: { type: 'array', items: { type: 'string' } },
    examples: { type: 'array', items: { type: 'string' }, description: 'what examples-touched.sh lists' },
    title: { type: 'string' },
    body: { type: 'string', description: 'the pull request body, which pr-body.sh passes' },
    smallest: SMALLEST,
    findings_left: LEFT,
    notes: { type: 'string' },
  },
  required: ['branch', 'head', 'base', 'commits', 'examples', 'title', 'body', 'smallest', 'findings_left', 'notes'],
}

const FIXED = { type: 'object', properties: {
  head: { type: 'string', description: 'the full SHA of the branch tip after the fix' },
  caused: { type: 'boolean', description: 'false when the failure is not the change\'s' },
  notes: { type: 'string' },
}, required: ['head', 'caused', 'notes'] }

const OPENED = { type: 'object', properties: { pr: { type: 'integer' }, notes: { type: 'string' } }, required: ['pr'] }

const FILED = { type: 'object', properties: {
  filed: { type: 'array', items: { type: 'object', properties: {
    index: { type: 'integer' }, number: { type: 'integer' }, action: { type: 'string', enum: ['created', 'updated'] },
  }, required: ['index', 'number', 'action'] } },
}, required: ['filed'] }

const reviewArgs = (impl, extra) => ({
  pr: 0, branch: impl.branch, base: impl.base, scratch: a.scratch, validated: null, examples: impl.examples,
  focus: a.focus || a.notes, smallest: impl.smallest, effort: a.effort, model: a.model, push: a.push,
  repo: a.repo, machine: a.machine, gh: a.gh, ...extra,
})
const passed = (build) => build && build.clean && /fail:0\b/.test(build.totals || '')
const unrun = (impl, build) => (impl.examples || []).filter(e => !(build?.examples || []).includes(e))

phase('Implement')
const implemented = await agent(IMPLEMENT, {
  label: `implement:${a.issue}`, phase: 'Implement', effort: a.effort, schema: IMPLEMENTED, ...model,
})

let review = null, pr = 0
const fixes = []
if (implemented?.branch && a.push !== false) {
  try {
    review = await workflow({ scriptPath: REVIEW }, reviewArgs(implemented, { head: implemented.head }))
  } catch (e) {
    log(`the review of ${implemented.branch} did not run: ${e.message}`)
  }
  let build = review?.build
  let head = build?.head || review?.hunt?.tip || implemented.head
  while (review && !passed(build) && fixes.length < FIXES) {
    phase('Fix')
    const fix = await agent(FIX({ totals: build?.totals, clean: build?.clean, notes: build?.notes }, head), {
      label: `fix:${a.issue}:${fixes.length + 1}`, phase: 'Fix', effort: a.effort, schema: FIXED, ...model,
    })
    fixes.push(fix)
    if (!fix?.caused) break
    head = fix.head
    const rerun = await workflow({ scriptPath: REVIEW }, reviewArgs(implemented, { head, hunt: false }))
    build = rerun?.build
    head = build?.head || head
  }
  const missing = unrun(implemented, build)
  if (passed(build) && !missing.length && a.gh !== false) {
    phase('Open')
    const opened = await agent(OPEN(implemented, head), {
      label: `open:${a.issue}`, phase: 'Open', agentType: 'lunatik-github', effort: 'low', schema: OPENED,
    })
    pr = opened?.pr || 0
  } else {
    const why = !passed(build) ? 'the host run did not pass' : missing.length ? `the host run left ${missing.join(', ')} unrun` : 'gh is absent'
    log(`no pull request for #${a.issue}: ${why}; the session reads the result`)
  }
} else {
  const why = !implemented ? 'the implementer died' : !implemented.branch ? 'the issue closes with no change' : 'the session pushes the branch'
  log(`no review for #${a.issue}: ${why}`)
}

const findings_left = [implemented, review].flatMap(r => r?.findings_left || [])
let filed = []
if (a.gh === false && findings_left.length)
  log('gh is absent: the session files what the agents left')
else if (findings_left.length) {
  phase('File')
  const filing = await agent(FILE(findings_left, pr || a.issue), {
    label: `file:${a.issue}`, phase: 'File', agentType: 'lunatik-github', effort: 'low', schema: FILED,
  })
  filed = filing?.filed || []
}
const unfiled = findings_left.filter((_, index) => !filed.some(f => f.index === index))
if (unfiled.length) {
  log(`${unfiled.length} of ${findings_left.length} left unfiled: ${unfiled.map(f => f.title).join('; ')}`)
}
const issues = [...new Set(filed.map(f => f.number))]
return { issue: a.issue, pr, implemented, review, fixes, findings_left, filed, issues, unfiled }

