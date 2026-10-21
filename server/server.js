// MoonCycle API — accounts, partner pairing and redacted snapshot sync.
// Raw cycle logs never reach this server; see SNAPSHOT_FIELDS.
const http = require('node:http');
const crypto = require('node:crypto');
const { Pool } = require('pg');
const tipWriter = require('./tip-writer');
const TIP_SEED = require('./tips-seed.json');

const PORT = Number(process.env.PORT || 8787);
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const CODE_TTL_HOURS = 24;
const MAX_BODY_BYTES = 16 * 1024;
const MIN_PASSWORD_LENGTH = 8;
const MAX_PASSWORD_LENGTH = 200;
// No sentences: his app writes the card from these, in his own language.
const SNAPSHOT_FIELDS = [
  'v', 'dayOfCycle', 'phase', 'nextPhase', 'daysUntilNextPhase', 'jokes',
  'daysUntilNextPeriod', 'symptoms', 'energy',
];

// The one-tap messages between them. Only these codes are ever stored; the
// wording lives in the app, one file per language (lib/l10n/), so each of
// them reads it in their own. The lists must match. Each one shows for a day.
const codes = (prefix, from, to) =>
  Array.from({ length: to - from + 1 }, (_, i) => prefix + String(from + i).padStart(2, '0'));
// A15 and A29 were retired as duplicates; never reuse a code.
const ASKS = [...codes('A', 1, 14), ...codes('A', 16, 28)];
// 'special' is the reply written for her particular ask.
const REACTIONS = ['special', ...codes('R', 1, 8)];
const OFFERS = [...codes('O', 1, 12), ...codes('O', 17, 26)];
const OFFER_REPLIES = codes('O', 13, 16);
const INTERACTION_TTL_HOURS = 24;

// Codes of the daily tips (T01...) in the app's language files.
const TIP_CODE = /^T\d{2,3}$/;

// The current ask, his reply, his offer and her answer, each hidden once it
// is more than a day old. Column aliases are quoted to keep their case.
const FRESH = `now() - interval '${INTERACTION_TTL_HOURS} hours'`;
const FRESH_INTERACTIONS = `
  CASE WHEN ask_at > ${FRESH} THEN ask END AS "ask",
  CASE WHEN ask_at > ${FRESH} THEN ask_at END AS "askAt",
  CASE WHEN ask_at > ${FRESH} THEN reaction END AS "reaction",
  CASE WHEN offer_at > ${FRESH} THEN offer END AS "offer",
  CASE WHEN offer_at > ${FRESH} THEN offer_reply END AS "offerReply"`;

// The partner tip library. Lines are drafted by AI or seeded, and reach
// partners only once a person has approved them. A "not okay" from anyone
// pulls a line for everyone until it is looked at again.
const TIP_PHASES = ['menstrual', 'follicular', 'ovulatory', 'luteal'];
const TIP_TONES = ['straight', 'light', 'playful'];
const TIP_STATUSES = ['draft', 'approved', 'rejected', 'pulled'];
const TIP_FEEDBACK = ['like', 'not_funny', 'not_okay'];

// Accounts allowed to draft and approve tips, from the server's environment
// file. Never one of the test accounts: anyone can guess those.
const ADMIN_EMAILS = (process.env.ADMIN_EMAILS || '')
  .split(',')
  .map((e) => e.trim().toLowerCase())
  .filter(Boolean);

// TEST ACCOUNTS — REMOVE BEFORE REAL USERS. See BEFORE_LAUNCH.md.
// Created at start-up so the testers can sign in without registering. The
// names are not email addresses and the password is far below the minimum a
// real sign-up must meet, so anyone who guesses a name gets in.
const TEST_USERS = ['alex', 'sorana', 'robert', 'oana'];
const TEST_PASSWORD = '123456';

// The cost settings are stored inside each hash, so they can be raised later
// without locking out anyone whose password was hashed with the old ones.
const SCRYPT = { N: 32768, r: 8, p: 1 };
const SCRYPT_MAXMEM = 64 * 1024 * 1024;

// Connection details come from the PG* environment variables.
const pool = new Pool();

