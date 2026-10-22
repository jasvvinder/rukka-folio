export const meta = {
  name: 'acct-review',
  description: 'Accounting panel review: CA, munim, entity specialist and auditor review a doc, a reference book or an app-produced book; every finding is cross-examined by another panel member before it reaches the owner',
  whenToUse: 'Invoked by /acct-review. Read-only: no agent edits anything; survivors go to the owner, who decides keep or change.',
  phases: [
    { title: 'Review', detail: 'each panel member reviews the target from its own discipline' },
    { title: 'Verify', detail: 'another panel member tries to refute each finding; blockers get two refuters' },
  ],
}

// args: {
//   kind: 'docs' | 'book' | 'output',
//   target: 'short label for report names, e.g. "01" or "shop" or "app-export-S"',
//   files: ['docs/accounting/01-foundations.md', ...],   // what to review
//   golden?: 'docs/accounting/reference-books/shop-sukhwinder-sales-co.md',  // output only
//   panel?: ['acct-ca', 'acct-munim', ...],              // override the default panel
//   focus?: 'free text: what the owner wants looked at',
// }
// Reports: .claude/lane-reports/acct-<kind>-<target>-<agent>.json, written by the agents.

const PANEL = {
  docs: ['acct-ca', 'acct-munim', 'acct-entities'],
  book: ['acct-auditor', 'acct-ca', 'acct-munim', 'acct-entities'],
  output: ['acct-auditor', 'acct-ca'],
}

// who cross-examines whom: the discipline best placed to kill a wrong finding
const REFUTERS = {
  'acct-ca': ['acct-entities', 'acct-auditor'],
  'acct-munim': ['acct-ca', 'acct-entities'],
  'acct-entities': ['acct-ca', 'acct-auditor'],
  'acct-auditor': ['acct-ca', 'acct-entities'],
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
          id: { type: 'string' },
          file: { type: 'string' },
          where: { type: 'string', description: 'section, line, entry number or ledger page' },
          severity: { type: 'string', description: 'blocker | major | minor' },
          category: { type: 'string' },
          claim: { type: 'string', description: 'one sentence: what is wrong' },
          evidence: { type: 'string', description: 'quoted text + source with paragraph/page, or derived vs printed figure' },
          proposed_fix: { type: 'string' },
          confidence: { type: 'string', description: 'high | medium | low' },
        },
        required: ['file', 'where', 'severity', 'category', 'claim', 'evidence'],
      },
    },
    citations: { type: 'array', items: { type: 'object' } },
    questions: { type: 'array', items: { type: 'object' }, description: 'acct-munim only: practice questions for the human bookkeeper; not verified' },
    notes: { type: 'string' },
  },
  required: ['complete', 'findings'],
}

const VERDICT_SCHEMA = {
  type: 'object',
  properties: {
    refuted: { type: 'boolean', description: 'true = the finding does NOT hold' },
    reason: { type: 'string', description: 'the evidence that settles it: quoted rule, source paragraph/page, or arithmetic' },
  },
  required: ['refuted', 'reason'],
}

if (!args || !['docs', 'book', 'output'].includes(args.kind)) throw new Error("args.kind must be 'docs', 'book' or 'output'")
if (!args.target || !Array.isArray(args.files) || !args.files.length) throw new Error('args.target and a non-empty args.files are required')
if (args.kind === 'output' && !args.golden) log('output review without args.golden: internal checks only, no golden comparison')

const panel = args.panel?.length ? args.panel : PANEL[args.kind]
const reportPath = (a) => `.claude/lane-reports/acct-${args.kind}-${args.target}-${a}.json`

const what = {
  docs: 'the accounting rules in these documents',
  book: 'this finished reference book (printed book, Day Book/Cash Book export, and app mapping)',
  output: 'this book produced by the app',
}[args.kind]

const reviewPrompt = (a) => `Review ${what}:

${args.files.map((f) => `- ${f}`).join('\n')}
${args.golden ? `\nGolden (reference book to compare against, line by line): ${args.golden}\n` : ''}${args.focus ? `\nThe owner asks you to look especially at: ${args.focus}\n` : ''}
Work per your agent instructions, from your own discipline only. Write your report to
\`${reportPath(a)}\` as you go and keep it current. Every finding carries evidence; what you
could not check, say so. You have no Edit tool: state the defect, its evidence and a proposed fix.`

