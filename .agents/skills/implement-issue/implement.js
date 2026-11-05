/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

// An issue implemented, reviewed, run once on the host and opened as a pull request, as one workflow:
// an implementer that traces the issue and commits what builds, review.js over the branch as a nested
// workflow, whose build phase is the one run of the suite, the examples the change touches and the
// defect each new test is for, a fix of what that run fails, and the opening of the pull request on
// the head that passed. The host runs in an agent of its own, so the implementer's context never
// waits on a suite. A groomer, when the launch names one, judges the issue's merit and approach first:
// it settles the API in the issue and lets the implementer start, or stops the run with the shape it
// would take instead or the reason to take none.
//
// Usage: Workflow({scriptPath: '.agents/skills/implement-issue/implement.js', args: {...}})
//   issue       the issue to implement
//   effort      the reasoning effort of every agent agents does not name, the GitHub's and the host's
//               aside; required, since an agent that names none runs at the session's default
//   scratch     an absolute directory for worktrees and the checkpoints
//   base        the branch the work starts from and the pull request targets, default master
//   branch      the branch the implementer creates, default one it names for the change
//   notes       what the launching session adds for the implementer, in its own words
//   focus       what the review is for, default notes
//   model       the model of every agent agents does not name, the GitHub's and the host's aside,
//               default the session's
//   agents      {model, effort} per agent, under groom, implement, fix, review, build and github, over
//               model and effort; fix defaults to implement's, and build and github to their agents'
//               definitions, sonnet. groom runs a groomer before the implementer, only when named
//   push        false where a push from an agent is refused on this machine: the implementer leaves
//               its commits on the branch, and no review runs
//   repo        the checkout's absolute path, where review.js is read and its phases work; required, since
//               a relative path resolves against the session's directory when the review starts
//   machine     how this machine gets root and authenticates gh, for the agents that load no
//               CLAUDE.local.md, the host's and GitHub's; the launching session copies it from there
//   gh          false where gh is absent: the agents write nothing to GitHub, and the pull request and
//               the filing are the session's
//   build       what the host runs in place of the suite and the examples, review.js's own argument:
//               a change whose done criteria are a run of its own tool spells that run here
//
// It returns the implementer's answer, the review's, the last host run's build, the pull request, the
// writes the session posts to GitHub in order, the labels, the groomer's Update and each entry of
// findings_left the filing prepared, and any entry left unfiled.
// findings_left holds what the implementer, the review, each fix and each build run again after one left.

export const meta = {
  name: 'implement-issue',
  description: 'Implement an issue, review it, run it once on the host, and open its pull request',
  phases: [{ title: 'Groom' }, { title: 'Implement' }, { title: 'Fix' }, { title: 'Open' }, { title: 'File' }],
}

const a = args || {}
for (const key of ['issue', 'effort', 'scratch', 'repo'])
  if (!a[key]) throw new Error(`implement-issue: args.${key} is required`)

const base = a.base || 'master'
// an agent's model and effort: its own under agents, else the fallback, else its definition's
const role = (name, fallback = { model: a.model, effort: a.effort }) => {
  const own = { ...fallback, ...((a.agents || {})[name] || {}) }
  return { ...(own.model ? { model: own.model } : {}), ...(own.effort ? { effort: own.effort } : {}) }
}
const implementer = role('implement')
const fixer = role('fix', implementer)
const reviewer = role('review')
const githubber = role('github', { effort: 'low' })
const groomCheckpoint = `${a.scratch}/issue${a.issue}/GROOM.md`
const checkpoint = `${a.scratch}/issue${a.issue}/IMPLEMENT.md`
const bodyFile = `${a.scratch}/issue${a.issue}/pull-request.md`
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
const DRAFT = base === 'master' ? '' : ' It opens as a draft (`-F draft=true`), which GitHub will not merge before its base.'

