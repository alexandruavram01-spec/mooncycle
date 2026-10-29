// Her AI-written daily note. Only for accounts that turned the notes on.
//
// Her phone's rules pick the reviewed card and work out the facts about her
// day; this writes those facts and the card's text as one short note. The
// GP line and the urgent-help line stay on her phone, word for word: the
// model never sees them. Any doubt and the answer is null, and her phone
// shows the reviewed card instead.
//
// Nothing here is stored or logged: not her summary, not the note.

const fs = require('node:fs');
const path = require('node:path');

const MODEL = process.env.AI_NOTES_MODEL || 'claude-opus-5-5';
// Where Anthropic runs the model: only in the United States, where it also
// stores data, so her summary goes to one country (priced at 1.1x).
const GEO = process.env.AI_NOTES_GEO || 'us';
const EFFORT = process.env.AI_NOTES_EFFORT || 'medium';
// A second reading of each note against its card, before it is used.
const SECOND_READING = process.env.AI_NOTES_REVIEW !== 'off';

// The reviewed card texts, deployed beside this file from
// content/her-insights-en-GB-combined.json.
const pack = JSON.parse(
  fs.readFileSync(path.join(__dirname, 'her-cards.json'), 'utf8'),
);
const CARDS = new Map(
  [
    ...pack.prior_base_cards,
    ...pack.stage1_candidate_cards,
    ...pack.stage1_alternate_wordings,
  ].map((card) => [card.id, card]),
);
const OPENINGS = new Map(pack.stage1_openings.map((o) => [o.id, o.body]));

// The same cards in Romanian, deployed beside this file from
// content/her-insights-ro.json (made by tool/export_ro_cards.py). Without
// it, Romanian requests get no note and her phone shows the card.
const RO = (() => {
  try {
    return JSON.parse(fs.readFileSync(path.join(__dirname, 'her-cards-ro.json'), 'utf8'));
  } catch {
    return null;
  }
})();
const LANGUAGES = ['en', 'ro'];

// Cards that always show as reviewed, never rewritten: warning signs, late
// or long bleeding, pregnancy and fertility timing, contraception, low mood,
// medicines and the drafts from her own log.
const FIXED_ONLY = new Set([
  'I03', 'I05', 'I08', 'I09', 'I11', 'I21', 'I22', 'I23', 'I24', 'I25',
  'I26', 'I27', 'I28', 'I29', 'I30', 'NEW02', 'L07', 'L08', 'L12', 'L18',
  'L20', 'C02', 'C07', 'M03', 'M04', 'H01', 'H02', 'H03',
]);

const SYMPTOMS = [
  'Cramps', 'Headache', 'Backache', 'Breast tenderness', 'Joint pain',
  'Ovulation pain', 'Happy', 'Calm', 'Irritable', 'Anxious', 'Sad',
  'Sensitive', 'Confident', 'Bloating', 'Acne', 'Nausea', 'Fatigue',
  'Dizziness', 'Hot flush', 'Food cravings', 'Constipation', 'Diarrhoea',
  'Appetite up', 'Appetite down', 'Dry', 'Sticky', 'Creamy', 'Egg white',
  'Watery', 'High drive', 'Low drive', 'Usual drive', 'Protected', 'Unprotected',
];
const FLOWS = ['spotting', 'light', 'medium', 'heavy'];
// Not symptoms, but things an opening line can be about.
const OTHER = ['heavy flow', 'low energy'];

// How each is written in a sentence: "You logged a headache..."
const LOGGED = {
  Cramps: 'cramps', Headache: 'a headache', Backache: 'backache',
  'Breast tenderness': 'breast tenderness', 'Joint pain': 'joint pain',
  'Ovulation pain': 'ovulation pain', Happy: 'feeling happy',
  Calm: 'feeling calm', Irritable: 'feeling irritable',
  Anxious: 'feeling anxious', Sad: 'feeling sad',
  Sensitive: 'feeling sensitive', Confident: 'feeling confident',
  Bloating: 'bloating', Acne: 'spots', Nausea: 'feeling sick',
  Fatigue: 'tiredness', Dizziness: 'dizziness', 'Hot flush': 'a hot flush',
  'Food cravings': 'food cravings', Constipation: 'constipation',
  Diarrhoea: 'diarrhoea', 'Appetite up': 'a bigger appetite',
  'Appetite down': 'a smaller appetite', Dry: 'dryness',
  Sticky: 'sticky discharge', Creamy: 'creamy discharge',
  'Egg white': 'egg-white discharge', Watery: 'watery discharge',
  'Low drive': 'low desire', 'heavy flow': 'a heavy flow',
  'low energy': 'low energy',
};
// For patterns: "You logged headaches around..."
const PATTERN = {
  ...LOGGED,
  Headache: 'headaches', 'Hot flush': 'hot flushes',
};
const WINDOW = {
  menstrual: 'your period',
  follicular: 'the days after your period',
  ovulatory: 'the middle of your cycle',
  luteal: 'the days before your period',
};
const WEEKDAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const MONTHS = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
  'September', 'October', 'November', 'December',
];

