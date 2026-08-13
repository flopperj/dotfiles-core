export const meta = {
  name: 'team-lead-waves',
  description: 'Execute an already-sequenced ticket wave plan: waves run sequentially, tickets within a wave run in parallel; return the swarm-context accumulator object.',
  phases: [
    { title: 'Plan intake', detail: 'Parse and validate the wave plan passed via args' },
    { title: 'Waves', detail: 'One phase per wave: sequential outer loop, parallel inner ticket pipelines' }
  ]
}

// Ownership split: team-lead/SKILL.md builds the dependency graph (Step 1
// sequencing rules: same-file tickets never share a wave, Jira "Blocks"
// forces order, schema -> API -> frontend) and injects domain context
// (Step 2). This workflow only EXECUTES the already-sequenced plan.
//
// args is a JSON object:
//   waves               required — the Step 1 plan in the swarm-context
//                       shape: [{ index, tickets: [keys], parallel }]
//   domain              required — backend | frontend | infra | unknown
//   sequencing_reasons  optional — one string per ordering decision
//   briefs              optional — { ticketKey: pipeline brief text }; the
//                       full per-ticket brief (enrichment + domain context
//                       + branch/base-branch + ticket_complexity) prepared
//                       by the SKILL.md, passed verbatim to that ticket's
//                       pipeline agent

// One pipeline result per ticket. A pipeline that dies or returns anything
// else yields null from agent(); the wave loop attributes that null to its
// ticket BY INDEX — attribution happens before any filtering, because the
// index-to-ticket mapping is how a blocked ticket gets named.
const TICKET_RESULT = {
  type: 'object',
  required: ['ticket', 'status', 'summary', 'files_touched'],
  properties: {
    ticket: { type: 'string' },
    status: { type: 'string', enum: ['done', 'blocked'] },
    summary: { type: 'string' },
    files_touched: { type: 'array', items: { type: 'string' } }
  }
}

// parallel() caps at 16 concurrent agents (1000 per run). A wave wider
// than the cap queues rather than erroring — acceptable, but logged so a
// 40-ticket wave reads as queued, not mysteriously slow.
const PARALLEL_CAP = 16

// Accumulator condensation, mirroring team-lead/SKILL.md's size limits:
// the last N waves keep full detail; older waves condense to one line per
// ticket (key, status, file count).
const FULL_DETAIL_WAVES = 3

const VALID_DOMAINS = ['backend', 'frontend', 'infra', 'unknown']

phase('Plan intake')

let plan = null
try {
  plan = JSON.parse(String(args ?? ''))
} catch (e) {
  plan = null
}

const isValidWave = (w) =>
  w !== null &&
  typeof w === 'object' &&
  Number.isInteger(w.index) &&
  Array.isArray(w.tickets) &&
  w.tickets.length > 0 &&
  w.tickets.every((t) => typeof t === 'string' && t.length > 0) &&
  typeof w.parallel === 'boolean'

const planValid =
  plan !== null &&
  typeof plan === 'object' &&
  Array.isArray(plan.waves) &&
  plan.waves.length > 0 &&
  plan.waves.every(isValidWave)

const briefFor = (key) => {
  const briefs = planValid && plan.briefs !== null && typeof plan.briefs === 'object' ? plan.briefs : {}
  return typeof briefs[key] === 'string' ? briefs[key] : ''
}

const pipelinePromptFor = (key, waveIndex, priorContext) => {
  const brief = briefFor(key)
  return `You are one ticket pipeline inside a team-lead swarm wave (wave ${waveIndex}).
Ticket: ${key}
Run the ticket-pickup pipeline for this ticket with swarm_mode: true and execution_mode: autonomous.

${brief
    ? `Pipeline brief (enriched ticket + domain context, prepared by the team lead):
${brief}`
    : 'No pipeline brief was provided — fetch and enrich the ticket yourself per ticket-pickup Steps 2-4 before implementing.'}

${priorContext
    ? `Prior wave context (what upstream tickets in this cluster already built):
${priorContext}`
    : 'This is the first wave — no prior wave context.'}

When the pipeline finishes, return ONLY the JSON object the schema requires:
- "ticket": "${key}"
- "status": "done" if the pipeline completed, "blocked" if it hit a blocker it could not resolve
- "summary": one short paragraph — what was built (files created/modified, classes/interfaces established, tests written, reviewer outcome) or why it blocked
- "files_touched": repo-relative paths of every file the pipeline created or modified (empty array if blocked before any change)
This is a workflow-owned stage: the schema-validated return IS the completion signal — no sentinel token is required.`
}