const GROOM = `
You groom issue #${a.issue} of Lunatik before anyone implements it, in a worktree of your own under ${a.scratch}/
at \`origin/${base}\` as fetched now, removed when you are done. GitHub is read through its REST API,
${github}, and you write nothing to it.
${a.notes ? '\nFROM THE SESSION THAT LAUNCHED THIS: ' + a.notes + '\n' : ''}
CHECKPOINT: ${groomCheckpoint} is your memory across a death. If it exists, read it first and continue from
it. Append a line per step as you take it, and your answer before you return.

An issue is a request, not a decision to implement it. Judge it before you shape it:
1. Its merit: whether the need is real and general or one consumer's, whether its contract holds against the
   binding's documentation and the honest-mistake bullet of AGENTS.md, "Deciding what to change", and what
   leaving it undone costs.
2. Its approach: the smallest shape that meets the need, written first, beside the one the issue proposes and
   the alternatives, each with what it buys and what it costs, the comparison starting in the kernel's own
   answer, resource by resource for an object kept past the code that lent it (AGENTS.md, "Deciding what to
   change"). Read what the issue asks to be researched, in the kernel
   source and on the web, and name what you read.
3. Your verdict. implement settles, as text the issue takes under an Update: line, the API, the contract and
   whatever format the issue leaves open, and leaves helpers and loops to the implementer (AGENTS.md, on what
   an issue states). reshape is a shape other than the issue's, which the maintainer decides on; decline is
   the reason to build nothing. Either stops the run.
`

const GROOMING = (groomed) => `
THE GROOMER judged the issue worth implementing and settled its API, which the session appends to the issue
under an Update: line once this run returns, so it stands here: ${JSON.stringify(groomed.update)}. Its
reading of the shapes, for your step 2, and what it read:
${JSON.stringify({ shapes: groomed.shapes, sources: groomed.sources }, null, 2)}
`

const LEAVE = `goes in findings_left with a body that can be filed as it stands, its severity the label
.agents/skills/review-pr/process.md "Findings" names, read against the contract the entry quotes, and its
home the open issue it belongs to, where one exists; nothing is left in prose alone.`

const IMPLEMENT = `
You implement issue #${a.issue} of Lunatik, in a worktree of your own under ${a.scratch}/ on
${a.branch ? `the branch \`${a.branch}\`` : 'a branch named for the change'}, started from \`origin/${base}\` as
fetched now. GitHub is read through its REST API, ${github}.
${a.notes ? '\nFROM THE SESSION THAT LAUNCHED THIS: ' + a.notes + '\n' : ''}
CHECKPOINT: ${checkpoint} is your memory across a death (AGENTS.md, "Patches and commits", on work an
agent does for a workflow). If it exists, read it first and continue from it. Append a line per step as
you take it, what you read, decided, committed and measured, and your answer before you return.

1. Read the issue and its comments, and the code and the kernel source they name; a cause is traced
   before it is written down (AGENTS.md rule 1). An object the change keeps past the code that lent it is
   read against each of the kernel's keepers of such an object, resource by resource
   (AGENTS.md, "Deciding what to change"). An issue whose stimulus is a script out of contract
   (AGENTS.md, "Deciding what to change") closes as not a defect, with no pull request.
2. Write the smallest shape that makes the defect unreachable, or meets the need, in the checkpoint
   before any other, and take a larger one, a helper or a loop the issue prescribes included, which is a
   shape to weigh and not the spec, only where AGENTS.md, "Deciding what to change", keeps one. Your
   answer's smallest carries that shape beside the diff, and names what each mechanism past it buys with
   its source; the review keeps none without one.
3. Commit as "Patches and commits" asks: one change per commit, the harness apart from the code, tests
   wired and described (the new-test skill), each doc where its reader looks. \`make\` is clean on every
   commit, and \`make C=1\` where the change touches an annotated pointer. ${PUSH}
4. For each test under tests/ the change adds or changes, write the defect it is for, the mechanism it
   covers disabled (.agents/rules/tests.md), as a patch over the head: edit the tree, see that \`make\`
   builds it, \`git diff > ${a.scratch}/issue${a.issue}/defect<n>.patch\`, then \`git apply -R\` of that patch.
   A defect that removes a crash guard is not written, since its test rests on the message it asserts.
   Your answer's defects names each patch, the suite that runs the test and the cases it should fail:
   the build plants each after one reload and runs that whole suite, never the test alone.
5. Run "Before opening a pull request" with the pr-prep skill, except what needs the host: the suite and
   the examples run once, after the review, in an agent of their own, and a failure comes back to a fix.
   Run no install, reload, suite or example yourself. List the examples tools/checks/examples-touched.sh
   names over the changed files.
6. Draft the pull request's title and body as pr-prep says, into your answer; tools/checks/pr-body.sh
   passes the body, which carries \`Closes #${a.issue}\` on a line of its own and names each example as run:
   the pull request opens only on a head the host run passed, and says of an example the host only loaded
   what the build said of it. Open nothing.
7. Remove your worktree (\`rm -rf <tree> && git worktree prune\`) once the branch is pushed: the review, the host
   run and a fix each work in one of their own.

What you leave, a defect found on the way that is not this change's or a cell of the matrix no test covers,
${LEAVE}
`

