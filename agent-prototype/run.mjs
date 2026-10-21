// Writes a sample note for each invented scenario, checks it, and saves a
// review file for you and the clinician: samples/latest.md (and .json).
//
//   npm run dry-run      shows what would be sent, calls nothing, costs nothing
//   npm start            runs every scenario (needs ANTHROPIC_API_KEY)
//   node run.mjs --only=good-day --no-judge
//
// Only invented data goes to the API: see scenarios.mjs.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import Anthropic from '@anthropic-ai/sdk';

import { checkNote } from './checks.mjs';
import {
  JUDGE_SCHEMA,
  JUDGE_SYSTEM,
  NOTE_SCHEMA,
  NOTE_SYSTEM,
  judgeRequest,
  noteRequest,
} from './prompt.mjs';
import { scenarios } from './scenarios.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const MODEL = 'claude-opus-5-5';

// US dollars per million tokens for Claude Opus 5.5, as listed in October
// 2026. A declined request answered by a fallback model is priced
// differently, so the total is an estimate.
const PRICE = { input: 4, output: 20, cacheRead: 0.2, cacheWrite: 5 };

const argv = process.argv.slice(2);
const dryRun = argv.includes('--dry-run');
const judge = !argv.includes('--no-judge');
const only = argv.find((a) => a.startsWith('--only='))?.slice('--only='.length);
const effort = argv.find((a) => a.startsWith('--effort='))?.slice('--effort='.length) ?? 'medium';

// The reviewed card texts: the 30 cards and the stage 1 cards.
const pack = JSON.parse(
  fs.readFileSync(
    path.join(here, '..', 'content', 'her-insights-en-GB-combined.json'),
    'utf8',
  ),
);
const cards = new Map(
  [
    ...pack.prior_base_cards,
    ...pack.stage1_candidate_cards,
    ...pack.stage1_alternate_wordings,
  ].map((card) => [card.id, card]),
);

function cardsFor(scenario) {
  return scenario.cards.map((id) => {
    const card = cards.get(id);
    if (!card) throw new Error(`No reviewed card ${id} (scenario ${scenario.id})`);
    return card;
  });
}

const chosen = scenarios.filter((s) => !only || s.id === only);
if (chosen.length === 0) {
  console.error(`No scenario called "${only}".`);
  process.exit(1);
}

if (dryRun) {
  const first = chosen[0];
  console.log('--- Instructions (the same for every note) ---\n');
  console.log(NOTE_SYSTEM);
  console.log(`\n--- What is sent for "${first.id}" ---\n`);
  console.log(noteRequest(first, cardsFor(first)));
  console.log(
    `\n${chosen.length} scenario(s), ${judge ? 2 : 1} call(s) each, model ${MODEL}, effort ${effort}. Nothing was sent.`,
  );
  process.exit(0);
}

const client = new Anthropic();

/// One request with a fixed JSON answer shape. Declines are returned, not
/// thrown, so one refusal does not stop the run.
async function ask(system, user, schema) {
  const response = await client.beta.messages.create({
    model: MODEL,
    max_tokens: 16000,
    // If a safety check declines the request, Anthropic's recommended
    // fallback model answers it instead.
    betas: ['server-side-fallback-2026-07-01'],
    fallbacks: 'default',
    system: [{ type: 'text', text: system, cache_control: { type: 'ephemeral' } }],
    messages: [{ role: 'user', content: user }],
    output_config: { effort, format: { type: 'json_schema', schema } },
  });
  if (response.stop_reason === 'refusal') {
    return {
      declined: response.stop_details?.category ?? 'no category',
      usage: response.usage,
      model: response.model,
    };
  }
  if (response.stop_reason === 'max_tokens') {
    throw new Error('The answer was cut off (max_tokens).');
  }
  const text = response.content
    .filter((block) => block.type === 'text')
    .map((block) => block.text)
    .join('');
  return { data: JSON.parse(text), usage: response.usage, model: response.model };
}

const cost = (u) =>
  ((u?.input_tokens ?? 0) * PRICE.input +
    (u?.output_tokens ?? 0) * PRICE.output +
    (u?.cache_read_input_tokens ?? 0) * PRICE.cacheRead +
    (u?.cache_creation_input_tokens ?? 0) * PRICE.cacheWrite) /
  1e6;

const results = [];
let spent = 0;