class NoteRefused extends Error {}
const refuse = (why) => {
  throw new NoteRefused(why);
};

// ---- Reading what her phone sent -------------------------------------------

const ISO_DAY = /^\d{4}-\d{2}-\d{2}$/;
function day(value) {
  if (typeof value !== 'string' || !ISO_DAY.test(value)) refuse('bad date');
  const date = new Date(`${value}T00:00:00Z`);
  if (Number.isNaN(date.getTime())) refuse('bad date');
  return date;
}
function int(value, min, max) {
  if (!Number.isInteger(value) || value < min || value > max) refuse('bad number');
  return value;
}
function num(value, min, max) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < min || value > max) {
    refuse('bad number');
  }
  return value;
}
function oneOf(value, allowed) {
  if (!allowed.includes(value)) refuse('unknown value');
  return value;
}
const daysBetween = (from, to) => Math.round((to - from) / 86400000);

// Each opening line's values, checked against what that line may hold.
const FACT_FIELDS = {
  P01: { symptom: 'symptom', consecutive_logged_days: [2, 90] },
  P02: { symptom: 'symptom', cycle_window: 'window', matching_cycles: [1, 24], eligible_cycles: [1, 24] },
  P03: { symptom: 'symptom' },
  P04: { symptom: 'symptom' },
  P05: { period_day: [1, 20], completed_period_count: [1, 24], min_days: [1, 20], max_days: [1, 20] },
  P06: { friendly_date: 'date', days_from_today: [0, 7] },
  P07: { days_past_estimate: [1, 120] },
  P08: { relative_to_estimate: [-60, 60] },
  P09: { last_cycle_days: [10, 120], completed_cycles: [1, 24], median_cycle_days: 'number' },
  P10: { sleep_hours: 'hours' },
  P11: { energy_rating: [1, 5] },
  P12: { start_date: 'date', end_date: 'date' },
};

function readFact(fact) {
  if (typeof fact !== 'object' || fact === null) refuse('bad fact');
  const fields = FACT_FIELDS[fact.id];
  if (!fields) refuse('unknown fact');
  const values = fact.values ?? {};
  if (typeof values !== 'object' || values === null) refuse('bad fact');
  const out = {};
  for (const [key, value] of Object.entries(values)) {
    const kind = fields[key];
    if (!kind) refuse('unknown fact field');
    if (Array.isArray(kind)) out[key] = int(value, kind[0], kind[1]);
    else if (kind === 'symptom') out[key] = oneOf(value, [...SYMPTOMS, ...OTHER]);
    else if (kind === 'window') out[key] = oneOf(value, Object.keys(WINDOW));
    else if (kind === 'date') out[key] = day(value);
    else if (kind === 'number') out[key] = num(value, 10, 120);
    else if (kind === 'hours') out[key] = num(value, 0, 24);
  }
  for (const key of Object.keys(fields)) {
    if (!(key in out) && key !== 'days_from_today') refuse('missing fact field');
  }
  return { id: fact.id, values: out };
}