const FIX = (failed, head) => `
You fix what the host run of issue #${a.issue}'s branch failed, on \`${head}\`. Read ${checkpoint} first: the
implementer's memory of the change. The run reported:
${JSON.stringify(failed, null, 2)}

Trace the failure before you change anything (AGENTS.md rule 1): the test's prints, the errno, the journal
window the lunatik-cycle skill names. A failure the change causes is fixed in the commit that introduced it,
\`git commit --fixup\` folded at once with \`git rebase -i --autosquash ${implemented.base}\`, since the pull
request opens squashed, \`make\` clean, and pushed with \`--force-with-lease\`; one it does not cause, a host process or a test already
failing on master, is said as such with its evidence and the open issue that reports it, and fixes nothing. Run no install, reload, suite or
example: the host run that follows is another agent's. Append what you traced and committed to the checkpoint,
and remove the worktree you worked in once the fix is pushed.${(implemented.defects || []).length ? `

The host run plants each defect below over your pushed head, and a fix over a line one carries leaves it unable
to apply, so before you remove the worktree run \`git apply --check <patch>\` of each over that head; one that no
longer applies you write again at the same path, carrying the defect the old patch carries: edit the tree, see
that \`make\` builds it, \`git diff > <patch>\`, then \`git apply -R <patch>\`, each a call of its own. Note each
one written again in the checkpoint.
${JSON.stringify(implemented.defects, null, 2)}` : ''}

What you find past the failure and do not fix, in the change or beside it,
${LEAVE}
`

const OPEN = (impl, head, unrelated, body, loaded, skipped) => `
${MACHINE}Open a pull request on luainkernel/lunatik from the branch \`${impl.branch}\` against \`${base}\`, whose head is
\`${head}\`; push the branch first if GitHub's tip of it is not that SHA.${DRAFT} Title: ${JSON.stringify(impl.title)}
A pull request GitHub already has for the branch is that one, read with
\`gh api "repos/luainkernel/lunatik/pulls?head=luainkernel:${impl.branch}&state=open"\`, and is not opened twice.

Body, as it stands${unrelated.length ? `, with one sentence added to its last paragraph naming the failure a host
run showed and the change does not cause, and the issue that reports it, from this record:
${JSON.stringify(unrelated)}` : ''}${loaded.length ? `, and with its sentence on the examples saying of each
example of this record that the host only loaded it, or could not run it, and why, in the record's words:
${JSON.stringify(loaded)}` : ''}${skipped && (impl.examples || []).length ? `, and with its sentence on the examples
saying that the host ran none of them, since tools/checks/functional.sh names no file of the change it reads` : ''}:
${JSON.stringify(body)}

Write the body with your Write tool to exactly ${bodyFile}, run tools/checks/pr-body.sh over it, and pass that
path spelled out in the command that opens the pull request (\`-F body=@${bodyFile}\`): the guards before a shell
call read the file the command names, and refuse a path a shell variable holds. Label nothing: the session
labels it, with the label \`bash tools/complexity.sh <number>\` prints, which your answer carries as
complexity. Your answer is the pull request's number; a write refused goes in notes, word for word.
`