const SCHEMA = `
  -- The pre-accounts test build identified installs by device. Its tables
  -- cannot be reused, so they are dropped the first time this version starts.
  DO $$ BEGIN
    IF to_regclass('devices') IS NOT NULL THEN
      DROP TABLE IF EXISTS pairings;
      DROP TABLE devices;
    END IF;
  END $$;

  CREATE TABLE IF NOT EXISTS users (
    id            uuid PRIMARY KEY,
    email         text NOT NULL UNIQUE,
    password_hash text NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now()
  );
  CREATE TABLE IF NOT EXISTS sessions (
    token_hash  text PRIMARY KEY,
    user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at  timestamptz NOT NULL DEFAULT now()
  );
  CREATE TABLE IF NOT EXISTS pairings (
    owner_id        uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    code            text UNIQUE,
    code_expires_at timestamptz,
    partner_id      uuid REFERENCES users(id) ON DELETE SET NULL,
    snapshot        jsonb,
    snapshot_at     timestamptz
  );
  CREATE INDEX IF NOT EXISTS pairings_partner_idx ON pairings (partner_id);

  -- Proof of agreement: which version of the terms and privacy policy each
  -- person accepted, and when they gave explicit consent for health data
  -- (UK GDPR articles 7 and 9).
  ALTER TABLE users ADD COLUMN IF NOT EXISTS terms_version text;
  ALTER TABLE users ADD COLUMN IF NOT EXISTS terms_accepted_at timestamptz;
  ALTER TABLE users ADD COLUMN IF NOT EXISTS health_consent_at timestamptz;

  ALTER TABLE pairings ADD COLUMN IF NOT EXISTS ask text;
  ALTER TABLE pairings ADD COLUMN IF NOT EXISTS ask_at timestamptz;
  ALTER TABLE pairings ADD COLUMN IF NOT EXISTS reaction text;
  ALTER TABLE pairings ADD COLUMN IF NOT EXISTS reaction_at timestamptz;
  ALTER TABLE pairings ADD COLUMN IF NOT EXISTS offer text;
  ALTER TABLE pairings ADD COLUMN IF NOT EXISTS offer_at timestamptz;
  ALTER TABLE pairings ADD COLUMN IF NOT EXISTS offer_reply text;
  ALTER TABLE pairings ADD COLUMN IF NOT EXISTS offer_reply_at timestamptz;
  ALTER TABLE pairings ADD COLUMN IF NOT EXISTS partner_tone text;

  CREATE TABLE IF NOT EXISTS tip_lines (
    id          uuid PRIMARY KEY,
    phase       text NOT NULL,
    tone        text NOT NULL,
    text        text NOT NULL,
    status      text NOT NULL,
    source      text NOT NULL,
    review_note text,
    likes       integer NOT NULL DEFAULT 0,
    not_funny   integer NOT NULL DEFAULT 0,
    not_okay    integer NOT NULL DEFAULT 0,
    created_at  timestamptz NOT NULL DEFAULT now(),
    decided_at  timestamptz
  );
  CREATE TABLE IF NOT EXISTS tip_feedback (
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    line_id uuid NOT NULL REFERENCES tip_lines(id) ON DELETE CASCADE,
    kind    text NOT NULL,
    PRIMARY KEY (user_id, line_id)
  );

  -- Ratings of the daily tips built into the app, by code. One per person
  -- per tip; a new rating replaces the old.
  CREATE TABLE IF NOT EXISTS tip_ratings (
    user_id  uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    code     text NOT NULL,
    kind     text NOT NULL,
    rated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, code)
  );
  -- Tips someone flagged "not okay": nobody gets them until an editor puts
  -- them back.
  CREATE TABLE IF NOT EXISTS tip_pulled (
    code      text PRIMARY KEY,
    pulled_at timestamptz NOT NULL DEFAULT now()
  );
`;

const sha256 = (text) => crypto.createHash('sha256').update(text).digest('hex');
const newCode = () =>
  Array.from(crypto.randomBytes(8), (b) => CODE_ALPHABET[b % CODE_ALPHABET.length]).join('');
const clientIp = (req) => req.headers['x-forwarded-for'] || req.socket.remoteAddress;

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

