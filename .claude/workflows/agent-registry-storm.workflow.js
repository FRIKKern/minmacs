export const meta = {
  name: 'agent-registry-storm',
  description: 'Research every agent harness in parallel, adversarially verify each registry row, then synthesize',
  whenToUse: 'Fill or refresh registry/agents/*.json, the data MinMacs and Insomnia use to tell working agents from idle ones',
  phases: [
    { title: 'Research', detail: 'one agent per harness writes a registry row with evidence', model: 'sonnet' },
    { title: 'Verify', detail: 'a skeptic tries to refute each row, then repairs or downgrades it', model: 'sonnet' },
    { title: 'Hosts', detail: 'what terminals and multiplexers can report on their own', model: 'sonnet' },
    { title: 'Synthesize', detail: 'registry README, cross-harness findings, and what is still missing', model: 'sonnet' },
  ],
}

// args: { repo, today, harnesses: [{id,name,surfaces_hint,start_at,installed_here}], hosts: {...} }
const { repo, today, harnesses, hosts } = args
const MODEL = 'sonnet', EFFORT = 'high'   // high, not max: at max this model tends to widen scope

const RULES = `
Ground rules, all binding:
- Work in ${repo}. Read registry/schema.json, registry/agents/claude-code.json (the worked example) and tools/agents_probe.py first. They are the contract.
- Write ONLY the files named in your task. Do not edit any other file. Do not commit, push, or create branches.
- Do not install anything. Do not start, resume or message any agent session. Read-only commands only: --version, --help, ls, stat, file, strings, ps, lsof.
- Privacy: session stores hold private conversations. You may list file names, sizes and modification times, and print the KEY NAMES of one record. Never print, quote or summarise message content.
- Evidence or it does not go in. Every non-obvious field needs a sources entry: an official docs URL, a path in the vendor's public source, or the exact local command with what it printed. Say "inferred" when that is what it is.
- Undocumented paths are fine to record, with session_store.documented=false.
- Today is ${today}. Your training data may predate current releases; prefer what you can fetch or observe over what you remember.`

const ROW_RESULT = {
  type: 'object',
  required: ['id', 'confidence', 'wrote_row', 'summary'],
  properties: {
    id: { type: 'string' },
    confidence: { type: 'string', enum: ['verified-locally', 'documented', 'inferred'] },
    wrote_row: { type: 'boolean' },
    best_working_signal: { type: 'string' },
    has_hooks: { type: 'boolean' },
    summary: { type: 'string' },
    open_questions: { type: 'array', items: { type: 'string' } },
    model_self_report: { type: 'string' },
  },
}
const VERDICT = {
  type: 'object',
  required: ['id', 'verdict', 'final_confidence'],
  properties: {
    id: { type: 'string' },
    verdict: { type: 'string', enum: ['pass', 'repaired', 'rejected'] },
    final_confidence: { type: 'string', enum: ['verified-locally', 'documented', 'inferred'] },
    claims_checked: { type: 'number' },
    claims_refuted: { type: 'number' },
    changes: { type: 'array', items: { type: 'string' } },
    remaining_doubts: { type: 'array', items: { type: 'string' } },
  },
}

const research = h => agent(`Research how to recognise the agent harness "${h.name}" on macOS and how to tell whether it is working or idle.

Known surfaces, as a hint only: ${h.surfaces_hint}
Start at: ${h.start_at}
Installed on this Mac: ${h.installed_here ? 'YES. Inspect the real install read-only, and run `tools/agents_probe.py --row registry/agents/' + h.id + '.json` to see how your row classifies what is running.' : 'no. Work from official docs and the public source code.'}

Find, for every surface the harness has: process names and executable paths, app bundle ids, how a process maps to its own session, where sessions are stored and in what format, which signal most precisely means "a turn is in progress", how to tell it is waiting on the human, what lifecycle hooks exist and where they are configured, and whether it exports OpenTelemetry.

Write exactly two files:
1. registry/agents/${h.id}.json, a row that passes \`tools/validate_row.py registry/agents/${h.id}.json\`. Run the validator and fix the row until it passes.
2. registry/evidence/${h.id}.md, short notes: what you checked, what you could not determine, and anything that contradicts common belief.

Return the structured result. In model_self_report, state the model name and ID from your own system prompt.
${RULES}`, { label: `research:${h.id}`, phase: 'Research', model: MODEL, effort: EFFORT, schema: ROW_RESULT })

