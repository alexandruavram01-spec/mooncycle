// Drafts partner tips with Claude, then has a second pass check every line
// against the content rules before a person ever sees it.
//
// Nothing about any user is sent: only the phase, the tone, and the existing
// lines to avoid repeating. Approval by a person happens afterwards, in the
// app's tip library screen.

const MODEL = 'claude-opus-5-5';
const MAX_TIP_LENGTH = 110;

const PHASES = {
  menstrual: 'her period. Energy is often low; cramps and tiredness are common.',
  follicular: 'the days after her period. Energy and mood often rise.',
  ovulatory: 'the mid-cycle peak. Often her most energetic, sociable days.',
  luteal:
    'the wind-down before her period. Energy often dips, and patience for stress and noise can run lower.',
};

const TONES = {
  straight: 'practical and warm, with no jokes',
  light: 'practical, with a light touch of humour',
  playful: 'funny first and still useful, teasing him affectionately',
};

const RULES = `- If there is a joke, it is on him or the situation. Never on her, her body, her appetite, her mood or her cycle.
- Never call her hormonal, moody, emotional, crazy, dramatic or difficult. No "time of the month" and no PMS jokes.
- Nothing about sex, fertility, ovulation, pregnancy or contraception.
- No medical advice, no diagnosis, no medicines or supplements.
- Never claim to know how she feels. Use "may" and "often", never "she is".
- One concrete, kind thing he can do today.
- At most ${MAX_TIP_LENGTH} characters, plain words, British spelling, no emoji, no hashtags.
- No alcohol, and no assumptions about money, religion or children.`;

// Checked in code as well as by the reviewer: a line containing any of these
// fails, whatever the model said.
const BLOCKED =
  /hormon|\bpms\b|moody|crazy|emotional|dramatic|time of the month|\bsex|fertil|ovulat|pregnan|contracep|\bnag/i;

const DRAFT_SYSTEM = `You write one-line tips for MoonCycle. The app shows a partner where the person he supports is in her menstrual cycle, as a gentle forecast, and gives him one thing to do today.

Address him as "you" and refer to her as "she" or "her".

Every line must follow these rules:
${RULES}`;

const REVIEW_SYSTEM = `You check one-line tips for partners in a menstrual cycle app before a human editor sees them.

Fail a line if it breaks any of these rules:
${RULES}

Also fail a line if she would feel mocked, watched or pressured reading it over his shoulder, or if the humour tips into meanness. When in doubt, fail it, and say why in a few words.`;

const DRAFT_SCHEMA = {
  type: 'object',
  properties: { lines: { type: 'array', items: { type: 'string' } } },
  required: ['lines'],
  additionalProperties: false,
};

const REVIEW_SCHEMA = {
  type: 'object',
  properties: {
    reviews: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          index: { type: 'integer' },
          pass: { type: 'boolean' },
          reason: { type: 'string' },
        },
        required: ['index', 'pass', 'reason'],
        additionalProperties: false,
      },
    },
  },
  required: ['reviews'],
  additionalProperties: false,
};

let sdk;
async function anthropicClient() {
  if (!process.env.ANTHROPIC_API_KEY) {
    throw new Error('The AI key is not set on the server yet.');
  }
  // The SDK ships as an ES module; a dynamic import loads it from this
  // CommonJS file.
  sdk ??= import('@anthropic-ai/sdk').then(({ default: Anthropic }) => ({
    Anthropic,
    client: new Anthropic(),
  }));
  return sdk;
}

async function ask(system, user, schema) {
  const { Anthropic, client } = await anthropicClient();
  let response;
  try {
    response = await client.beta.messages.create({
      model: MODEL,
      max_tokens: 16000,
      // If a safety classifier declines, the API re-runs the request on a
      // recommended fallback model instead of returning the refusal.
      betas: ['server-side-fallback-2026-07-01'],
      fallbacks: 'default',
      // Short lines and a pass/fail check don't need deep thinking, and the
      // editor is waiting for the answer.
      output_config: {
        effort: 'low',
        format: { type: 'json_schema', schema },
      },
      system,
      messages: [{ role: 'user', content: user }],
    });
  } catch (err) {
    if (err instanceof Anthropic.AuthenticationError) {
      throw new Error('The AI key on the server is wrong.');
    }
    if (err instanceof Anthropic.RateLimitError) {
      throw new Error('The AI service is busy. Try again in a minute.');
    }
    if (err instanceof Anthropic.APIError) {
      throw new Error(`The AI service answered with an error (${err.status}).`);
    }
    throw err;
  }

  if (response.stop_reason === 'refusal') throw new Error('The AI declined this request.');
  if (response.stop_reason === 'max_tokens') throw new Error('The AI answer was cut off.');
  const text = response.content
    .filter((block) => block.type === 'text')
    .map((block) => block.text)
    .join('');
  return JSON.parse(text);
}

// Returns [{ text, pass, reason }]. A line fails if it is too long, contains
// a blocked word, was failed by the reviewer, or was skipped by it.
async function draftTips({ phase, tone, count, avoid }) {
  const existing = avoid.length ? avoid.map((t) => `- ${t}`).join('\n') : '- (none yet)';
  const { lines } = await ask(
    DRAFT_SYSTEM,
    `Phase: ${PHASES[phase]}\nTone: ${TONES[tone]}.\n\nWrite ${count} new tips. Each one must differ from the others and from these existing tips:\n${existing}`,
    DRAFT_SCHEMA,
  );

  const drafts = [...new Set(lines.map((l) => String(l).trim()).filter(Boolean))].slice(0, count);
  if (drafts.length === 0) return [];

  const { reviews } = await ask(
    REVIEW_SYSTEM,
    `Phase: ${PHASES[phase]}\nTone: ${TONES[tone]}.\n\nCheck each tip. Answer once per tip, using its number as the index.\n\n${drafts
      .map((t, i) => `${i}. ${t}`)
      .join('\n')}`,
    REVIEW_SCHEMA,
  );
  const verdicts = new Map(reviews.map((r) => [r.index, r]));

  return drafts.map((text, i) => {
    if (text.length > MAX_TIP_LENGTH) {
      return { text, pass: false, reason: `Longer than ${MAX_TIP_LENGTH} characters.` };
    }
    if (BLOCKED.test(text)) return { text, pass: false, reason: 'Contains a blocked word.' };
    const review = verdicts.get(i);
    if (!review) return { text, pass: false, reason: 'Not checked by the reviewer.' };
    return { text, pass: review.pass, reason: review.pass ? null : review.reason };
  });
}

module.exports = { draftTips, MAX_TIP_LENGTH };