/// Checks everything her phone sent; anything unexpected is refused.
function readRequest(body) {
  const cardId = String(body.card ?? '');
  const card = CARDS.get(cardId);
  if (!card || FIXED_ONLY.has(cardId)) refuse('card not for AI');
  const wordingId = String(body.wording ?? cardId);
  const wording = CARDS.get(wordingId);
  if (!wording || (wordingId !== cardId && wording.variant_of !== cardId)) refuse('bad wording');

  const language = oneOf(body.language ?? 'en', LANGUAGES);
  let shown = { title: wording.title, body: wording.body };
  if (language === 'ro') {
    const ro = RO?.cards?.[wordingId];
    if (!ro) refuse('no Romanian card');
    shown = { title: ro.title, body: ro.body };
  }

  const today = day(body.today);
  const goal = oneOf(body.goal, ['track', 'conceive']);
  const fertility = body.fertility === true;
  const logged = Array.isArray(body.logged) ? body.logged : refuse('bad log');
  if (logged.length > 12) refuse('bad log');
  for (const item of logged) oneOf(item, [...SYMPTOMS, ...FLOWS.map((f) => `${f} flow`)]);
  const facts = Array.isArray(body.facts) ? body.facts : refuse('bad facts');
  if (facts.length > 8) refuse('bad facts');
  return {
    cardId,
    language,
    card: { id: cardId, ...shown },
    today,
    goal,
    fertility,
    logged,
    facts: facts.map(readFact),
  };
}

// ---- Her day in words, from the reviewed opening lines ---------------------

const plural = (text) => text.replace(/\b1 days\b/g, '1 day').replace(/\b1 hours\b/g, '1 hour');
const formatNumber = (n) => (Number.isInteger(n) ? String(n) : n.toFixed(1));
const longDate = (d) => `${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]}`;

function friendly(date, today) {
  const ahead = daysBetween(today, date);
  if (ahead === 0) return 'today';
  if (ahead === 1) return 'tomorrow';
  return `on ${WEEKDAYS[date.getUTCDay()]}, ${longDate(date)}`;
}

function relative(days) {
  if (days === 0) return 'on the day it was estimated';
  return `${Math.abs(days)} days ${days < 0 ? 'earlier' : 'later'} than estimated`;
}

function factSentence({ id, values }, today) {
  let template = OPENINGS.get(id);
  if (id === 'P05' && values.min_days === values.max_days) {
    template = 'Day {period_day} of your period. Your {completed_period_count} recorded periods have each lasted {min_days} days.';
  }
  let text = template;
  for (const [key, value] of Object.entries(values)) {
    let shown;
    if (key === 'symptom') shown = (id === 'P02' ? PATTERN : LOGGED)[value] ?? value.toLowerCase();
    else if (key === 'cycle_window') shown = WINDOW[value];
    else if (key === 'friendly_date') shown = friendly(value, today);
    else if (value instanceof Date) shown = longDate(value);
    else if (key === 'relative_to_estimate') shown = relative(value);
    else shown = formatNumber(value);
    text = text.replaceAll(`{${key}}`, shown);
  }
  return plural(text);
}

// ---- The same in Romanian, from the Romanian pack ---------------------------

// "1 zi" for "1 zile", and "de" from 20 on ("21 de zile"), as in the app.
function roCounts(text) {
  const one = { zile: 'zi', ore: 'oră', cicluri: 'ciclu', 'menstruații': 'menstruație' };
  return text.replace(/(?<![\d.,])(\d+) (zile|ore|cicluri|menstruații)(?![\p{L}])/gu, (_, digits, noun) => {
    const n = Number(digits);
    if (n === 1) return `1 ${one[noun]}`;
    const rest = n % 100;
    return `${n} ${rest >= 20 || (rest === 0 && n !== 0) ? 'de ' : ''}${noun}`;
  });
}

const RO_FLOWS = {
  'spotting flow': 'pătare', 'light flow': 'flux slab',
  'medium flow': 'flux mediu', 'heavy flow': 'flux abundent',
};
// JavaScript's getUTCDay() counts from Sunday; the pack lists Monday first.
const roWeekday = (d) => RO.weekdaysMondayFirst[(d.getUTCDay() + 6) % 7];
const roLongDate = (d) => `${d.getUTCDate()} ${RO.months[d.getUTCMonth()]}`;
const roPhrase = (map, value) => RO[map][value] ?? value.toLowerCase();

function roFriendly(date, today) {
  const ahead = daysBetween(today, date);
  if (ahead === 0) return RO.ui.today;
  if (ahead === 1) return RO.ui.tomorrow;
  return `${RO.ui.onDay.replace('{day}', roWeekday(date))}, ${roLongDate(date)}`;
}

function roRelative(days) {
  if (days === 0) return RO.ui.onEstimate;
  return RO.ui[days < 0 ? 'earlierThanEstimate' : 'laterThanEstimate'].replace('{n}', String(Math.abs(days)));
}

