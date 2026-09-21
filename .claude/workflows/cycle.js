export const meta = {
  name: 'cycle',
  description: 'Build → review → adversarially verify → repair, per feature slice, ending ready-to-commit',
  whenToUse: 'Invoked by /cycle. The gate stays a SEPARATE run (workflow `gate-run`) — a limit hit must cost one stage, not the phase.',
  phases: [
    { title: 'Build', detail: 'one lane per slice, disjoint directories, tests-first' },
    { title: 'Review', detail: 'read-only reviewer per slice, spec sections that own it' },
    { title: 'Verify', detail: 'adversarial refutation — findings must survive to reach the owner' },
    { title: 'Repair', detail: 'confirmed findings go back to the lane that owns the directory' },
  ],
}

// args: {
//   milestone: 'M12',
//   slices: [{ key, agent, dirs: [...], prompt, risk?: 'high'|'normal', skipBuild?: bool }],
//   maxRepairRounds?: 2,
// }
// Reports land in .claude/lane-reports/<milestone>-<key>.json (build) and
// .claude/lane-reports/<milestone>-<key>.review.json (review), written by the agents
// themselves, so a session-limit kill loses the run but never the work.

const HIGH_RISK = [
  'packages/core_crypto', 'packages/core_ledger', 'packages/sync_engine',
  'server/supabase/migrations', 'server/supabase/functions',
]

const LANE_SCHEMA = {
  type: 'object',
  properties: {
    complete: { type: 'boolean', description: 'true only if the whole task is finished' },
    files: { type: 'array', items: { type: 'string' } },
    tests: { type: 'array', items: { type: 'string' }, description: 'test ids added or made green' },
    open: { type: 'array', items: { type: 'string' }, description: '⚠️ SPEC / 🔒 / owner items' },
    notes: { type: 'string' },
  },
  required: ['complete', 'files', 'tests', 'open'],
}

const FINDINGS_SCHEMA = {
  type: 'object',
  properties: {
    complete: { type: 'boolean' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          file: { type: 'string' },
          line: { type: 'number' },
          severity: { type: 'string', description: 'blocker | major | minor' },
          category: { type: 'string', description: 'test-honesty | spec | security | lock-trace | invariant' },
          claim: { type: 'string', description: 'one sentence: what is wrong' },
          evidence: { type: 'string', description: 'file:line, doc section, or golden row that shows it' },
          owning_dirs: { type: 'array', items: { type: 'string' } },
          why_it_matters: { type: 'string' },
        },
        required: ['file', 'severity', 'category', 'claim', 'evidence'],
      },
    },
    notes: { type: 'string' },
  },
  required: ['complete', 'findings'],
}

const VERDICT_SCHEMA = {
  type: 'object',
  properties: {
    refuted: { type: 'boolean', description: 'true = the finding does NOT hold' },
    reason: { type: 'string', description: 'the evidence that settles it, with file:line or doc section' },
  },
  required: ['refuted', 'reason'],
}

const LENSES = [
  'correctness — read the actual code path and say whether the claim holds as stated',
  'context — is this already handled elsewhere (a caller, a guard, a deterministic checker, an existing test)?',
  'authority — does the spec section cited actually say this, and does a newer ADR override it?',
]

if (!args || !Array.isArray(args.slices) || args.slices.length === 0) {
  throw new Error('args.slices must be a non-empty array of { key, agent, dirs, prompt }')
}
const MAX = 3
if (args.slices.length > MAX) {
  throw new Error(
    `${args.slices.length} slices requested; the cap is ${MAX} per cycle. ` +
      `Split into separate cycles — one cycle is about one day at the pacing ceiling.`,
  )
}
const bad = args.slices.filter((s) => !s.key || !s.agent || !s.dirs?.length || !s.prompt)
if (bad.length) throw new Error(`slice(s) missing key/agent/dirs/prompt: ${JSON.stringify(bad.map((s) => s.key ?? '?'))}`)

// disjointness is enforced by the prompt alone (edits are auto-accepted) — check it here too
const seen = new Map()
for (const s of args.slices) {
  for (const d of s.dirs) {
    if (seen.has(d)) throw new Error(`directory "${d}" claimed by both ${seen.get(d)} and ${s.key} — slices must be disjoint`)
    seen.set(d, s.key)
  }
}

const M = args.milestone || 'M?'
const ROUNDS = args.maxRepairRounds ?? 2
const isHigh = (s) => s.risk === 'high' || s.dirs.some((d) => HIGH_RISK.some((h) => d.startsWith(h)))

log(`${M}: ${args.slices.length} slice(s) — ${args.slices.map((s) => `${s.key}${isHigh(s) ? '*' : ''}`).join(' ')}  (* = 3-vote verify)`)

const reviewPrompt = (s) => `Review the slice **${s.key}** of milestone ${M}.

Directories it owns: ${s.dirs.join(', ')}
What it was asked to build:
${s.prompt}

Read the current state of those directories and the spec sections that own them. Report findings
per your agent instructions — test-honesty first. Write
\`.claude/lane-reports/${M}-${s.key}.review.json\` as you go.
You have no Edit tool. Do not propose patches; state the defect and its evidence.`