const FILE = (entries, source, findings, fixes) => `
${MACHINE}Prepare what the implementation of issue #${a.issue} and its review left, as issues of luainkernel/lunatik,
for the session to post: you write nothing to GitHub, since the auto mode classifier refuses a workflow agent's
write, and read it through \`gh api\` alone. No entry goes to a pull request: the issues endpoint answers for a
pull request too, and \`gh api repos/luainkernel/lunatik/issues/<n>\` carries a \`pull_request\` field when <n> is one.

An entry was written before the run went on, so what the branch did since is read before it is filed. An
entry a finding of the review below fixed with a commit, or a fix below traced and committed, is skipped, and
one the branch fixes in part is cut to the part it leaves. A failure a fix read as not caused by the change and
fixed by an open pull request is skipped too. A skipped entry is held by that pull request, or by #${source}.

Entries that report one defect, the implementer's and the review's or those of builds that fail on it again,
are one: prepare the fullest once and name every index it stands for. For each other entry:
- write its text with your Write tool to exactly ${a.scratch}/issue${a.issue}/entry<index>.md and run
  tools/checks/machine-leak.sh and tools/checks/untraced.sh over it; a line either one names is rewritten;
- an entry whose body carries \`Decision:\` or \`Decision D<n>:\`, or whose home is an epic (a title that starts with \`Epic:\`),
  opens an issue of its own, whatever it reports, and its body ends with \`Part of #<home>.\` when it has a
  home;
- no entry goes to #${a.issue}, which the pull request of this change closes, whoever opens it, and what is
  appended to it closes unread with it: one that belongs there opens an issue of its own, whose body ends with
  \`Found while implementing #${a.issue}.\`;
- an entry whose home is an open issue is appended to that issue: its file holds the text the session adds
  after the issue's body and a blank line, opening with a line \`Update: <title> (#${source})\`, with that
  number as it stands, and the issue keeps one severity label, the higher of its own and the entry's;
- an entry that reports what an open issue already reports, read in that issue and not guessed from its
  title, goes to it the same way;
- any other entry opens an issue with its title, its file as the body and the label \`severity: <its severity>\`;
- the text carries the entry's contract on a line of its own, \`Contract: <contract>\`, the promise its
  severity was read against.

Your answer is writes, one for each prepared entry and each skipped one, every index of ENTRIES in exactly one:
create with the title, the file and the severity, append with the issue, the file and the severity, or skip
with the issue or the pull request that holds it.

THE REVIEW'S FINDINGS, each with its disposition:
${JSON.stringify(findings, null, 2)}

THE FIXES of the host run, each with whether the change caused what it traced:
${JSON.stringify(fixes, null, 2)}

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
    source: { type: 'string', description: 'the defect the smallest shape leaves reachable, with its trace, or the need the issue or the maintainer stated, quoted with where; empty when it has neither' },
  }, required: ['mechanism', 'buys', 'source'] } },
}, required: ['shape', 'lines', 'diff', 'beyond'] }

const DEFECTS = { type: 'array', items: { type: 'object', properties: {
  patch: { type: 'string', description: 'the absolute path of the patch that plants the defect' },
  suite: { type: 'string', description: 'the suite `lunatik test` runs the test in' },
  fails: { type: 'array', items: { type: 'string' }, description: 'the cases the defect should fail, as the test prints them' },
}, required: ['patch', 'suite', 'fails'] } }

const IMPLEMENTED = {
  type: 'object',
  properties: {
    branch: { type: 'string', description: 'the branch, or empty when the issue closes with no change' },
    head: { type: 'string', description: 'the full SHA of the branch tip' },
    base: { type: 'string', description: 'the full SHA of the base the branch sits on, after any rebase' },
    commits: { type: 'array', items: { type: 'string' } },
    examples: { type: 'array', items: { type: 'string' }, description: 'what examples-touched.sh lists' },
    defects: DEFECTS,
    title: { type: 'string' },
    body: { type: 'string', description: 'the pull request body, which pr-body.sh passes' },
    smallest: SMALLEST,
    findings_left: LEFT,
    notes: { type: 'string' },
  },
  required: ['branch', 'head', 'base', 'commits', 'examples', 'defects', 'title', 'body', 'smallest', 'findings_left', 'notes'],
}

const FIXED = { type: 'object', properties: {
  head: { type: 'string', description: 'the full SHA of the branch tip after the fix' },
  caused: { type: 'boolean', description: 'false when the failure is not the change\'s' },
  findings_left: LEFT,
  notes: { type: 'string' },
}, required: ['head', 'caused', 'findings_left', 'notes'] }

const OPENED = { type: 'object', properties: {
  pr: { type: 'integer' }, complexity: { type: 'string', enum: ['complexity: small', 'complexity: medium', 'complexity: large'] },
  notes: { type: 'string' },
}, required: ['pr'] }

const GROOMED = { type: 'object', properties: {
  verdict: { type: 'string', enum: ['implement', 'reshape', 'decline'] },
  merit: { type: 'string', description: 'whether the need is real, general and in contract, and what leaving it undone costs' },
  shapes: { type: 'array', items: { type: 'object', properties: {
    shape: { type: 'string' }, buys: { type: 'string' }, costs: { type: 'string' },
  }, required: ['shape', 'buys', 'costs'] }, description: 'the smallest first, then the issue\'s and the alternatives' },
  update: { type: 'string', description: 'for implement, the text the issue takes under its Update: line; empty otherwise' },
  sources: { type: 'array', items: { type: 'string' }, description: 'what was read, as file:line or URL' },
  notes: { type: 'string' },
}, required: ['verdict', 'merit', 'shapes', 'update', 'sources', 'notes'] }

const PREPARED = { type: 'object', properties: {
  writes: { type: 'array', items: { type: 'object', properties: {
    action: { type: 'string', enum: ['create', 'append', 'skip'] },
    indexes: { type: 'array', items: { type: 'integer' } },
    issue: { type: 'integer', description: 'append: the issue the text goes to; skip: the issue or pull request that holds the entry' },
    title: { type: 'string' }, file: { type: 'string' }, severity: { type: 'string', enum: ['low', 'medium', 'high'] },
  }, required: ['action', 'indexes'] } },
  notes: { type: 'string' },
}, required: ['writes'] }

const reviewArgs = (impl, extra) => ({
  pr: 0, branch: impl.branch, base: impl.base, scratch: a.scratch, validated: null, examples: impl.examples, defects: impl.defects,
  focus: a.focus || a.notes, smallest: impl.smallest, body: impl.body, effort: reviewer.effort, model: reviewer.model, push: a.push,
  agents: { build: (a.agents || {}).build }, build: a.build, repo: a.repo, machine: a.machine, gh: a.gh, ...extra,
})
const passed = (build) => build && build.clean && (build.skipped || /fail:0\b/.test(build.totals || ''))
// an example the host only loaded, or a skipped build ran none of, is accounted for, and the body says so
const unrun = (impl, build) => build?.skipped ? [] : (impl.examples || []).filter(e =>
  ![...(build?.examples || []), ...(build?.loaded || []).map(l => l.example)].includes(e))

let groomed = null
if ((a.agents || {}).groom) {
  phase('Groom')
  groomed = await agent(GROOM, { label: `groom:${a.issue}`, phase: 'Groom', schema: GROOMED, ...role('groom') })
  if (groomed?.verdict !== 'implement') {
    log(`#${a.issue} ${groomed ? `groomed: ${groomed.verdict}` : 'not groomed: the groomer died'}; the session reads the result`)
    return { issue: a.issue, groomed, pr: 0 }
  }
}