function send(res, status, body) {
  res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(body));
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size <= MAX_BODY_BYTES) chunks.push(chunk);
    });
    req.on('error', reject);
    req.on('end', () => {
      if (size > MAX_BODY_BYTES) return reject(httpError(413, 'body too large'));
      try {
        const body = size === 0 ? {} : JSON.parse(Buffer.concat(chunks).toString('utf8'));
        if (typeof body !== 'object' || body === null || Array.isArray(body)) throw new Error();
        resolve(body);
      } catch {
        reject(httpError(400, 'invalid JSON body'));
      }
    });
  });
}

// ---- Passwords and sessions ------------------------------------------------

function scrypt(password, salt, params) {
  return new Promise((resolve, reject) => {
    crypto.scrypt(password, salt, 64, { ...params, maxmem: SCRYPT_MAXMEM }, (err, key) =>
      err ? reject(err) : resolve(key));
  });
}

async function hashPassword(password) {
  const salt = crypto.randomBytes(16);
  const key = await scrypt(password, salt, SCRYPT);
  return ['scrypt', SCRYPT.N, SCRYPT.r, SCRYPT.p, salt.toString('hex'), key.toString('hex')].join(':');
}

async function verifyPassword(password, stored) {
  const [scheme, N, r, p, salt, hash] = stored.split(':');
  if (scheme !== 'scrypt') return false;
  const key = await scrypt(password, Buffer.from(salt, 'hex'), { N: Number(N), r: Number(r), p: Number(p) });
  const expected = Buffer.from(hash, 'hex');
  return key.length === expected.length && crypto.timingSafeEqual(key, expected);
}

// Both boxes on the sign-up screen: the terms (with the privacy policy) and
// explicit consent for health data. Returns the terms version agreed to.
function readConsent(body) {
  const termsVersion = String(body.termsVersion || '').trim();
  if (!/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(termsVersion) || body.healthConsent !== true) {
    throw httpError(400, 'Please agree to the terms and give your consent to continue.');
  }
  return termsVersion;
}

// Sign-up insists on an email address. Sign-in takes whatever name the account
// has, which is what lets the test accounts in.
function readCredentials(body, { requireEmail }) {
  const email = String(body.email || '').trim().toLowerCase();
  const password = String(body.password || '');
  const valid = requireEmail ? /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) : email.length > 0;
  if (!valid || email.length > 254) throw httpError(400, 'Enter a valid email address.');
  return { email, password };
}

async function seedTestUsers() {
  for (const name of TEST_USERS) {
    const { rowCount } = await pool.query('SELECT 1 FROM users WHERE email = $1', [name]);
    if (rowCount > 0) continue;
    await pool.query(
      `INSERT INTO users (id, email, password_hash) VALUES ($1, $2, $3)
       ON CONFLICT (email) DO NOTHING`,
      [crypto.randomUUID(), name, await hashPassword(TEST_PASSWORD)],
    );
  }
}

// The lines the app shipped with, so they can be pulled and reviewed like any
// other. Only runs while the library is empty.
async function seedTips() {
  const { rows } = await pool.query('SELECT count(*)::int AS n FROM tip_lines');
  if (rows[0].n > 0) return;
  for (const line of TIP_SEED) {
    await pool.query(
      `INSERT INTO tip_lines (id, phase, tone, text, status, source, decided_at)
       VALUES ($1, $2, $3, $4, 'approved', 'seed', now())`,
      [crypto.randomUUID(), line.phase, line.tone, line.text],
    );
  }
}

async function requireAdmin(req) {
  const { userId } = await authenticate(req);
  const { rows } = await pool.query('SELECT email FROM users WHERE id = $1', [userId]);
  if (!ADMIN_EMAILS.includes(rows[0].email)) throw httpError(403, 'Only the editors can do that.');
  return userId;
}

function oneOf(value, allowed, message) {
  const key = String(value || '');
  if (!allowed.includes(key)) throw httpError(400, message);
  return key;
}

// A key from a fixed list, or null to clear.
function optionalKey(value, allowed) {
  if (value === null || value === undefined) return null;
  const key = String(value);
  if (!allowed.includes(key)) throw httpError(400, 'unknown choice');
  return key;
}

async function openSession(userId) {
  const token = crypto.randomBytes(32).toString('base64url');
  await pool.query('INSERT INTO sessions (token_hash, user_id) VALUES ($1, $2)', [sha256(token), userId]);
  return token;
}