const verifyPrompt = (f, lens) => `A reviewer filed this finding. Your job is to REFUTE it.

  file:     ${f.file}${f.line ? ':' + f.line : ''}
  severity: ${f.severity}   category: ${f.category}
  claim:    ${f.claim}
  evidence: ${f.evidence}

Lens for this pass — ${lens}

Read the real code and the real spec section. Default to refuted:true if you are uncertain or
cannot source the claim: a finding that reaches the owner must be one that survived an attempt to
kill it. Refute it if the claim misreads the code, if the behaviour is already handled elsewhere,
if a deterministic checker already owns it, or if the cited authority does not say what is claimed.`

const built = await pipeline(
  args.slices,

  // ---- Build -------------------------------------------------------------
  (s) =>
    s.skipBuild
      ? Promise.resolve({ complete: true, files: [], tests: [], open: [], notes: 'build skipped' })
      : agent(
          `${s.prompt}\n\nYou own ONLY: ${s.dirs.join(', ')}. Touch nothing outside them.\n` +
            `Write .claude/lane-reports/${M}-${s.key}.json as you go (key "${s.key}").`,
          { label: `build:${s.key}`, phase: 'Build', agentType: s.agent, schema: LANE_SCHEMA },
        ),

  // ---- Review ------------------------------------------------------------
  (build, s) =>
    agent(reviewPrompt(s), {
      label: `review:${s.key}`,
      phase: 'Review',
      agentType: 'lane-review',
      schema: FINDINGS_SCHEMA,
    }).then((r) => ({ slice: s, build, review: r })),

  // ---- Verify ------------------------------------------------------------
  async (r) => {
    const findings = r.review?.findings || []
    if (!findings.length) return { ...r, confirmed: [], killed: 0 }
    const votes = isHigh(r.slice) ? LENSES : LENSES.slice(0, 1)
    const judged = await parallel(
      findings.map((f) => () =>
        parallel(
          votes.map((lens, i) => () =>
            agent(verifyPrompt(f, lens), {
              label: `verify:${r.slice.key}:${(f.file || '?').split('/').pop()}:${i}`,
              phase: 'Verify',
              schema: VERDICT_SCHEMA,
              effort: isHigh(r.slice) ? 'high' : 'medium',
            }),
          ),
        ).then((vs) => {
          const v = vs.filter(Boolean)
          // survives only on a majority of NON-refutations; no votes returned = dropped
          const alive = v.filter((x) => !x.refuted).length
          return { finding: f, survives: v.length > 0 && alive * 2 > v.length, votes: v }
        }),
      ),
    )
    const ok = judged.filter(Boolean)
    const confirmed = ok.filter((j) => j.survives).map((j) => j.finding)
    log(`${r.slice.key}: ${findings.length} finding(s) → ${confirmed.length} confirmed, ${ok.length - confirmed.length} refuted`)
    return { ...r, confirmed, killed: ok.length - confirmed.length }
  },
)

const results = built.filter(Boolean)

// ---- Repair (bounded) ------------------------------------------------------
let round = 0
let outstanding = results.filter((r) => r.confirmed.length)
const repairLog = []

while (outstanding.length && round < ROUNDS) {
  round += 1
  phase('Repair')
  log(`repair round ${round}/${ROUNDS} — ${outstanding.reduce((n, r) => n + r.confirmed.length, 0)} confirmed finding(s) across ${outstanding.length} slice(s)`)
  const repaired = await parallel(
    outstanding.map((r) => () =>
      agent(
        `Repair confirmed review findings in slice **${r.slice.key}** (${M}).\n` +
          `You own ONLY: ${r.slice.dirs.join(', ')}.\n\n` +
          r.confirmed
            .map((f, i) => `${i + 1}. [${f.severity}/${f.category}] ${f.file}${f.line ? ':' + f.line : ''}\n   ${f.claim}\n   evidence: ${f.evidence}`)
            .join('\n\n') +
          `\n\nEach finding survived an adversarial refutation pass, so treat it as real. If one is ` +
          `nonetheless wrong, do NOT patch around it — say so in "open" with your evidence and leave ` +
          `the code alone; it becomes an owner item rather than a third round.\n` +
          `Update .claude/lane-reports/${M}-${r.slice.key}.json.`,
        { label: `repair:${r.slice.key}:r${round}`, phase: 'Repair', agentType: r.slice.agent, schema: LANE_SCHEMA },
      ).then((fix) => ({ slice: r.slice, fix, addressed: r.confirmed })),
    ),
  )
  const done = repaired.filter(Boolean)
  repairLog.push({ round, slices: done.map((d) => d.slice.key) })
  // a slice whose repair lane reported unresolved items stays outstanding
  outstanding = done
    .filter((d) => (d.fix?.open || []).length && d.fix?.complete !== true)
    .map((d) => ({ slice: d.slice, confirmed: d.addressed }))
}

const toOwner = []
for (const r of results) for (const f of r.confirmed) if (outstanding.some((o) => o.slice.key === r.slice.key)) toOwner.push({ slice: r.slice.key, ...f })
for (const r of results) for (const o of r.build?.open || []) toOwner.push({ slice: r.slice.key, owner_item: o })

return {
  milestone: M,
  slices: results.map((r) => ({
    key: r.slice.key,
    built: r.build?.complete === true,
    tests: (r.build?.tests || []).length,
    findings: (r.review?.findings || []).length,
    confirmed: r.confirmed.length,
    refuted: r.killed,
  })),
  repair_rounds: round,
  repair_log: repairLog,
  owner_items: toOwner,
  next: 'run /gate (separate invocation), then /close — the gate is never in this run by design',
}