const verify = (r, h) => {
  if (!r || !r.wrote_row) return null
  return agent(`You did not write registry/agents/${h.id}.json. Your job is to REFUTE it. Assume it is wrong until the evidence says otherwise.

1. Run \`tools/validate_row.py registry/agents/${h.id}.json\`.
2. For every entry in sources: open the URL or re-run the command and check that it actually supports the claim. A source that does not say what the row claims is a refuted claim.
3. Check the process patterns for false positives: would they also match an unrelated program, a helper, or a different product with a similar name?
4. ${h.installed_here ? 'This harness is installed here. Run `tools/agents_probe.py --row registry/agents/' + h.id + '.json` and judge whether the classification is believable against `ps`.' : 'This harness is not installed here, so confidence can be at most "documented".'}
5. Repair the row in place where you can prove the correction. Downgrade confidence where the evidence is thin. If the row cannot be made trustworthy, set confidence to "inferred" and say why in notes.
6. Append a "## Verification" section to registry/evidence/${h.id}.md listing each claim as confirmed, corrected or unsupported.

You may edit only those two files.
${RULES}`, { label: `verify:${h.id}`, phase: 'Verify', model: MODEL, effort: EFFORT, schema: VERDICT })
    .then(v => ({ ...r, verification: v }))
}

// Hosts research runs alongside the harness pipeline; it is one independent question.
const hostsJob = agent(`${hosts.question}

Start at: ${hosts.start_at}
cmux is installed on this Mac: run \`cmux --help\`, \`cmux docs agents\`, \`cmux docs api\`, \`cmux capabilities\`, \`cmux hooks --help\` and \`cmux list-workspaces\`. Do not run any command that changes cmux state, and do not install or uninstall hooks.

Write exactly one file, registry/evidence/hosts.md, answering for each host: what it knows about a running agent, how another program can ask it (socket, CLI, API, escape sequences), whether that needs per-harness setup, and how reliable it is. End with a ranked recommendation of which host signals MinMacs should read first.
${RULES}`, { label: 'research:hosts', phase: 'Hosts', model: MODEL, effort: EFFORT })

const rows = (await pipeline(harnesses, research, verify)).filter(Boolean)
const hostsNote = await hostsJob

const dropped = harnesses.length - rows.length
if (dropped) log(`${dropped} of ${harnesses.length} harnesses produced no verified row; they are listed in the synthesis as gaps`)

phase('Synthesize')
const [readme, gaps] = await parallel([
  () => agent(`Every file under registry/agents/ and registry/evidence/ in ${repo} has now been researched and verified. Read all of them.

Write exactly one file, registry/README.md, containing:
1. One table: harness, surfaces, most precise working signal, hooks yes or no, session store, confidence.
2. "What is universal": signals that hold across most harnesses, with the count of rows supporting each.
3. "What needs specialisation": the cases a generic detector gets wrong, and the smallest rule that fixes each.
4. "Recommended defaults" for the generic detector: CPU floor, hold window, which child processes count as tools.
Plain language, no marketing. Cite row ids for every claim.
${RULES}`, { label: 'synthesis:readme', phase: 'Synthesize', model: MODEL, effort: EFFORT }),
  () => agent(`Completeness critic. Read registry/harnesses.json, every row under registry/agents/ and every note under registry/evidence/ in ${repo}.

Report what is missing or weak: harnesses in wide use that are not listed, surfaces a row skipped, claims resting on a single third-party source, rows whose working signal is only CPU, and any two rows whose process patterns could match the same process. Do not write or edit any file. Return the list as your final text, most important first.
${RULES}`, { label: 'synthesis:gaps', phase: 'Synthesize', model: MODEL, effort: EFFORT }),
])

return {
  rows: rows.map(r => ({ id: r.id, confidence: r.verification ? r.verification.final_confidence : r.confidence,
                         verdict: r.verification ? r.verification.verdict : 'unverified',
                         signal: r.best_working_signal, hooks: r.has_hooks,
                         doubts: r.verification ? r.verification.remaining_doubts : [] })),
  models_reported: [...new Set(rows.map(r => r.model_self_report).filter(Boolean))],
  missing: harnesses.filter(h => !rows.some(r => r.id === h.id)).map(h => h.id),
  hosts_written: !!hostsNote,
  readme_written: !!readme,
  gaps,
}
