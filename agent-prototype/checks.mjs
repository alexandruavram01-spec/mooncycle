// Checks run on every note without asking the model. A term the card or
// her summary already uses is allowed; anything else is flagged for review.

const DIAGNOSIS = [
  'diagnos', 'disorder', 'syndrome', 'condition', 'pmdd', 'pms',
  'endometriosis', 'pcos', 'fibroid', 'anaemi', 'anemi', 'iron',
  'deficien', 'infection', 'depress', 'migraine', 'menopaus', 'hormon',
];
const FERTILITY = ['pregnan', 'conceiv', 'ovulat', 'fertil', 'contracept'];
const MEDICINE = [
  'ibuprofen', 'paracetamol', 'aspirin', 'naproxen', 'codeine', 'mefenamic',
  'tablet', 'pill', 'painkiller', 'pain relief', 'dose', 'medicine',
  'medication',
];
// Entries turned into claims about her body, or promised results of a tip.
const OVERSTATEMENT = [
  'lasted', 'lasting', 'continu', 'persist', 'adds up', 'add up',
  'build up', 'builds up', 'building up', 'catch up', "you'll feel",
  'help you feel', 'make you feel', 'feel better', 'feel more',
];
const SERVICES = [
  'gp', 'doctor', 'nurse', 'pharmacist', 'pharmacy', 'clinic', 'nhs',
  'hospital',
];

const words = (text) => text.trim().split(/\s+/).filter(Boolean).length;
const escapeRegex = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

// The stem at the start of a word ("iron" but not "environment").
const hasStem = (text, stem) => new RegExp(`\\b${escapeRegex(stem)}`, 'i').test(text);

// The whole number ("2" but not the 2 in "27").
const hasNumber = (text, n) =>
  new RegExp(`(^|[^\\d.])${escapeRegex(n)}(?![\\d])`).test(text);

export function checkNote(note, scenario, cards) {
  const text = note.message;
  const lower = text.toLowerCase();
  const sources = [
    ...cards.map((card) => `${card.title}\n${card.body}`),
    JSON.stringify(scenario.summary),
  ]
    .join('\n')
    .toLowerCase();
  const results = [];
  const check = (name, ok, detail = '') => results.push({ name, ok, detail });
  const newTerms = (stems) =>
    stems.filter((stem) => hasStem(lower, stem) && !hasStem(sources, stem));

  // The instructions ask for 55; a long card may need a few more.
  const count = words(text);
  check('At most 60 words', count <= 60, `${count} words`);

  const overstated = newTerms(OVERSTATEMENT);
  check('Says what she logged, not more', overstated.length === 0, overstated.join(', '));

  // Opening with today's entries is a recap; opening with a pattern across
  // her cycles ("...in 3 of your last 4 recorded cycles") is the point.
  const opener = text.split(/(?<=[.!?])\s/)[0];
  const recap = opener.match(/^\s*(you've logged|you logged|you have logged|you're on day|you are on day|it's day|today is day|on day)\b/i);
  const pattern = /\b(of your last|recorded cycles|cycles)\b/i.test(opener);
  check('Does not open by repeating what she logged', !recap || pattern, recap?.[0] ?? '');

  const unknownCards = note.card_ids.filter(
    (id) => !cards.some((card) => card.id === id),
  );
  check('Uses only the card it was given', unknownCards.length === 0, unknownCards.join(', '));

  const urgent = text.match(/\b(999|111|A&E|ambulance|emergency)\b/gi) ?? [];
  check('No urgent-care advice (the app shows it separately)', urgent.length === 0, urgent.join(', '));

  const services = newTerms(SERVICES);
  check('No pointers to services (the app shows them separately)', services.length === 0, services.join(', '));

  const diagnosis = newTerms(DIAGNOSIS);
  check('No condition or cause the card does not name', diagnosis.length === 0, diagnosis.join(', '));

  const fertility = newTerms(FERTILITY);
  check('No pregnancy or fertility unless the sources raise it', fertility.length === 0, fertility.join(', '));

  const medicine = newTerms(MEDICINE);
  check('No medicine the card does not mention', medicine.length === 0, medicine.join(', '));

  const numbers = (text.match(/\d+(?:\.\d+)?/g) ?? []).filter(
    (n) => !hasNumber(sources, n),
  );
  check('Every number comes from the sources', numbers.length === 0, numbers.join(', '));

  const certainty =
    lower.match(/\b(definitely|certainly|guarantee\w*|always|never|will (start|arrive|come|begin|be))\b/g) ?? [];
  check('No certainty about her body or the estimates', certainty.length === 0, certainty.join(', '));

  if (scenario.summary.goal === 'trying to conceive') {
    const sad =
      lower.match(/not this (month|time|cycle)|unfortunately|sorry|disappoint\w*|better luck|next time/g) ?? [];
    check('No disappointment while trying to conceive', sad.length === 0, sad.join(', '));
  }

  const people = lower.match(/\b(partner|boyfriend|husband|girlfriend|wife)\b/g) ?? [];
  check('No partner or other people', people.length === 0, people.join(', '));

  const style = [
    ...(/\p{Extended_Pictographic}/u.test(text) ? ['emoji'] : []),
    ...(text.includes('!') ? ['exclamation mark'] : []),
    ...(text.includes('?') ? ['question'] : []),
  ];
  check('No emoji, exclamation marks or questions', style.length === 0, style.join(', '));

  return results;
}