phase('Implement')
const implemented = await agent(IMPLEMENT + (groomed ? GROOMING(groomed) : ''), {
  label: `implement:${a.issue}`, phase: 'Implement', schema: IMPLEMENTED, ...implementer,
})

let review = null, build = null, pr = 0, complexity = null
const fixes = [], reruns = []
if (implemented?.branch && a.push !== false) {
  try {
    review = await workflow({ scriptPath: REVIEW }, reviewArgs(implemented, { head: implemented.head }))
  } catch (e) {
    log(`the review of ${implemented.branch} did not run: ${e.message}`)
  }
  build = review?.build
  let head = build?.head || review?.reviewer?.tip || implemented.head
  while (review && !passed(build) && fixes.length < FIXES) {
    phase('Fix')
    const fix = await agent(FIX({ totals: build?.totals, clean: build?.clean, notes: build?.notes }, head), {
      label: `fix:${a.issue}:${fixes.length + 1}`, phase: 'Fix', schema: FIXED, ...fixer,
    })
    fixes.push(fix)
    if (!fix) break
    // a failure the change does not cause, a test that fails on a busy host among them, is read once more
    head = fix.head || head
    const rerun = await workflow({ scriptPath: REVIEW }, reviewArgs(implemented, { head, reviewer: false }))
    reruns.push(rerun)
    build = rerun?.build
    head = build?.head || head
  }
  const missing = unrun(implemented, build)
  const unsourced = review?.unsourced || []
  if (passed(build) && !missing.length && !unsourced.length && a.gh !== false) {
    phase('Open')
    const unrelated = fixes.filter(f => f && !f.caused).map(f => f.notes)
    const body = review?.reviewer?.body || implemented.body
    const opened = await agent(OPEN(implemented, head, unrelated, body, build?.loaded || [], build?.skipped), {
      label: `open:${a.issue}`, phase: 'Open', agentType: 'lunatik-github', schema: OPENED, ...githubber,
    })
    pr = opened?.pr || 0
    complexity = opened?.complexity || null
  } else {
    const why = !passed(build) ? 'the host run did not pass' : missing.length ? `the host run left ${missing.join(', ')} unrun`
      : unsourced.length ? `the review kept ${unsourced.map(b => b.mechanism).join('; ')} without a source` : 'gh is absent'
    log(`no pull request for #${a.issue}: ${why}; the session reads the result`)
  }
} else {
  const why = !implemented ? 'the implementer died' : !implemented.branch ? 'the issue closes with no change' : 'the session pushes the branch'
  log(`no review for #${a.issue}: ${why}`)
}

