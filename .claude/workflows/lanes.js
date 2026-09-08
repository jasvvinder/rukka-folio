export const meta = {
  name: 'lanes',
  description: 'Run 1-3 Rukka Folio build lanes in parallel by agent tier, write durable reports, then STOP (no gate)',
  whenToUse: 'Invoked by /lane. The gate is a separate run (workflow `gate-run`) so a limit hit never costs a whole phase.',
  phases: [{ title: 'Lanes', detail: 'one subagent per lane, disjoint directories, tests-first' }],
}

// args: { milestone: 'M4', lanes: [{ key, agent, dirs: [..], prompt, model?, effort? }] }
//   agent  = an agent definition in .claude/agents/: lane-mech | lane-ui | lane-server |
//            lane-sync | lane-core.  Model and effort come from that FILE, not from here —
//            that is the point. model/effort per lane are escape hatches, normally absent.
//   Reports land in .claude/lane-reports/<milestone>-<key>.json, written by the lane itself,
//   so a session-limit kill loses the run but never the work. /lane skips lanes already
//   reported there.
const LANE_SCHEMA = {
  type: 'object',
  properties: {
    complete: { type: 'boolean', description: 'true only if the whole task is finished; false if the turn cap or anything else cut it short' },
    files: { type: 'array', items: { type: 'string' } },
    tests: { type: 'array', items: { type: 'string' }, description: 'test ids added or made green' },
    open: { type: 'array', items: { type: 'string' }, description: '⚠️ SPEC / 🔒 / owner items; a 🔒 item is the escalation trigger' },
    notes: { type: 'string' },
  },
  required: ['complete', 'files', 'tests', 'open'],
}

const MAX_LANES = 3

if (!args || !Array.isArray(args.lanes) || args.lanes.length === 0) {
  throw new Error('args.lanes must be a non-empty array of { key, agent, dirs, prompt }')
}
if (args.lanes.length > MAX_LANES) {
  throw new Error(
    `${args.lanes.length} lanes requested; the cap is ${MAX_LANES} per run (PLAN.md §3 session economy). ` +
      `Split into separate runs — a limit hit should cost one run, not a phase.`,
  )
}
const missing = args.lanes.filter((l) => !l.key || !l.agent || !l.dirs?.length || !l.prompt)
if (missing.length) {
  throw new Error(`lane(s) missing key/agent/dirs/prompt: ${JSON.stringify(missing.map((l) => l.key ?? '?'))}`)
}

phase('Lanes')
const settled = await parallel(
  args.lanes.map((l) => () =>
    agent(
      `Milestone ${args.milestone}. You are lane **${l.key}**.

You own these directories and must not touch anything else:
${l.dirs.map((d) => `  - ${d}`).join('\n')}

Your report file (write it early, keep it current, \`complete: false\` until wholly done):
  .claude/lane-reports/${args.milestone}-${l.key}.json

${l.prompt}`,
      {
        label: `lane:${l.key}`,
        phase: 'Lanes',
        schema: LANE_SCHEMA,
        agentType: l.agent,
        ...(l.model ? { model: l.model } : {}),
        ...(l.effort ? { effort: l.effort } : {}),
      },
    )
      .then((r) => (r ? { key: l.key, agent: l.agent, ...r } : { key: l.key, agent: l.agent, dead: true }))
      // A lane that throws — most often the turn cap ending it before StructuredOutput — resolves
      // to null in `parallel`, which loses the key with it. Catch here so every slot stays an
      // object and the run can still name which lanes need re-running.
      .catch((e) => ({ key: l.key, agent: l.agent, dead: true, error: String((e && e.message) || e) })),
  ),
)

// A lane is unfinished either because it died (no report returned) or because it capped out
// mid-flight and said so. Both need another /lane run; neither may be gated over.
// `parallel` can still hand back a null slot; keep it aligned with the lane that produced it.
const results = settled.map((r, i) => r ?? { key: args.lanes[i].key, agent: args.lanes[i].agent, dead: true })
const lanes = results.filter((r) => !r.dead)
const incomplete = results.filter((r) => r.dead || r.complete === false).map((r) => r.key)
const escalate = lanes.filter((l) => (l.open || []).some((o) => /🔒|ADR|golden|STOP/i.test(o))).map((l) => l.key)

log(`${lanes.length}/${args.lanes.length} lanes reported`)
if (incomplete.length) {
  log(`INCOMPLETE: ${incomplete.join(', ')} — work is partly on disk and the report says so. Re-run /lane for these keys; do NOT gate yet.`)
}
if (escalate.length) {
  log(`ESCALATION CANDIDATES (🔒 / ADR / golden): ${escalate.join(', ')} — owner decides before any lane-core run.`)
}

// The gate deliberately does NOT run here. Next step is a separate `gate-run`, and only
// once `incomplete` is empty.
return {
  milestone: args.milestone,
  ok: incomplete.length === 0,
  lanes,
  incomplete,
  escalate,
  next: incomplete.length ? `re-run /lane ${incomplete.join(' ')}` : 'run /gate (separate invocation)',
}
