// Writes one sample AI note for every card that can get one, in Romanian (or
// English with `node sample-notes.js en`), from a made-up day. No user and no
// stored data: it only prints. Run on the server, where the API key is:
//
//   sudo bash -c 'set -a; . /etc/mooncycle-api.env; set +a; cd /opt/mooncycle-api && node sample-notes.js'
//
// Each card makes one or two calls to the AI (the note, then its check).

const fs = require('node:fs');
const path = require('node:path');
const notes = require('./her-notes');

const language = process.argv[2] === 'en' ? 'en' : 'ro';
const english = JSON.parse(fs.readFileSync(path.join(__dirname, 'her-cards.json'), 'utf8'));
const romanian = JSON.parse(fs.readFileSync(path.join(__dirname, 'her-cards-ro.json'), 'utf8'));
const cards = new Map(
  [...english.prior_base_cards, ...english.stage1_candidate_cards, ...english.stage1_alternate_wordings]
    .map((card) => [card.id, card]),
);

// What each card is about in her log, for the made-up day.
const LOGGED = {
  I01: 'Cramps', I01b: 'Cramps', I10: 'Ovulation pain', I12: 'Bloating', I12b: 'Bloating',
  I16: 'Headache', I16b: 'Headache', I17: 'Bloating', I17b: 'Bloating',
  I18: 'Breast tenderness', I19: 'Fatigue', I19b: 'Fatigue', I20: 'Sad', I20b: 'Anxious',
  L01: 'Cramps', L02: 'Backache', L03: 'Backache', L04: 'Joint pain', L05: 'Headache',
  L06: 'Happy', L09: 'Acne', L10: 'Nausea', L11: 'Dizziness', L13: 'Food cravings',
  L14: 'Constipation', L15: 'Diarrhoea', L16: 'Appetite down', L17: 'Creamy', L19: 'Low drive',
  C01: 'Cramps', C03: 'Headache', C04: 'Bloating', C05: 'Sad', C06: 'Fatigue', C08: 'Low drive',
};

function sampleRequest(wordingId) {
  const card = cards.get(wordingId);
  const base = card.variant_of || wordingId;
  const symptom = LOGGED[wordingId];
  const facts = [{ id: 'P06', values: { friendly_date: '2026-11-09', days_from_today: 5 } }];
  if (symptom) facts.unshift({ id: 'P02', values: { symptom, cycle_window: 'luteal', matching_cycles: 3, eligible_cycles: 4 } });
  return {
    card: base,
    wording: wordingId,
    today: '2026-11-04',
    language,
    goal: 'track',
    fertility: false,
    logged: symptom ? [symptom] : [],
    facts,
  };
}

async function main() {
  const ids = Object.keys(romanian.cards).filter((id) => {
    const card = cards.get(id);
    return card && !notes.FIXED_ONLY.has(card.variant_of || id);
  });
  console.log(`${ids.length} cards, language ${language}\n`);
  for (const id of ids) {
    const request = sampleRequest(id);
    const title = language === 'ro' ? romanian.cards[id].title : cards.get(id).title;
    let result;
    try {
      result = await notes.writeNote(request);
    } catch (error) {
      result = { note: null, reason: `error: ${error?.constructor?.name}` };
    }
    console.log(`=== ${id}: ${title}`);
    console.log(result.note ?? `(no note, the card shows instead: ${result.reason})`);
    console.log('');
  }
}

main();