function roFactSentence({ id, values }, today) {
  let template = RO.openings[id];
  if (id === 'P05' && values.min_days === values.max_days) template = RO.openings.P05_same ?? template;
  let text = template;
  for (const [key, value] of Object.entries(values)) {
    let shown;
    if (key === 'symptom') shown = roPhrase(id === 'P02' ? 'patternPhrase' : 'loggedPhrase', value);
    else if (key === 'cycle_window') shown = RO.windowPhrase[value];
    else if (key === 'friendly_date') shown = roFriendly(value, today);
    else if (value instanceof Date) shown = roLongDate(value);
    else if (key === 'relative_to_estimate') shown = roRelative(value);
    else shown = formatNumber(value).replace('.', ',');
    text = text.replaceAll(`{${key}}`, shown);
  }
  return roCounts(text);
}

function roSummaryText(request) {
  const lines = [
    request.goal === 'conceive' ? 'Încearcă să rămână însărcinată.' : 'Își urmărește ciclul menstrual.',
  ];
  if (request.fertility) lines.push('Are informațiile despre fertilitate pornite.');
  if (request.logged.length > 0) {
    const items = request.logged.map((item) => RO_FLOWS[item] ?? roPhrase('loggedPhrase', item));
    lines.push(`Azi a înregistrat: ${items.join(', ')}.`);
  }
  for (const fact of request.facts) lines.push(roFactSentence(fact, request.today));
  return lines.map((line) => `- ${line}`).join('\n');
}

function summaryText(request) {
  if (request.language === 'ro') return roSummaryText(request);
  const lines = [
    request.goal === 'conceive' ? 'She is trying to conceive.' : 'She is tracking her cycle.',
  ];
  if (request.fertility) lines.push('She has fertility information turned on.');
  if (request.logged.length > 0) {
    const items = request.logged.map((item) =>
      item.endsWith(' flow') ? `a ${item}` : LOGGED[item] ?? item.toLowerCase());
    lines.push(`Today she logged: ${items.join(', ')}.`);
  }
  for (const fact of request.facts) lines.push(factSentence(fact, request.today));
  return lines.map((line) => `- ${line}`).join('\n');
}

// ---- Asking the model ------------------------------------------------------

const NOTE_SYSTEM = `You write the short daily note that MoonCycle, a UK period-tracking app, shows a woman on her Today screen.

You receive two things. First, facts about her day, worked out on her phone from what she logged and already worded; they speak to her as "you". Second, one reviewed card: text checked against NHS guidance and chosen for her by the app's rules. Your note says what the card says, around her day, so it reads as written for her rather than as a leaflet.

What the note may contain:
- What the card says, in your own words. Keep its meaning; do not add to it or make it stronger or more certain.
- Her facts, only where they add meaning: a pattern in her history, an estimate, how often she logged something. She already knows what she logged today and which day of her cycle it is, so do not list those back to her or open with them. Leave out any number that does not help her.
- Dates and estimates stay estimates: say "estimated", never that something will happen.

Open with what matters most for her today, and vary how you begin: she may read a note like this every day.

What the note must leave out:
- Any medical fact, cause, number, tip or reassurance that is not in the card, even if it is true. If the card does not say it, leave it out.
- Any guess about why she feels as she does, and any condition name the card does not use.
- Anything that turns her entries into claims about her body. Entries are entries: "you logged a headache on 3 days in a row" says what she logged; "this headache has lasted three days" claims more. Do not raise how strong something was unless she logged it, do not say what something adds up to or builds into, and do not promise how a tip will make her feel.
- Pregnancy, fertility and ovulation, unless the card or her facts raise them. If she is trying to conceive and her period has started, stay neutral and practical: no disappointment and nothing like "not this month".
- Advice to see a GP, a pharmacist or anyone else, urgent-care advice and phone numbers. The app shows its own GP and urgent-help text under your note. The one exception: when the card's own text gives that advice, keep it as the card puts it.
- Advice about anything else she logged that the card does not cover.
- Her partner or anyone else, and anything about sex beyond what the card says.
- Medicine names and doses.

Style: UK English. Warm, plain and calm, like a knowledgeable friend rather than a doctor or a cheerleader. Two or three short sentences, at most 55 words. Speak to her as "you". No greeting, no emoji, no exclamation marks, and no questions for her to answer.

Return the note.`;

