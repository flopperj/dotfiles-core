export const meta = {
  name: 'code-auditor-score',
  description: 'Score a diff for structural complexity, fan-out impact, and scope; return a weighted composite with a routing band and reviewer recommendation.',
  phases: [
    { title: 'Analysis', detail: 'Three independent scorers run in parallel' },
    { title: 'Aggregate', detail: 'Weighted composite, routing band, and reviewer recommendation' }
  ]
}

// A scorer that dies or returns anything else yields null from agent(),
// which the Aggregate phase treats as a dead component.
const SCORER_SCHEMA = {
  type: 'object',
  required: ['score', 'findings'],
  properties: {
    score: { type: 'number' },
    findings: { type: 'array', items: { type: 'string' } }
  }
}

const WEIGHTS = { structural: 0.40, impact: 0.35, scope: 0.25 }

// Band cut-points over the 0-100 composite: Low 0-39, Medium 40-69, High 70-100.
const LOW_MAX = 39
const MEDIUM_MAX = 69

// In autonomous mode a borderline composite escalates to the deep reviewer.
const BORDERLINE_MIN = 65
const BORDERLINE_MAX = 74

// Exact sentinel strings the scope scorer is instructed to emit in its
// findings array. The scorer contract has no dedicated fields for the
// fast-path signals, so they travel as well-known findings entries.
const SENTINEL_TRIVIAL = 'TRIVIAL_DIFF'
const SENTINEL_DOCS_ONLY = 'DOCUMENTATION_ONLY'

// args carries the diff/target descriptor (PR number, branch, or file
// paths) and, optionally, the word "autonomous" to signal swarm mode.
const TARGET = String(args ?? '').trim()
const AUTONOMOUS = /\bautonomous\b/i.test(TARGET)

const COMMON_BRIEF = `You are one of three independent complexity scorers for a code audit.
Review target: ${TARGET}
Resolve the target to a diff (gh pr diff for a PR number or branch; git diff or direct file inspection for paths). Do not review the code or suggest fixes — measure it.
Return only the JSON object the schema requires: "score" (a number from 0 to 100) and "findings" (short strings, one per notable observation).`

const SCORER_PROMPTS = {
  structural: `${COMMON_BRIEF}

Dimension: structural complexity. For each changed function/method in the diff:
- Count decision points (if/else, switch cases, loops, ternary, catch blocks) as a proxy for cyclomatic complexity
- Measure max nesting depth
- Measure function length (lines)
- Measure file length
Score: weighted sum normalized to 0-100.`,

  impact: `${COMMON_BRIEF}

Dimension: fan-out / impact. For each changed file:
- rg for imports/usages of changed symbols across the codebase
- Count direct consumers (files that import from changed files)
- Flag if security-sensitive paths are touched (app/views/, data/schemas/, app/lib-grpc/)
Score: 0-100 based on consumer count and sensitivity.`,

  scope: `${COMMON_BRIEF}

Dimension: scope. Diff-level metrics:
- Total files changed
- Total lines added/removed
- Number of distinct directories touched
- Whether new abstractions (classes, interfaces, types) are introduced
- Whether database migrations are included
Score: 0-100.

Additionally, include these exact strings in "findings" when the conditions hold:
- "${SENTINEL_TRIVIAL}" if total lines changed <= 10 AND only 1-2 files changed AND no security-sensitive paths are touched
- "${SENTINEL_DOCS_ONLY}" if the diff is documentation-only (*.md, *.txt, or comment-only changes)`
}

phase('Analysis')
const [structural, impact, scope] = await parallel(
  ['structural', 'impact', 'scope'],
  (kind) => agent(SCORER_PROMPTS[kind], { schema: SCORER_SCHEMA, label: kind, phase: 'Analysis' })
)

phase('Aggregate')
const rawResults = { structural, impact, scope }
const clamp = (n) => Math.min(100, Math.max(0, n))

const components = {}
for (const kind of Object.keys(WEIGHTS)) {
  const r = rawResults[kind]
  if (r === null || typeof r.score !== 'number' || Number.isNaN(r.score)) {
    components[kind] = null
    log(`Scorer "${kind}" returned null (dead or schema-invalid) — ${kind} component unavailable.`)
  } else {
    components[kind] = clamp(r.score)
    log(`Scorer "${kind}": score ${components[kind]}; findings: ${JSON.stringify(r.findings)}`)
  }
}

const aliveKinds = Object.keys(WEIGHTS).filter((k) => components[k] !== null)

let result
if (aliveKinds.length <= 1) {
  // Two or more dead scorers: a composite built from at most one component
  // would be a confident wrong score. Abort with null composite/band so the
  // caller's schema validation fails and its prose fallback takes over.
  log(`Aborting: only ${aliveKinds.length} of 3 scorers returned results — not enough to aggregate.`)
  result = { composite: null, band: null, recommendation: null, components, degraded: true }
} else {
  const degraded = aliveKinds.length < Object.keys(WEIGHTS).length
  // With exactly one scorer dead, renormalize the surviving weights so the
  // composite stays on the 0-100 scale instead of deflating toward Low.
  const weightSum = aliveKinds.reduce((sum, k) => sum + WEIGHTS[k], 0)
  const composite = Math.round(
    aliveKinds.reduce((sum, k) => sum + components[k] * (WEIGHTS[k] / weightSum), 0)
  )
  const band = composite <= LOW_MAX ? 'Low' : composite <= MEDIUM_MAX ? 'Medium' : 'High'

  const scopeFindings = scope !== null && Array.isArray(scope.findings) ? scope.findings : []
  const docsOnly = scopeFindings.includes(SENTINEL_DOCS_ONLY)
  const trivial = scopeFindings.includes(SENTINEL_TRIVIAL)

  let recommendation
  if (docsOnly) {
    recommendation = 'none'
    log('Documentation-only change — no code review needed.')
  } else if (trivial) {
    recommendation = 'scout'
    log('Trivial-diff fast path: lightweight single-pass review (Scout with collapsed analysis).')
  } else if (band === 'High') {
    recommendation = 'ranger'
  } else if (AUTONOMOUS && composite >= BORDERLINE_MIN && composite <= BORDERLINE_MAX) {
    recommendation = 'ranger'
    log(`Borderline composite ${composite} in autonomous mode — escalating to the deep reviewer.`)
  } else {
    recommendation = 'scout'
  }

  if (degraded) {
    const dead = Object.keys(WEIGHTS).filter((k) => components[k] === null)
    log(`Degraded scoring: component(s) unavailable: ${dead.join(', ')} — weights renormalized over ${aliveKinds.join(', ')}.`)
  }
  log(`Composite inputs: ${JSON.stringify(components)} with weights ${JSON.stringify(WEIGHTS)} -> composite ${composite}, band ${band}, recommendation ${recommendation}.`)

  result = { composite, band, recommendation, components, degraded }
}

// Machine-consumable return only — narration stays in the log above.
result