const findings_left = [implemented, review, ...reruns, ...fixes].flatMap(r => r?.findings_left || [])
let filing = null
if (a.gh === false && findings_left.length)
  log('gh is absent: the session files what the agents left')
else if (findings_left.length) {
  phase('File')
  filing = await agent(FILE(findings_left, pr || a.issue, review?.reviewer?.findings || [], fixes), {
    label: `file:${a.issue}`, phase: 'File', agentType: 'lunatik-github', schema: PREPARED, ...githubber,
  })
}
// the pull request closes the issue, and an entry appended to it closes unread with it
const closes = w => w.action === 'append' && w.issue === a.issue
const prepared = (filing?.writes || []).filter(w => !closes(w))
const unfiled = findings_left.filter((_, index) => !prepared.some(w => w.indexes.includes(index)))
if (unfiled.length)
  log(`${unfiled.length} of ${findings_left.length} left unfiled: ${unfiled.map(f => f.title).join('; ')}${filing?.notes ? `; ${filing.notes}` : ''}`)
// a workflow agent's write to GitHub is refused by the auto mode classifier, and the session's is not
const writes = [
  ...(pr ? [{ action: 'label', issue: pr, label: 'workflow-reviewed' }] : []),
  ...(pr && complexity ? [{ action: 'label', issue: pr, label: complexity }] : []),
  ...(groomed?.update ? [{ action: 'append', issue: a.issue, text: /^Update:/.test(groomed.update) ? groomed.update : `Update: ${groomed.update}` }] : []),
  ...prepared.filter(w => w.action !== 'skip'),
]
return { issue: a.issue, groomed, pr, implemented, review, build, fixes, findings_left, writes, prepared, unfiled }

