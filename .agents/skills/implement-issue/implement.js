// An issue implemented and then reviewed as one workflow: an implementer that traces the issue,
// commits, runs the host and opens the pull request, then review.js over that pull request as a
// nested workflow, so there is one review workflow. What the implementer ran on the head it hands
// over goes to the review as validated, and the review builds and runs again only what a fixup
// changed or the implementer did not run.
//
// Usage: Workflow({scriptPath: '.agents/skills/implement-issue/implement.js', args: {...}})
//   issue       the issue to implement
//   effort      the reasoning effort of every agent here, and review.js's effort; required, since an
//               agent that names none runs at the session's default
//   scratch     an absolute directory for worktrees and the checkpoints
//   base        the branch the work starts from and the pull request targets, default master
//   branch      the branch the implementer creates, default one it names for the change
//   notes       what the launching session adds for the implementer, in its own words
//   focus       what the review is for, default notes
//   model       the model every agent runs on, default the session's
//   push        false where a push from an agent is refused on this machine: the implementer leaves
//               its commits on the branch and opens nothing, and no review runs
//   repo, sudo, gh   as review.js takes them, and passed to it; with gh false the agents write nothing to
//               GitHub, and the pull request and the filing are the session's
//
// Its last stage files findings_left, what either one leaves as an issue, and it returns the
// implementer's answer, the review's, the issues that now hold each entry, and any entry left unfiled.

export const meta = {
  name: 'implement-issue',
  description: 'Implement an issue, open its pull request, and review it with the review workflow',
  phases: [{ title: 'Implement' }, { title: 'File' }],
}

const a = args || {}
for (const key of ['issue', 'effort', 'scratch'])
  if (!a[key]) throw new Error(`implement-issue: args.${key} is required`)

const base = a.base || 'master'
const model = a.model ? { model: a.model } : {}
const checkpoint = `${a.scratch}/issue${a.issue}/IMPLEMENT.md`
const fileCheckpoint = `${a.scratch}/issue${a.issue}/FILED.md`
const REVIEW = '.agents/skills/review-pr/review.js'
// where gh is absent curl reads GitHub and writes nothing to it, since no guard reads a write through curl
const github = a.gh === false
  ? 'curl against https://api.github.com with `Authorization: Bearer $GH_TOKEN`, as the review-pr skill spells it, to read only'
  : '`gh api`, as the review-pr skill spells it'

const PUSH = a.push === false
  ? 'Push nothing: the session that launched this workflow pushes the branch.'
  : 'Push each commit as a command of its own, as you make it.'
const OPEN = a.push === false || a.gh === false
  ? `Open no pull request, and keep the branch for the session, which opens it; your answer's pr is 0.`
  : `Open the pull request against \`${base}\` with a body that passes tools/checks/pr-body.sh and carries
   \`Closes #${a.issue}\` on a line of its own, then remove your worktree.`

const IMPLEMENT = `
You implement issue #${a.issue} of Lunatik, in a worktree of your own under ${a.scratch}/ on
${a.branch ? `the branch \`${a.branch}\`` : 'a branch named for the change'}, started from \`origin/${base}\` as
fetched now. GitHub is read, and written where gh is present, through its REST API, ${github}.
${a.notes ? '\nFROM THE SESSION THAT LAUNCHED THIS: ' + a.notes + '\n' : ''}
CHECKPOINT: ${checkpoint} is your memory across a death (AGENTS.md, "Patches and commits", on work an
agent does for a workflow). If it exists, read it first and continue from it. Append a line per step as
you take it, what you read, decided, committed, ran and measured, and your answer before you return.

1. Read the issue and its comments, and the code and the kernel source they name; a cause is traced
   before it is written down (AGENTS.md rule 1). An issue whose stimulus is a script out of contract
   (AGENTS.md, "Deciding what to change") closes as not a defect, with no pull request.
2. Write the smallest shape that makes the defect unreachable, or meets the need, in the checkpoint
   before any other, and take a larger one only for what it buys (AGENTS.md, "Deciding what to change").
3. Commit as "Patches and commits" asks: one change per commit, the harness apart from the code, tests
   wired and described (the new-test skill), each doc where its reader looks.
   ${PUSH}
4. Run the host through tools/lunatik-host, as the lunatik-cycle skill orders it: build, install,
   reload, the whole suite, and every example tools/checks/examples-touched.sh names over the changed
   files, through tools/watchdog.sh. Read the core srcversion while it is loaded.
5. Run "Before opening a pull request" whole, with the pr-prep skill, and the checks under tools/checks
   over the changeset.
6. ${OPEN}

Your answer's validated is what passed on the head you return, with that head's full SHA: the review runs
again only what it does not carry, so a head that moved after the run, or a run that failed, leaves its
head empty for the review to build.
What you leave, a defect found on the way that is not this pull request's or a cell of the matrix no test
covers, goes in findings_left with a body that can be filed as it stands, its severity the label AGENTS.md
"Findings" names, and its home the open issue it belongs to, where one exists; nothing is left in prose alone.
`