// Added to both instructions when her phone is set to Romanian.
const ROMANIAN = `

Language: the card and the facts are in Romanian, and the note must be in Romanian too. Address her informally as "tu", with correct diacritics (ș and ț with a comma below). Keep the card's own Romanian terms. These instructions were written for the UK: read "GP" as "medicul de familie"; in Romania the emergency number is 112, and it still stays out of the note. Ignore "UK English" in the style rule; everything else applies as written, including at most 55 words.`;

const NOTE_SCHEMA = {
  type: 'object',
  properties: { message: { type: 'string' } },
  required: ['message'],
  additionalProperties: false,
};

const REVIEW_SYSTEM = `You check a short note written for a UK period-tracking app against its only allowed sources: a reviewed card and facts about her day.

Find, and quote word for word from the note:
- unsupported: any statement the sources do not support, such as a fact, cause, number, tip, reassurance or certainty that is not in the card or the facts, or that is stated more strongly than the card states it. This includes turning her logged entries into claims about her body (a symptom lasting, continuing, building up, adding up or being strong, or being new to her rather than new to her log) and promising what a tip will do for her.
- diagnosis_or_cause: any diagnosis, condition name not used in the card, or guess at why she feels as she does.
- other_issues: anything else a careful health app would not say: alarming or judgemental wording, pregnancy raised when the sources do not raise it, disappointment about a period while trying to conceive, promises about what her body will do, assumptions about her age or circumstances that the sources do not state, advice about something she logged that the card does not cover, or advice to contact services that the card itself does not give.

Leave a list empty when there is nothing to quote. The verdict is "pass" only when all three lists are empty.`;

const REVIEW_SCHEMA = {
  type: 'object',
  properties: {
    verdict: { type: 'string', enum: ['pass', 'fail'] },
    unsupported: { type: 'array', items: { type: 'string' } },
    diagnosis_or_cause: { type: 'array', items: { type: 'string' } },
    other_issues: { type: 'array', items: { type: 'string' } },
  },
  required: ['verdict', 'unsupported', 'diagnosis_or_cause', 'other_issues'],
  additionalProperties: false,
};

let client;
async function anthropic() {
  if (!client) {
    const { default: Anthropic } = await import('@anthropic-ai/sdk');
    // Reads ANTHROPIC_API_KEY from the server's environment file.
    client = new Anthropic({ timeout: 60_000, maxRetries: 1 });
  }
  return client;
}

/// One request with a fixed answer shape. Null when declined or cut off.
async function ask(system, user, schema) {
  const api = await anthropic();
  const response = await api.beta.messages.create({
    model: MODEL,
    max_tokens: 16000,
    inference_geo: GEO,
    // If a safety check declines the request, Anthropic's recommended
    // fallback model answers it instead.
    betas: ['server-side-fallback-2026-07-01'],
    fallbacks: 'default',
    system: [{ type: 'text', text: system, cache_control: { type: 'ephemeral' } }],
    messages: [{ role: 'user', content: user }],
    output_config: { effort: EFFORT, format: { type: 'json_schema', schema } },
  });
  if (response.stop_reason !== 'end_turn') return null;
  const text = response.content
    .filter((block) => block.type === 'text')
    .map((block) => block.text)
    .join('');
  return JSON.parse(text);
}

// ---- Checks that do not depend on the model --------------------------------

const DIAGNOSIS = [
  'diagnos', 'disorder', 'syndrome', 'condition', 'pmdd', 'pms',
  'endometriosis', 'pcos', 'fibroid', 'anaemi', 'anemi', 'iron', 'deficien',
  'infection', 'depress', 'migraine', 'menopaus', 'perimenopaus', 'hormon',
];
const FERTILITY_WORDS = ['pregnan', 'conceiv', 'ovulat', 'fertil', 'contracept'];
const MEDICINE = [
  'ibuprofen', 'paracetamol', 'aspirin', 'naproxen', 'codeine', 'mefenamic',
  'tablet', 'pill', 'painkiller', 'pain relief', 'dose', 'medicine', 'medication',
];
const SERVICES = ['gp', 'doctor', 'nurse', 'pharmacist', 'pharmacy', 'clinic', 'nhs', 'hospital'];
const OVERSTATEMENT = [
  'lasted', 'lasting', 'continu', 'persist', 'adds up', 'add up', 'build up',
  'builds up', 'building up', 'catch up', "you'll feel", 'help you feel',
  'make you feel', 'feel better', 'feel more', 'strong', 'severe', 'intense',
];