async function authenticate(req) {
  const match = /^Bearer ([A-Za-z0-9_-]{20,})$/.exec(req.headers.authorization || '');
  if (!match) throw httpError(401, 'Sign in first.');
  const tokenHash = sha256(match[1]);
  const { rows } = await pool.query('SELECT user_id FROM sessions WHERE token_hash = $1', [tokenHash]);
  if (rows.length === 0) throw httpError(401, 'Sign in again.');
  return { userId: rows[0].user_id, tokenHash };
}

// Passwords and pairing codes are the only secrets guarding an account or a
// snapshot, so guessing either is throttled.
const attempts = new Map();
function throttle(key, limit, windowMs) {
  const now = Date.now();
  const entry = attempts.get(key);
  if (!entry || now > entry.resetAt) {
    attempts.set(key, { count: 1, resetAt: now + windowMs });
  } else if (++entry.count > limit) {
    throw httpError(429, 'Too many attempts. Try again later.');
  }
}
setInterval(() => {
  const now = Date.now();
  for (const [key, entry] of attempts) if (now > entry.resetAt) attempts.delete(key);
}, 60 * 1000).unref();

const routes = {
  'GET /api/health': async () => ({ ok: true }),

  // ---- Accounts ------------------------------------------------------------

  'POST /api/account': async (req) => {
    throttle(`signup:${clientIp(req)}`, 10, 60 * 60 * 1000);
    const body = await readJson(req);
    const { email, password } = readCredentials(body, { requireEmail: true });
    if (password.length < MIN_PASSWORD_LENGTH || password.length > MAX_PASSWORD_LENGTH) {
      throw httpError(400, `Use a password of at least ${MIN_PASSWORD_LENGTH} characters.`);
    }
    const termsVersion = readConsent(body);
    const id = crypto.randomUUID();
    const { rowCount } = await pool.query(
      `INSERT INTO users (id, email, password_hash, terms_version, terms_accepted_at, health_consent_at)
       VALUES ($1, $2, $3, $4, now(), now())
       ON CONFLICT (email) DO NOTHING`,
      [id, email, await hashPassword(password), termsVersion],
    );
    if (rowCount === 0) throw httpError(409, 'An account with this email already exists.');
    return { email, token: await openSession(id) };
  },

  'GET /api/account': async (req) => {
    const { userId } = await authenticate(req);
    const { rows } = await pool.query(
      'SELECT email, terms_version FROM users WHERE id = $1',
      [userId],
    );
    return {
      email: rows[0].email,
      admin: ADMIN_EMAILS.includes(rows[0].email),
      termsVersion: rows[0].terms_version,
    };
  },

  // Agreeing to new terms, or for accounts made before consent was recorded.
  'POST /api/account/consent': async (req) => {
    const { userId } = await authenticate(req);
    const termsVersion = readConsent(await readJson(req));
    await pool.query(
      `UPDATE users SET terms_version = $2, terms_accepted_at = now(), health_consent_at = now()
        WHERE id = $1`,
      [userId, termsVersion],
    );
    return { ok: true };
  },

  // ---- Daily tips ----------------------------------------------------------
  // The tips are written into the app, per language. The server only keeps
  // ratings by code, and which tips are pulled.

  'GET /api/tips/pulled': async (req) => {
    await authenticate(req);
    const { rows } = await pool.query('SELECT code FROM tip_pulled ORDER BY code');
    return { codes: rows.map((r) => r.code) };
  },

  // Anyone who sees a tip can rate it once (a new rating replaces the old).
  // "not_okay" pulls the tip for everyone straight away.
  'POST /api/tips/rating': async (req) => {
    const { userId } = await authenticate(req);
    throttle(`feedback:${userId}`, 60, 60 * 60 * 1000);
    const body = await readJson(req);
    const kind = oneOf(body.kind, TIP_FEEDBACK, 'unknown feedback');
    const code = String(body.code || '');
    if (!TIP_CODE.test(code)) throw httpError(400, 'unknown tip');
    await pool.query(
      `INSERT INTO tip_ratings (user_id, code, kind) VALUES ($1, $2, $3)
       ON CONFLICT (user_id, code) DO UPDATE SET kind = EXCLUDED.kind, rated_at = now()`,
      [userId, code, kind],
    );
    if (kind === 'not_okay') {
      await pool.query('INSERT INTO tip_pulled (code) VALUES ($1) ON CONFLICT DO NOTHING', [code]);
    }
    return { ok: true };
  },

  'GET /api/admin/tips/ratings': async (req) => {
    await requireAdmin(req);
    const { rows } = await pool.query(
      `SELECT COALESCE(r.code, p.code) AS code,
              COALESCE(r.likes, 0) AS likes,
              COALESCE(r.not_funny, 0) AS "notFunny",
              COALESCE(r.not_okay, 0) AS "notOkay",
              p.code IS NOT NULL AS pulled
         FROM (SELECT code,
                      count(*) FILTER (WHERE kind = 'like')::int AS likes,
                      count(*) FILTER (WHERE kind = 'not_funny')::int AS not_funny,
                      count(*) FILTER (WHERE kind = 'not_okay')::int AS not_okay
                 FROM tip_ratings GROUP BY code) r
         FULL JOIN tip_pulled p ON p.code = r.code
        ORDER BY 1`,
    );
    return { ratings: rows };
  },

  // An editor puts a pulled tip back for everyone.
  'POST /api/admin/tips/restore': async (req) => {
    await requireAdmin(req);
    const code = String((await readJson(req)).code || '');
    if (!TIP_CODE.test(code)) throw httpError(400, 'unknown tip');
    await pool.query('DELETE FROM tip_pulled WHERE code = $1', [code]);
    return { ok: true };
  },

  // ---- Tip library (AI drafting) -------------------------------------------
  // No longer used by the app, which now has the reviewed tips built in.
  // Kept until the AI work moves to its own server.

  // Approved partner tips, for the app to rotate through.
  'GET /api/tips': async (req) => {
    await authenticate(req);
    const { rows } = await pool.query(
      `SELECT id, phase, tone, text FROM tip_lines WHERE status = 'approved'
        ORDER BY created_at`,
    );
    return { lines: rows };
  },

  // Anyone who sees a tip can rate it once (a new rating replaces the old).
  // "not_okay" pulls the line for everyone straight away.
  'POST /api/tips/feedback': async (req) => {
    const { userId } = await authenticate(req);
    throttle(`feedback:${userId}`, 60, 60 * 60 * 1000);
    const body = await readJson(req);
    const kind = oneOf(body.kind, TIP_FEEDBACK, 'unknown feedback');
    const lineId = String(body.id || '');
    if (!/^[0-9a-f-]{36}$/.test(lineId)) throw httpError(400, 'unknown tip');

    const { rowCount } = await pool.query('SELECT 1 FROM tip_lines WHERE id = $1', [lineId]);
    if (rowCount === 0) throw httpError(404, 'unknown tip');
    await pool.query(
      `INSERT INTO tip_feedback (user_id, line_id, kind) VALUES ($1, $2, $3)
       ON CONFLICT (user_id, line_id) DO UPDATE SET kind = EXCLUDED.kind`,
      [userId, lineId, kind],
    );
    await pool.query(
      `UPDATE tip_lines SET
         likes     = (SELECT count(*) FROM tip_feedback WHERE line_id = $1 AND kind = 'like'),
         not_funny = (SELECT count(*) FROM tip_feedback WHERE line_id = $1 AND kind = 'not_funny'),
         not_okay  = (SELECT count(*) FROM tip_feedback WHERE line_id = $1 AND kind = 'not_okay'),
         status    = CASE WHEN $2 = 'not_okay' AND status = 'approved' THEN 'pulled' ELSE status END
       WHERE id = $1`,
      [lineId, kind],
    );
    return { ok: true };
  },

  'GET /api/admin/tips': async (req) => {
    await requireAdmin(req);
    const status = oneOf(
      new URL(req.url, 'http://localhost').searchParams.get('status'),
      TIP_STATUSES,
      'unknown status',
    );
    const { rows } = await pool.query(
      `SELECT id, phase, tone, text, status, source, review_note AS "reviewNote",
              likes, not_funny AS "notFunny", not_okay AS "notOkay"
         FROM tip_lines WHERE status = $1
        ORDER BY phase, tone, created_at DESC`,
      [status],
    );
    return { lines: rows };
  },

  // Has the AI draft new lines. Lines its reviewer fails are kept as
  // "rejected" with the reason, so an editor can see what was filtered out.
  'POST /api/admin/tips/draft': async (req) => {
    const userId = await requireAdmin(req);
    throttle(`draft:${userId}`, 30, 60 * 60 * 1000);
    const body = await readJson(req);
    const phase = oneOf(body.phase, TIP_PHASES, 'unknown phase');
    const tone = oneOf(body.tone, TIP_TONES, 'unknown tone');
    if (phase === 'menstrual' && tone !== 'straight') {
      throw httpError(400, 'Jokes are always off during her period, so only plain tips are needed.');
    }
    const count = Math.min(Math.max(Number(body.count) || 5, 1), 20);

    const { rows } = await pool.query(
      `SELECT text FROM tip_lines
        WHERE phase = $1 AND tone = $2 AND status IN ('draft', 'approved')`,
      [phase, tone],
    );
    let results;
    try {
      results = await tipWriter.draftTips({ phase, tone, count, avoid: rows.map((r) => r.text) });
    } catch (err) {
      console.error('tip drafting failed', err);
      throw httpError(502, err.message);
    }

    for (const r of results) {
      await pool.query(
        `INSERT INTO tip_lines (id, phase, tone, text, status, source, review_note)
         VALUES ($1, $2, $3, $4, $5, 'ai', $6)`,
        [crypto.randomUUID(), phase, tone, r.text, r.pass ? 'draft' : 'rejected', r.reason],
      );
    }
    return {
      drafted: results.filter((r) => r.pass).length,
      filtered: results.filter((r) => !r.pass).length,
    };
  },

  // An editor approves, rejects, withdraws or restores a line, optionally
  // rewording it first.
  'POST /api/admin/tips/decide': async (req) => {
    await requireAdmin(req);
    const body = await readJson(req);
    const status = oneOf(body.status, ['approved', 'rejected'], 'unknown decision');
    const lineId = String(body.id || '');
    if (!/^[0-9a-f-]{36}$/.test(lineId)) throw httpError(400, 'unknown tip');
    const text = body.text === undefined || body.text === null ? null : String(body.text).trim();
    if (text !== null && (text.length === 0 || text.length > tipWriter.MAX_TIP_LENGTH + 30)) {
      throw httpError(400, 'Keep the tip short.');
    }
    const { rowCount } = await pool.query(
      `UPDATE tip_lines SET status = $2, text = COALESCE($3, text), decided_at = now()
        WHERE id = $1`,
      [lineId, status, text],
    );
    if (rowCount === 0) throw httpError(404, 'unknown tip');
    return { ok: true };
  },

  // The password is asked again so a borrowed, unlocked phone is not enough.
  // 403 rather than 401: the session itself is still valid.
  'POST /api/account/delete': async (req) => {
    const { userId } = await authenticate(req);
    throttle(`delete:${userId}`, 10, 15 * 60 * 1000);
    const body = await readJson(req);
    const { rows } = await pool.query('SELECT password_hash FROM users WHERE id = $1', [userId]);
    if (!(await verifyPassword(String(body.password || ''), rows[0].password_hash))) {
      throw httpError(403, 'Wrong password.');
    }
    // Sessions and her pairing go with the user; a pairing he had joined is unlinked.
    await pool.query('DELETE FROM users WHERE id = $1', [userId]);
    return { ok: true };
  },

  'POST /api/session': async (req) => {
    const { email, password } = readCredentials(await readJson(req), { requireEmail: false });
    throttle(`signin:${clientIp(req)}`, 20, 10 * 60 * 1000);
    throttle(`signin:${email}`, 10, 15 * 60 * 1000);
    const { rows } = await pool.query('SELECT id, password_hash FROM users WHERE email = $1', [email]);
    let ok = false;
    if (rows.length > 0) {
      ok = await verifyPassword(password, rows[0].password_hash);
    } else {
      // Do the same work for an unknown email, so timing does not reveal
      // which addresses have accounts.
      await hashPassword(password);
    }
    if (!ok) throw httpError(401, 'Wrong email or password.');
    return { email, token: await openSession(rows[0].id) };
  },

  'DELETE /api/session': async (req) => {
    const { tokenHash } = await authenticate(req);
    await pool.query('DELETE FROM sessions WHERE token_hash = $1', [tokenHash]);
    return { ok: true };
  },

  // ---- Pairing: her side ---------------------------------------------------

  // She asks for a fresh code. Any previous partner link and snapshot are dropped.
  'POST /api/pairings': async (req) => {
    const { userId } = await authenticate(req);
    const code = newCode();
    await pool.query(
      `INSERT INTO pairings (owner_id, code, code_expires_at)
       VALUES ($1, $2, now() + interval '${CODE_TTL_HOURS} hours')
       ON CONFLICT (owner_id) DO UPDATE
         SET code = EXCLUDED.code, code_expires_at = EXCLUDED.code_expires_at,
             partner_id = NULL, snapshot = NULL, snapshot_at = NULL,
             ask = NULL, ask_at = NULL, reaction = NULL, reaction_at = NULL,
             offer = NULL, offer_at = NULL, offer_reply = NULL, offer_reply_at = NULL,
             partner_tone = NULL`,
      [userId, code],
    );
    return { code, expiresInHours: CODE_TTL_HOURS };
  },

  // `linked`: someone has redeemed her code. `joined`: this user is a partner.
  // Plus her current ask, his reply, his offer and her answer.
  'GET /api/pairings': async (req) => {
    const { userId } = await authenticate(req);
    const { rows } = await pool.query(
      `SELECT EXISTS (SELECT 1 FROM pairings WHERE owner_id = $1 AND partner_id IS NOT NULL) AS linked,
              EXISTS (SELECT 1 FROM pairings WHERE partner_id = $1) AS joined`,
      [userId],
    );
    // partnerTone lets her app show her the same tip he sees today.
    const own = await pool.query(
      `SELECT ${FRESH_INTERACTIONS}, partner_tone AS "partnerTone"
         FROM pairings WHERE owner_id = $1`,
      [userId],
    );
    return { linked: rows[0].linked, joined: rows[0].joined, ...(own.rows[0] || {}) };
  },

  // She sends him one ask from the fixed list, or clears it with null. A new
  // ask replaces the previous one and his reply to it.
  'PUT /api/ask': async (req) => {
    const { userId } = await authenticate(req);
    const ask = optionalKey((await readJson(req)).ask, ASKS);
    const { rowCount } = await pool.query(
      `UPDATE pairings
          SET ask = $2, ask_at = CASE WHEN $2::text IS NULL THEN NULL ELSE now() END,
              reaction = NULL, reaction_at = NULL
        WHERE owner_id = $1`,
      [userId, ask],
    );
    if (rowCount === 0) throw httpError(409, 'Connect with a partner first.');
    return { ok: true };
  },

  // She answers his offer, or takes the answer back with null.
  'PUT /api/offer/reply': async (req) => {
    const { userId } = await authenticate(req);
    const reply = optionalKey((await readJson(req)).reply, OFFER_REPLIES);
    const { rowCount } = await pool.query(
      `UPDATE pairings
          SET offer_reply = $2,
              offer_reply_at = CASE WHEN $2::text IS NULL THEN NULL ELSE now() END
        WHERE owner_id = $1 AND offer IS NOT NULL AND offer_at > ${FRESH}`,
      [userId, reply],
    );
    if (rowCount === 0) throw httpError(409, 'That offer has expired.');
    return { ok: true };
  },

  // She turns sharing off: the link and the stored snapshot go immediately.
  'DELETE /api/pairings': async (req) => {
    const { userId } = await authenticate(req);
    await pool.query('DELETE FROM pairings WHERE owner_id = $1', [userId]);
    return { ok: true };
  },

  // She publishes the latest redacted snapshot. Anything outside SNAPSHOT_FIELDS is discarded.
  'PUT /api/snapshot': async (req) => {
    const { userId } = await authenticate(req);
    const body = await readJson(req);
    const snapshot = Object.fromEntries(
      SNAPSHOT_FIELDS.filter((key) => key in body).map((key) => [key, body[key]]),
    );
    const { rowCount } = await pool.query(
      'UPDATE pairings SET snapshot = $2, snapshot_at = now() WHERE owner_id = $1',
      [userId, JSON.stringify(snapshot)],
    );
    if (rowCount === 0) throw httpError(409, 'no pairing yet');
    return { ok: true };
  },

  // ---- Pairing: his side ---------------------------------------------------

  // He redeems a code. Codes are single-use.
  'POST /api/pairings/join': async (req) => {
    throttle(`join:${clientIp(req)}`, 10, 10 * 60 * 1000);
    const { userId } = await authenticate(req);
    const body = await readJson(req);
    const code = String(body.code || '').trim().toUpperCase();
    const { rowCount } = await pool.query(
      `UPDATE pairings SET partner_id = $1, code = NULL, code_expires_at = NULL
       WHERE code = $2 AND code_expires_at > now() AND owner_id <> $1`,
      [userId, code],
    );
    if (rowCount === 0) throw httpError(404, 'code not found or expired');
    return { ok: true };
  },

  // He answers her current ask, or takes the answer back with null.
  'PUT /api/ask/reaction': async (req) => {
    const { userId } = await authenticate(req);
    const reaction = optionalKey((await readJson(req)).reaction, REACTIONS);
    const { rowCount } = await pool.query(
      `UPDATE pairings
          SET reaction = $2,
              reaction_at = CASE WHEN $2::text IS NULL THEN NULL ELSE now() END
        WHERE partner_id = $1 AND ask IS NOT NULL AND ask_at > ${FRESH}`,
      [userId, reaction],
    );
    if (rowCount === 0) throw httpError(409, 'That ask has expired.');
    return { ok: true };
  },

  // He offers her something, or withdraws the offer with null. A new offer
  // replaces the previous one and her answer to it.
  'PUT /api/offer': async (req) => {
    const { userId } = await authenticate(req);
    const offer = optionalKey((await readJson(req)).offer, OFFERS);
    const { rowCount } = await pool.query(
      `UPDATE pairings
          SET offer = $2, offer_at = CASE WHEN $2::text IS NULL THEN NULL ELSE now() END,
              offer_reply = NULL, offer_reply_at = NULL
        WHERE partner_id = $1`,
      [userId, offer],
    );
    if (rowCount === 0) throw httpError(409, 'Connect with her first.');
    return { ok: true };
  },

  // He disconnects, for example to enter a different code.
  'POST /api/pairings/leave': async (req) => {
    const { userId } = await authenticate(req);
    await pool.query(
      'UPDATE pairings SET partner_id = NULL, partner_tone = NULL WHERE partner_id = $1',
      [userId],
    );
    return { ok: true };
  },

  // He tells the server the tone he picked, so her app can show her the
  // exact tip he gets and she can flag it.
  'PUT /api/partner/tone': async (req) => {
    const { userId } = await authenticate(req);
    const tone = oneOf((await readJson(req)).tone, TIP_TONES, 'unknown tone');
    await pool.query('UPDATE pairings SET partner_tone = $2 WHERE partner_id = $1', [
      userId,
      tone,
    ]);
    return { ok: true };
  },

  'GET /api/snapshot': async (req) => {
    const { userId } = await authenticate(req);
    const { rows } = await pool.query(
      `SELECT snapshot, snapshot_at, ${FRESH_INTERACTIONS}
         FROM pairings
        WHERE partner_id = $1 AND snapshot IS NOT NULL
        ORDER BY snapshot_at DESC LIMIT 1`,
      [userId],
    );
    if (rows.length === 0) throw httpError(404, 'nothing shared');
    const row = rows[0];
    return {
      snapshot: row.snapshot,
      updatedAt: row.snapshot_at,
      ask: row.ask,
      askAt: row.askAt,
      reaction: row.reaction,
      offer: row.offer,
      offerReply: row.offerReply,
    };
  },
};

const server = http.createServer(async (req, res) => {
  try {
    const path = new URL(req.url, 'http://localhost').pathname;
    const handler = routes[`${req.method} ${path}`];
    if (!handler) throw httpError(404, 'not found');
    send(res, 200, await handler(req));
  } catch (err) {
    if (!err.status) console.error(err);
    send(res, err.status || 500, { error: err.status ? err.message : 'server error' });
  }
});

pool.query(SCHEMA)
  .then(seedTestUsers)
  .then(seedTips)
  .then(() => {
    server.listen(PORT, '127.0.0.1', () => console.log(`mooncycle-api listening on 127.0.0.1:${PORT}`));
  })
  .catch((err) => {
    console.error('database setup failed', err);
    process.exit(1);
  });