const FILE = (entries, source) => `
You file what the implementation of issue #${a.issue} and its review left, as issues of luainkernel/lunatik,
through GitHub's REST API, ${github}. You post nothing on a pull request, no review and no comment.

CHECKPOINT: ${fileCheckpoint} records every entry already filed, one line each,
\`<index> | <title> | #<issue> | created\` or \`... | updated\`. Read it first and skip an entry whose index and
title it records, since an entry filed twice is a duplicate someone closes by hand; append the line the moment
the issue holds it.

For each entry:
- write its body to a file and run tools/checks/machine-leak.sh and tools/checks/untraced.sh over it; a line
  either one names is rewritten before anything is posted;
- an entry whose home is an open issue goes to that issue: its body is appended to the issue's own under a
  line \`Update: <title> (#${source})\`, and the issue carries one severity label, the higher of its own and
  the entry's;
- an entry that reports what an open issue already reports, read in that issue and not guessed from its
  title, goes to it the same way;
- any other entry opens an issue with its title, its body as it stands and the label
  \`severity: <its severity>\`.

Your answer names, for every entry by its index, the issue that now holds it.

ENTRIES:
${JSON.stringify(entries.map((entry, index) => ({ index, ...entry })), null, 2)}
`

const LEFT = { type: 'array', items: { type: 'object', properties: {
  title: { type: 'string' }, body: { type: 'string' }, severity: { type: 'string', enum: ['high', 'medium', 'low'] },
  home: { type: 'integer', description: 'the open issue this finding belongs to' },
}, required: ['title', 'body', 'severity'] } }

const IMPLEMENTED = {
  type: 'object',
  properties: {
    pr: { type: 'integer', description: 'the pull request opened, 0 when none was' },
    branch: { type: 'string' },
    head: { type: 'string', description: 'the full SHA of the branch tip' },
    base: { type: 'string', description: 'the full SHA of the base the branch sits on, after any rebase' },
    commits: { type: 'array', items: { type: 'string' } },
    examples: { type: 'array', items: { type: 'string' }, description: 'what examples-touched.sh lists' },
    validated: { type: 'object', properties: {
      head: { type: 'string', description: 'the full SHA the suite passed and the examples ran on, or empty' },
      suite: { type: 'string', description: 'the totals, "pass:N fail:0 skip:0"' },
      core: { type: 'string', description: 'the core srcversion while loaded' },
      examples: { type: 'array', items: { type: 'string' } },
    }, required: ['head', 'suite', 'core', 'examples'] },
    findings_left: LEFT,
    notes: { type: 'string' },
  },
  required: ['pr', 'branch', 'head', 'base', 'commits', 'examples', 'validated', 'findings_left', 'notes'],
}

const FILED = { type: 'object', properties: {
  filed: { type: 'array', items: { type: 'object', properties: {
    index: { type: 'integer' }, number: { type: 'integer' }, action: { type: 'string', enum: ['created', 'updated'] },
  }, required: ['index', 'number', 'action'] } },
}, required: ['filed'] }

phase('Implement')
const implemented = await agent(IMPLEMENT, {
  label: `implement:${a.issue}`, phase: 'Implement', effort: a.effort, schema: IMPLEMENTED, ...model,
})

let review = null
if (implemented?.pr) {
  const ran = implemented.validated.head
  const validated = ran && ran === implemented.head ? implemented.validated : null
  if (!validated) {
    log(`the implementer's run passed on ${ran || 'no head'}, not ${implemented.head}: the review builds`)
  }
  try {
    review = await workflow({ scriptPath: REVIEW }, {
      pr: implemented.pr, branch: implemented.branch, head: implemented.head, base: implemented.base,
      scratch: a.scratch, validated, examples: implemented.examples, focus: a.focus || a.notes,
      effort: a.effort, model: a.model, push: a.push, repo: a.repo, sudo: a.sudo, gh: a.gh,
    })
  } catch (e) {
    log(`the review of #${implemented.pr} did not run: ${e.message}`)
  }
} else {
  const why = implemented ? 'the session pushes the branch and opens it' : 'the implementer died'
  log(`no pull request for #${a.issue}: ${why}`)
}

const findings_left = [implemented, review].flatMap(r => r?.findings_left || [])
let filed = []
if (a.gh === false && findings_left.length)
  log('gh is absent: the session files what the agents left')
else if (findings_left.length) {
  phase('File')
  const filing = await agent(FILE(findings_left, implemented?.pr || a.issue), {
    label: `file:${a.issue}`, phase: 'File', effort: a.effort, schema: FILED, ...model,
  })
  filed = filing?.filed || []
}
const unfiled = findings_left.filter((_, index) => !filed.some(f => f.index === index))
if (unfiled.length) {
  log(`${unfiled.length} of ${findings_left.length} left unfiled: ${unfiled.map(f => f.title).join('; ')}`)
}
const issues = [...new Set(filed.map(f => f.number))]
return { issue: a.issue, implemented, review, findings_left, filed, issues, unfiled }