// Render the accumulated prior-wave context for injection into the next
// wave's pipeline prompts. Waves older than FULL_DETAIL_WAVES condense.
const renderAccumulator = (acc) => {
  if (acc.length === 0) return ''
  const lines = []
  const cutoff = acc.length - FULL_DETAIL_WAVES
  acc.forEach((wave, i) => {
    if (i < cutoff) {
      for (const e of wave.entries) {
        lines.push(`Wave ${wave.index} — ${e.ticket}: ${e.status} (${e.files.length} file(s))`)
      }
    } else {
      lines.push(`Wave ${wave.index} results:`)
      for (const e of wave.entries) {
        lines.push(`  ${e.ticket}: ${e.status} — ${e.summary}`)
        if (e.files.length > 0) {
          lines.push(`    files: ${e.files.join(', ')}`)
        }
      }
    }
  })
  return lines.join('\n')
}

let result
if (!planValid) {
  // Malformed args: there is nothing safe to execute. Return an object
  // whose null fields fail the caller's swarm-context schema validation
  // by design, so team-lead/SKILL.md's prose fallback takes over.
  log('Aborting: args did not parse as a valid wave plan (expected JSON with a non-empty "waves" array of { index, tickets[], parallel }).')
  result = { waves: null, sequencing_reasons: null, domain: null, blocked: null }
} else {
  const waves = plan.waves.map((w) => ({
    index: w.index,
    tickets: [...w.tickets],
    parallel: w.parallel
  }))
  const domain = VALID_DOMAINS.includes(plan.domain) ? plan.domain : 'unknown'
  const sequencingReasons = Array.isArray(plan.sequencing_reasons)
    ? plan.sequencing_reasons.filter((s) => typeof s === 'string')
    : []

  log(`Plan intake: ${waves.length} wave(s), ${waves.reduce((n, w) => n + w.tickets.length, 0)} ticket(s), domain "${domain}".`)

  const accumulator = []
  const blocked = []

  for (const wave of waves) {
    phase(`Wave ${wave.index}`)
    const width = wave.tickets.length
    const capNote = width > PARALLEL_CAP
      ? ` Width exceeds the ${PARALLEL_CAP}-agent parallel() cap — excess tickets queue rather than erroring; expect a longer wave, not a failure.`
      : ''
    log(`Wave ${wave.index}: width ${width}, ${wave.parallel ? 'parallel' : 'sequential'}.${capNote}`)

    const priorContext = renderAccumulator(accumulator)

    let results
    if (wave.parallel) {
      results = await parallel(
        wave.tickets.map((key) => () =>
          agent(pipelinePromptFor(key, wave.index, priorContext), {
            schema: TICKET_RESULT,
            label: key,
            phase: `Wave ${wave.index}`
          }))
      )
    } else {
      results = []
      for (const key of wave.tickets) {
        results.push(await agent(pipelinePromptFor(key, wave.index, priorContext), {
          schema: TICKET_RESULT,
          label: key,
          phase: `Wave ${wave.index}`
        }))
      }
    }

    // Attribute every result to its ticket BY INDEX before any filtering —
    // parallel() retains dead agents positionally as null, and the position
    // is the only thing that names the blocked ticket.
    const entries = []
    for (let i = 0; i < wave.tickets.length; i++) {
      const key = wave.tickets[i]
      const r = results[i]
      if (r === null || typeof r !== 'object') {
        blocked.push(key)
        entries.push({ ticket: key, status: 'blocked', summary: 'pipeline agent died or returned a schema-invalid result', files: [] })
        log(`Wave ${wave.index} — ${key}: BLOCKED (agent returned null — dead or schema-invalid).`)
      } else {
        if (r.ticket !== key) {
          log(`Wave ${wave.index} — ${key}: result self-identified as "${r.ticket}"; positional attribution to ${key} is authoritative.`)
        }
        const files = Array.isArray(r.files_touched) ? r.files_touched : []
        if (r.status === 'blocked') {
          blocked.push(key)
          entries.push({ ticket: key, status: 'blocked', summary: r.summary, files })
          log(`Wave ${wave.index} — ${key}: BLOCKED — ${r.summary}`)
        } else {
          entries.push({ ticket: key, status: 'done', summary: r.summary, files })
          log(`Wave ${wave.index} — ${key}: done — ${files.length} file(s) touched.`)
        }
      }
    }
    accumulator.push({ index: wave.index, entries })

    const succeeded = entries.filter((e) => e.status === 'done').length
    log(`Wave ${wave.index} complete: ${succeeded}/${width} succeeded${succeeded < width ? `, blocked: ${entries.filter((e) => e.status === 'blocked').map((e) => e.ticket).join(', ')}` : ''}.`)
  }

  log(`All waves complete: ${blocked.length} blocked ticket(s)${blocked.length > 0 ? ` (${blocked.join(', ')})` : ''}.`)
  result = { waves, sequencing_reasons: sequencingReasons, domain, blocked }
}

// Machine-consumable return only — narration stays in the log above.
result
