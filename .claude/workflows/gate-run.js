export const meta = {
  name: 'gate-run',
  description: 'Run the Rukka Folio CI gate once for a lane; fix only mechanical failures; report the rest verbatim',
  whenToUse: 'Invoked by /gate after `lanes` reported ok:true. Deliberately separate from the lane run.',
  phases: [{ title: 'Gate', detail: 'LANE=<lane> ./scripts/ci.sh once; mechanical fixes only' }],
}

// args: { lane?: 'push' | 'nightly' | 'rc' | 'release', landed?: [{ key, files, tests }] }
const GATE_SCHEMA = {
  type: 'object',
  properties: {
    green: { type: 'boolean' },
    fixed: { type: 'array', items: { type: 'string' } },
    failures: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          step: { type: 'string' },
          package: { type: 'string' },
          test: { type: 'string' },
          message: { type: 'string' },
        },
        required: ['step', 'message'],
      },
    },
  },
  required: ['green', 'fixed', 'failures'],
}

const lane = args?.lane || 'push'

phase('Gate')
const gate = await agent(
  `Run the gate for LANE=${lane}.
${args?.landed?.length ? `\nLanes that just landed:\n${JSON.stringify(args.landed)}` : ''}`,
  { label: `gate:${lane}`, phase: 'Gate', schema: GATE_SCHEMA, agentType: 'gate' },
)

if (!gate) return { lane, green: false, failures: [{ step: 'gate', message: 'gate agent died or was skipped; re-run /gate' }], fixed: [] }
log(gate.green ? `gate green (${lane})` : `gate RED (${lane}): ${gate.failures.length} failure(s)`)
return { lane, ...gate }