const verifyPrompt = (f, by) => `Another member of the accounting panel (${by}) filed this finding. Your job is to REFUTE it.

  file:     ${f.file}   where: ${f.where}
  severity: ${f.severity}   category: ${f.category}
  claim:    ${f.claim}
  evidence: ${f.evidence}

Read the actual text in docs/accounting/ (and the book, if one is cited), the ruling and its reason in
docs/archive/reference/accounting-research/OPEN.md if it touches one, and redo any arithmetic yourself in
integer paise. Refute it if the claim misreads the text, if the rule or a ruling already covers it with a
reason the finding does not answer, if the figures actually agree, if the source cited does not say what
is claimed, or if it is out of scope (tax/GST/TDS, app/UI/ADR matters, "should be accrual", or a case the docs do not
show: every entry is from one account to another, between accounts the user opens and chooses — ADR 2026-10-22 §2).
Default to refuted:true when you are uncertain or cannot source the claim: a finding that reaches the
owner must have survived an attempt to kill it. Do not write a report file for this pass; return only the verdict.`

const results = await pipeline(
  panel,

  // ---- Review ------------------------------------------------------------
  (a) =>
    agent(reviewPrompt(a), { label: `review:${a}`, phase: 'Review', agentType: a, schema: FINDINGS_SCHEMA })
      .then((r) => ({ agent: a, review: r })),

  // ---- Verify ------------------------------------------------------------
  async (r) => {
    const findings = r.review?.findings || []
    if (!findings.length) return { ...r, confirmed: [], refuted: [] }
    const judged = await parallel(
      findings.map((f) => () => {
        const refuters = (REFUTERS[r.agent] || ['acct-ca']).slice(0, f.severity === 'blocker' ? 2 : 1)
        return parallel(
          refuters.map((v) => () =>
            agent(verifyPrompt(f, r.agent), {
              label: `verify:${f.id || r.agent}:${v}`,
              phase: 'Verify',
              agentType: v,
              schema: VERDICT_SCHEMA,
            }),
          ),
        ).then((vs) => {
          const v = vs.filter(Boolean)
          const alive = v.filter((x) => !x.refuted).length
          // survives only on a majority of NON-refutations; no verdict returned = dropped
          return { finding: f, survives: v.length > 0 && alive * 2 > v.length, votes: v }
        })
      }),
    )
    const ok = judged.filter(Boolean)
    const confirmed = ok.filter((j) => j.survives).map((j) => ({ by: r.agent, ...j.finding, verdicts: j.votes }))
    const refuted = ok.filter((j) => !j.survives).map((j) => ({ by: r.agent, id: j.finding.id, claim: j.finding.claim, why: j.votes.map((v) => v.reason) }))
    log(`${r.agent}: ${findings.length} finding(s) → ${confirmed.length} confirmed, ${refuted.length} refuted`)
    return { ...r, confirmed, refuted }
  },
)

const done = results.filter(Boolean)
const rank = { blocker: 0, major: 1, minor: 2 }
const confirmed = done.flatMap((r) => r.confirmed).sort((a, b) => (rank[a.severity] ?? 3) - (rank[b.severity] ?? 3))

return {
  kind: args.kind,
  target: args.target,
  panel: done.map((r) => ({
    agent: r.agent,
    complete: r.review?.complete === true,
    findings: (r.review?.findings || []).length,
    confirmed: r.confirmed.length,
    refuted: r.refuted.length,
    report: reportPath(r.agent),
  })),
  confirmed,
  refuted: done.flatMap((r) => r.refuted),
  citations: done.flatMap((r) => r.review?.citations || []),
  questions_for_bookkeeper: done.flatMap((r) => r.review?.questions || []),
  next: 'present confirmed findings to the owner grouped by document, one line each with evidence; the owner rules keep/change; edits are made in the main session afterwards',
}