const escapeRegex = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const hasStem = (text, stem) => new RegExp(`\\b${escapeRegex(stem)}`, 'i').test(text);
const hasNumber = (text, n) => new RegExp(`(^|[^\\d.])${escapeRegex(n)}(?![\\d])`).test(text);

/// The rules every note must pass. Returns what failed, empty when none.
/// A word is allowed when the sources use it; words that overstate her
/// entries only when the card itself does. A wrongly failed note is safe:
/// her phone shows the card instead.
function failedChecks(message, sources, conceiving, cardText = sources) {
  const lower = message.toLowerCase();
  const failed = [];
  const fresh = (stems, allowedIn = sources) =>
    stems.filter((s) => hasStem(lower, s) && !hasStem(allowedIn, s));
  const words = message.trim().split(/\s+/).filter(Boolean).length;

  if (words === 0 || words > 60) failed.push('length');
  if (/\b(999|111|A&E|ambulance|emergency)\b/i.test(message)) failed.push('urgent care');
  for (const [name, stems] of [
    ['services', SERVICES],
    ['diagnosis', DIAGNOSIS],
    ['fertility', FERTILITY_WORDS],
    ['medicine', MEDICINE],
  ]) {
    if (fresh(stems).length > 0) failed.push(name);
  }
  if (fresh(OVERSTATEMENT, cardText).length > 0) failed.push('overstatement');
  const numbers = (message.match(/\d+(?:\.\d+)?/g) ?? []).filter((n) => !hasNumber(sources, n));
  if (numbers.length > 0) failed.push('numbers');
  if (/\b(definitely|certainly|guarantee\w*|always|never|will (start|arrive|come|begin|be))\b/i.test(message)) {
    failed.push('certainty');
  }
  if (conceiving && /not this (month|time|cycle)|unfortunately|sorry|disappoint\w*|better luck|next time/i.test(message)) {
    failed.push('disappointment');
  }
  if (/\b(partner|boyfriend|husband|girlfriend|wife)\b/i.test(message)) failed.push('people');
  if (/\p{Extended_Pictographic}/u.test(message) || /[!?]/.test(message)) failed.push('style');
  const opener = message.split(/(?<=[.!?])\s/)[0];
  if (
    /^\s*(you've logged|you logged|you have logged|you're on day|you are on day|it's day|today is day|on day)\b/i.test(opener) &&
    !/\b(of your last|recorded cycles|cycles)\b/i.test(opener)
  ) {
    failed.push('recap opening');
  }
  return failed;
}

// The same rules for a Romanian note. Word starts are matched with Unicode
// letters, since \b does not see ș, ț, ă, â or î as letters.
const DIAGNOSIS_RO = [
  'diagnost', 'tulburar', 'tulburăr', 'sindrom', 'afecțiun', 'boal', 'pmdd',
  'spm', 'endometrioz', 'sop', 'polichist', 'fibrom', 'anemi', 'fierul', 'de fier', 'deficit',
  'carenț', 'infecți', 'depresi', 'migren', 'menopauz', 'perimenopauz', 'hormon',
];
const FERTILITY_RO = ['sarcin', 'însărcinat', 'gravid', 'concep', 'ovulați', 'ovulat', 'fertil', 'contracep', 'anticoncep'];
const MEDICINE_RO = [
  'ibuprofen', 'paracetamol', 'aspirin', 'naproxen', 'codein', 'tablet',
  'pastil', 'comprimat', 'analgezic', 'calmant', 'antiinflamato', 'doz',
  'medicament',
];
const SERVICES_RO = ['medic', 'doctor', 'asistent', 'farmac', 'clinic', 'cabinet', 'spital', 'nhs', 'urgenț'];
const OVERSTATEMENT_RO = [
  'a durat', 'durează', 'continu', 'persist', 'se adun', 'se acumul',
  'te vei simți', 'te va face', 'să te simți mai', 'te simți mai bine',
  'puternic', 'sever', 'intens', 'recuper',
];

const hasStemRo = (text, stem) => new RegExp(`(?<![\\p{L}\\p{N}])${escapeRegex(stem)}`, 'iu').test(text);

function failedChecksRo(message, sources, conceiving, cardText = sources) {
  const lower = message.toLowerCase();
  const failed = [];
  const fresh = (stems, allowedIn = sources) =>
    stems.filter((s) => hasStemRo(lower, s) && !hasStemRo(allowedIn, s));
  const words = message.trim().split(/\s+/).filter(Boolean).length;

  // Romanian takes a few more words than English for the same note.
  if (words === 0 || words > 70) failed.push('length');
  if (/(?<![\p{L}\p{N}])(112|999|111|ambulanț\p{L}*|urgenț\p{L}*)/iu.test(message)) failed.push('urgent care');
  for (const [name, stems] of [
    ['services', SERVICES_RO],
    ['diagnosis', DIAGNOSIS_RO],
    ['fertility', FERTILITY_RO],
    ['medicine', MEDICINE_RO],
  ]) {
    if (fresh(stems).length > 0) failed.push(name);
  }
  if (fresh(OVERSTATEMENT_RO, cardText).length > 0) failed.push('overstatement');
  const numbers = (message.match(/\d+(?:[.,]\d+)?/g) ?? []).filter((n) => !hasNumber(sources, n));
  if (numbers.length > 0) failed.push('numbers');
  if (/(?<![\p{L}])(cu siguranță|garant\p{L}*|mereu|întotdeauna|niciodată|va începe|va veni|va apărea|va fi)(?![\p{L}])/iu.test(message)) {
    failed.push('certainty');
  }
  if (conceiving && /nu (luna|ciclul) (asta|acesta)|din păcate|îmi pare rău|dezamăg\p{L}*|data viitoare|mai mult noroc/iu.test(message)) {
    failed.push('disappointment');
  }
  if (/(?<![\p{L}])(partener\p{L}*|iubit\p{L}*|soț\p{L}*|soți\p{L}*|prieten\p{L}*)(?![\p{L}])/iu.test(message)) failed.push('people');
  if (/\p{Extended_Pictographic}/u.test(message) || /[!?]/.test(message)) failed.push('style');
  const opener = message.split(/(?<=[.!?])\s/)[0];
  if (
    /^\s*(ai notat|ai înregistrat|ești în ziua|e ziua|este ziua|azi e ziua|astăzi este ziua|în ziua)(?![\p{L}])/iu.test(opener) &&
    !/(din ultimele|cicluri înregistrate|cicluri)/iu.test(opener)
  ) {
    failed.push('recap opening');
  }
  return failed;
}

// ---- The whole thing -------------------------------------------------------

/// The note for her card today, or null: her phone then shows the card.
async function writeNote(body) {
  let request;
  try {
    request = readRequest(body);
  } catch (error) {
    if (error instanceof NoteRefused) return { note: null, reason: error.message };
    throw error;
  }
  const summary = summaryText(request);
  const cardText = `[${request.card.id}] ${request.card.title}\n${request.card.body}`;
  const user = `Facts about her day:\n${summary}\n\nThe reviewed card chosen for her today:\n${cardText}`;

  const romanian = request.language === 'ro';
  const written = await ask(romanian ? NOTE_SYSTEM + ROMANIAN : NOTE_SYSTEM, user, NOTE_SCHEMA);
  const message = typeof written?.message === 'string' ? written.message.trim() : '';
  if (!message) return { note: null, reason: 'no note' };

  const card = `${request.card.title}\n${request.card.body}`.toLowerCase();
  const sources = `${card}\n${summary.toLowerCase()}`;
  const check = romanian ? failedChecksRo : failedChecks;
  const failed = check(message, sources, request.goal === 'conceive', card);
  if (failed.length > 0) return { note: null, reason: `checks: ${failed.join(', ')}` };

  if (SECOND_READING) {
    const review = await ask(
      romanian ? REVIEW_SYSTEM + ROMANIAN : REVIEW_SYSTEM,
      `Sources.\n\nFacts about her day:\n${summary}\n\nReviewed card:\n${cardText}\n\nThe note to check:\n${message}`,
      REVIEW_SCHEMA,
    );
    if (review?.verdict !== 'pass') return { note: null, reason: 'second reading' };
  }
  return { note: message };
}

module.exports = {
  writeNote,
  FIXED_ONLY,
  // For tests: no model involved.
  readRequest,
  summaryText,
  failedChecks,
  failedChecksRo,
};