for (const scenario of chosen) {
  const used = cardsFor(scenario);
  process.stdout.write(`${scenario.id} ... `);
  const result = { scenario, cards: used };
  try {
    const note = await ask(NOTE_SYSTEM, noteRequest(scenario, used), NOTE_SCHEMA);
    spent += cost(note.usage);
    result.model = note.model;
    if (note.declined) {
      result.declined = note.declined;
    } else {
      result.note = note.data;
      result.checks = checkNote(note.data, scenario, used);
      if (judge) {
        const review = await ask(
          JUDGE_SYSTEM,
          judgeRequest(scenario, used, note.data.message),
          JUDGE_SCHEMA,
        );
        spent += cost(review.usage);
        result.judge = review.declined ? { verdict: 'declined' } : review.data;
      }
    }
  } catch (error) {
    if (error instanceof Anthropic.AuthenticationError) {
      console.error(
        '\nThe API key was not accepted. Set it in this terminal first: $env:ANTHROPIC_API_KEY = "..."',
      );
      process.exit(1);
    }
    result.error =
      error instanceof Anthropic.APIError
        ? `API error ${error.status}: ${error.message}`
        : String(error?.message ?? error);
  }
  results.push(result);
  console.log(summaryLine(result));
}

function passed(result) {
  return (
    !result.error &&
    !result.declined &&
    result.checks.every((c) => c.ok) &&
    (!result.judge || result.judge.verdict === 'pass')
  );
}

function summaryLine(result) {
  if (result.error) return `error: ${result.error}`;
  if (result.declined) return `declined (${result.declined})`;
  const failed = result.checks.filter((c) => !c.ok).length;
  const verdict = result.judge ? `, reviewer: ${result.judge.verdict}` : '';
  return `${failed === 0 ? 'checks passed' : `${failed} check(s) failed`}${verdict}`;
}

// ---- The review file ------------------------------------------------------

const lines = [
  '# MoonCycle daily note: prototype samples',
  '',
  `Made ${new Date().toISOString().slice(0, 10)} with ${MODEL} (effort ${effort}) from invented scenarios. Not reviewed, not for real users.`,
  '',
  `${results.filter(passed).length} of ${results.length} passed every check. Approximate cost of this run: $${spent.toFixed(2)}.`,
  '',
  'Under each note the app would show the card\'s reviewed "See a GP" and "Get help now" text, word for word. For each note: is it accurate to the card, is the tone right, would you change anything?',
  '',
];

for (const result of results) {
  const { scenario } = result;
  lines.push(`## ${scenario.title}`, '');
  lines.push(`Scenario \`${scenario.id}\`, card ${result.cards.map((c) => `${c.id} "${c.title}"`).join(', ')}.`, '');
  lines.push('What her phone worked out:', '');
  for (const [key, value] of Object.entries(scenario.summary)) {
    lines.push(`- ${key.replaceAll('_', ' ')}: ${Array.isArray(value) ? value.join(', ') : value}`);
  }
  lines.push('');
  if (result.error) {
    lines.push(`**Error:** ${result.error}`, '');
    continue;
  }
  if (result.declined) {
    lines.push(`**Declined by the model's safety checks** (${result.declined}).`, '');
    continue;
  }
  lines.push('**The note:**', '', `> ${result.note.message}`, '');
  for (const card of result.cards) {
    if (card.see_gp_if) lines.push(`Shown under it: ${card.see_gp_if}`, '');
    if (card.get_help_now_if) lines.push(`Folded away under it: ${card.get_help_now_if}`, '');
  }
  if (result.model && result.model !== MODEL) {
    lines.push(`Answered by the fallback model ${result.model}.`, '');
  }
  lines.push('Checks:', '');
  for (const check of result.checks) {
    lines.push(`- ${check.ok ? 'OK' : 'FAILED'}: ${check.name}${!check.ok && check.detail ? ` (${check.detail})` : ''}`);
  }
  if (result.judge) {
    const j = result.judge;
    lines.push(`- Second reading by the model: ${j.verdict}`);
    for (const [label, items] of [
      ['Not in the sources', j.unsupported],
      ['Diagnosis or cause', j.diagnosis_or_cause],
      ['Other', j.other_issues],
    ]) {
      for (const item of items ?? []) lines.push(`  - ${label}: "${item}"`);
    }
  }
  lines.push('');
}

const out = path.join(here, 'samples');
fs.mkdirSync(out, { recursive: true });
fs.writeFileSync(path.join(out, 'latest.md'), lines.join('\n'));
fs.writeFileSync(
  path.join(out, 'latest.json'),
  JSON.stringify(
    results.map(({ scenario, cards: used, ...rest }) => ({
      scenario: scenario.id,
      cards: used.map((c) => c.id),
      ...rest,
    })),
    null,
    2,
  ),
);
console.log(`\nSaved samples/latest.md. Approximate cost: $${spent.toFixed(2)}.`);
