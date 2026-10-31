// MoonCycle API — accounts, partner pairing and redacted snapshot sync.
// Raw cycle logs never reach this server; see SNAPSHOT_FIELDS.
const http = require('node:http');
const crypto = require('node:crypto');
const { Pool } = require('pg');
const herNotes = require('./her-notes');
const herChat = require('./her-chat');

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

// Paying for another partner connection. Off until the store products
// exist: she is shown the payment screen and can continue for free.
const PAIRING_PAYMENTS = process.env.PAIRING_PAYMENTS === 'on';

// Partner chat: emojis only (any, no letters or numbers), or a card code.
const CHAT_REACTIONS = ['like', 'love'];
const EMOJI_ONLY = /^(?:\p{Extended_Pictographic}|\p{Regional_Indicator}|\p{Emoji_Modifier}|\u200d|\ufe0f|\u20e3|[\u{E0020}-\u{E007F}]| )+$/u;
const HAS_EMOJI = /\p{Extended_Pictographic}|\p{Regional_Indicator}/u;

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

// The tone of tip he picked, and the ratings anyone can give a tip. A "not
// okay" pulls the tip for everyone until an editor puts it back.
const TIP_TONES = ['straight', 'light', 'playful'];
const TIP_FEEDBACK = ['like', 'not_funny', 'not_okay'];

// Accounts allowed to see tip ratings and put pulled tips back, from the
// server's environment file. Never one of the test accounts: anyone can guess
// those.
const ADMIN_EMAILS = (process.env.ADMIN_EMAILS || '')
  .split(',')
  .map((e) => e.trim().toLowerCase())
  .filter(Boolean);

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

  -- When each sign-in was last used, so unused ones expire.
  ALTER TABLE sessions ADD COLUMN IF NOT EXISTS last_used_at timestamptz NOT NULL DEFAULT now();

  -- Proof of agreement: which version of the terms and privacy policy each
  -- person accepted, and when they gave explicit consent for health data
  -- (UK GDPR articles 7 and 9).
  ALTER TABLE users ADD COLUMN IF NOT EXISTS terms_version text;
  ALTER TABLE users ADD COLUMN IF NOT EXISTS terms_accepted_at timestamptz;
  ALTER TABLE users ADD COLUMN IF NOT EXISTS health_consent_at timestamptz;

  -- The four test accounts used before launch (plain names, a shared
  -- password) are gone: their rows, sessions and pairings are deleted.
  DELETE FROM users WHERE email IN ('alex', 'sorana', 'robert', 'oana');

  -- Sign in with Google: the ID Google gives the person's Google account
  -- (its "sub"). Those accounts have no password.
  ALTER TABLE users ADD COLUMN IF NOT EXISTS google_id text UNIQUE;
  ALTER TABLE users ALTER COLUMN password_hash DROP NOT NULL;

  -- Sign in with Apple (iPhone): Apple's ID for the person, and the refresh
  -- token kept only to cancel Apple's link when the account is deleted.
  ALTER TABLE users ADD COLUMN IF NOT EXISTS apple_id text UNIQUE;
  ALTER TABLE users ADD COLUMN IF NOT EXISTS apple_refresh_token text;

  -- Her separate, explicit consent to AI-written notes: a summary of her day
  -- goes to Anthropic to write them. Null means off.
  ALTER TABLE users ADD COLUMN IF NOT EXISTS ai_notes_consent_at timestamptz;
  ALTER TABLE users ADD COLUMN IF NOT EXISTS ai_notes_version text;

  ALTER TABLE pairings ADD COLUMN IF NOT EXISTS ask text;
  ALTER TABLE pairings ADD COLUMN IF NOT EXISTS ask_at timestamptz;
  ALTER TABLE pairings ADD COLUMN IF NOT EXISTS reaction text;
  ALTER TABLE pairings ADD COLUMN IF NOT EXISTS reaction_at timestamptz;
  ALTER TABLE pairings ADD COLUMN IF NOT EXISTS offer text;
  ALTER TABLE pairings ADD COLUMN IF NOT EXISTS offer_at timestamptz;
  ALTER TABLE pairings ADD COLUMN IF NOT EXISTS offer_reply text;
  ALTER TABLE pairings ADD COLUMN IF NOT EXISTS offer_reply_at timestamptz;
  ALTER TABLE pairings ADD COLUMN IF NOT EXISTS partner_tone text;

  -- The old AI-drafted tip library, replaced by the tips built into the app.
  DROP TABLE IF EXISTS tip_feedback;
  DROP TABLE IF EXISTS tip_lines;

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

  -- AI notes someone reported, to improve the notes: the note and its card
  -- only, never who reported it. Deleted after 90 days.
  CREATE TABLE IF NOT EXISTS ai_note_reports (
    id          bigserial PRIMARY KEY,
    card        text NOT NULL,
    note        text NOT NULL,
    reported_at timestamptz NOT NULL DEFAULT now()
  );

  -- Partner connections (31 October 2026). Every account's first one is
  -- free: pairing_allowance starts at 1, and pairings_used counts partners
  -- who joined with her code. Connecting again needs a one-time payment,
  -- which will add 1 to the allowance once the stores confirm it; until
  -- payments exist she can continue for free, counted in pairing_free_passes.
  ALTER TABLE users ADD COLUMN IF NOT EXISTS pairing_allowance integer NOT NULL DEFAULT 1;
  ALTER TABLE users ADD COLUMN IF NOT EXISTS pairings_used integer NOT NULL DEFAULT 0;
  ALTER TABLE users ADD COLUMN IF NOT EXISTS pairing_free_passes integer NOT NULL DEFAULT 0;
  -- Whoever was already connected before this has used her free one.
  UPDATE users SET pairings_used = 1
   WHERE pairings_used = 0
     AND id IN (SELECT owner_id FROM pairings WHERE partner_id IS NOT NULL);

  -- The chat between her and her partner: only the fixed cards (by code)
  -- and emojis, never free text. Kept 90 days, and gone with the pairing.
  CREATE TABLE IF NOT EXISTS partner_messages (
    id           bigserial PRIMARY KEY,
    owner_id     uuid NOT NULL REFERENCES pairings(owner_id) ON DELETE CASCADE,
    from_her     boolean NOT NULL,
    kind         text NOT NULL,
    body         text NOT NULL,
    sent_at      timestamptz NOT NULL DEFAULT now(),
    her_reaction text,
    his_reaction text
  );
  CREATE INDEX IF NOT EXISTS partner_messages_owner_idx ON partner_messages (owner_id, id);
`;

// Adds a card to the partner chat of the pairing [ownerId].
async function addChat(ownerId, fromHer, body) {
  await pool.query(
    "INSERT INTO partner_messages (owner_id, from_her, kind, body) VALUES ($1, $2, 'card', $3)",
    [ownerId, fromHer, body],
  );
}

// The pairing this user is in, as her or as him, with someone connected.
async function chatPairing(userId) {
  const { rows } = await pool.query(
    `SELECT owner_id, owner_id = $1 AS her FROM pairings
      WHERE (owner_id = $1 OR partner_id = $1) AND partner_id IS NOT NULL
      LIMIT 1`,
    [userId],
  );
  if (rows.length === 0) throw httpError(409, 'Connect with your partner first.');
  return { ownerId: rows[0].owner_id, her: rows[0].her };
}

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

// Every account, for sign-up and sign-in, is an email address.
function readCredentials(body) {
  const email = String(body.email || '').trim().toLowerCase();
  const password = String(body.password || '');
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254) {
    throw httpError(400, 'Enter a valid email address.');
  }
  return { email, password };
}

// ---- Sign in with Google ----------------------------------------------------

// The "MoonCycle server" web client in Google Cloud (project MoonCycle). The
// Android app asks Google for ID tokens made for it. Not a secret; another
// client can be added through the environment file (comma-separated).
// The iPhone client ("MoonCycle iPhone") is accepted too.
const GOOGLE_CLIENT_IDS = (process.env.GOOGLE_CLIENT_IDS ||
  '531774189485-hqam3gqj4ola0p2b277u2e87sv8es266.apps.googleusercontent.com,' +
  '531774189485-d3phbm38s9tbget6rj5qvl1gbicv3c4o.apps.googleusercontent.com')
  .split(',')
  .map((id) => id.trim())
  .filter(Boolean);
const GOOGLE_ISSUERS = ['accounts.google.com', 'https://accounts.google.com'];
const GOOGLE_CERTS_URL = 'https://www.googleapis.com/oauth2/v3/certs';

// Signing keys published by Google and Apple, kept as long as they say
// (capped at a day). Fetched again early only for a key we have not seen, at
// most once a minute.
function signingKeys(url, provider) {
  let cache = { byId: new Map(), expiresAt: 0, fetchedAt: 0 };
  return async (kid) => {
    const now = Date.now();
    const stale = now > cache.expiresAt;
    const unknown = !cache.byId.has(kid) && now - cache.fetchedAt > 60 * 1000;
    if (stale || unknown) {
      const response = await fetch(url, { signal: AbortSignal.timeout(10 * 1000) });
      if (!response.ok) throw httpError(502, `Could not reach ${provider}. Try again.`);
      const { keys } = await response.json();
      const maxAge = Number(/max-age=(\d+)/.exec(response.headers.get('cache-control') || '')?.[1] || 3600);
      cache = {
        byId: new Map(keys.map((jwk) => [jwk.kid, crypto.createPublicKey({ key: jwk, format: 'jwk' })])),
        expiresAt: now + Math.min(maxAge, 24 * 60 * 60) * 1000,
        fetchedAt: now,
      };
    }
    return cache.byId.get(kid);
  };
}
const googleKey = signingKeys(GOOGLE_CERTS_URL, 'Google');

// Checks a sign-in token from the phone: the provider's signature, made for
// our app, not expired. Returns its claims.
async function verifySignInToken(idToken, { keyFor, issuers, audiences, failed }) {
  const token = String(idToken || '');
  const parts = token.split('.');
  if (parts.length !== 3 || token.length > 4096) throw failed();
  let header;
  let claims;
  try {
    header = JSON.parse(Buffer.from(parts[0], 'base64url').toString('utf8'));
    claims = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
  } catch {
    throw failed();
  }
  if (header.alg !== 'RS256' || typeof header.kid !== 'string') throw failed();
  const key = await keyFor(header.kid);
  const signed = key && crypto.verify(
    'sha256',
    Buffer.from(`${parts[0]}.${parts[1]}`),
    key,
    Buffer.from(parts[2], 'base64url'),
  );
  const now = Date.now() / 1000;
  if (!signed ||
      !issuers.includes(claims.iss) ||
      !audiences.includes(claims.aud) ||
      !(claims.exp > now - 60) ||
      typeof claims.sub !== 'string' || claims.sub.length === 0) {
    throw failed();
  }
  return claims;
}

const confirmedEmail = (claims) => {
  const email = String(claims.email || '').trim().toLowerCase();
  const verified = claims.email_verified === true || claims.email_verified === 'true';
  return verified && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) && email.length <= 254 ? email : null;
};

// Google's ID token, with an email Google has confirmed.
async function verifyGoogleToken(idToken) {
  const claims = await verifySignInToken(idToken, {
    keyFor: googleKey,
    issuers: GOOGLE_ISSUERS,
    audiences: GOOGLE_CLIENT_IDS,
    failed: () => httpError(401, 'Google sign-in did not work. Try again.'),
  });
  const email = confirmedEmail(claims);
  if (!email) throw httpError(401, 'Your Google account has no confirmed email address.');
  return { googleId: claims.sub, email };
}

// ---- Sign in with Apple -----------------------------------------------------
// iPhone only. Apple requires it beside Continue with Google. The email may be
// Apple's private relay (…@privaterelay.appleid.com), which forwards to her.

const APPLE_BUNDLE_ID = process.env.APPLE_BUNDLE_ID || 'com.ioncodex.mooncycle';
const APPLE_ISSUER = 'https://appleid.apple.com';
const appleKey = signingKeys('https://appleid.apple.com/auth/keys', 'Apple');

async function verifyAppleToken(identityToken) {
  const claims = await verifySignInToken(identityToken, {
    keyFor: appleKey,
    issuers: [APPLE_ISSUER],
    audiences: [APPLE_BUNDLE_ID],
    failed: () => httpError(401, 'Sign in with Apple did not work. Try again.'),
  });
  return { appleId: claims.sub, email: confirmedEmail(claims) };
}

// Apple asks apps to cancel its sign-in link when an account is deleted. That
// needs the "Sign in with Apple" key from the Apple Developer portal, on the
// server only (DEPLOY.md): APPLE_TEAM_ID, APPLE_KEY_ID and APPLE_KEY_FILE.
// Without them, sign-in still works and the cancelling is skipped (logged).
function appleClientSecret() {
  const { APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_KEY_FILE } = process.env;
  if (!APPLE_TEAM_ID || !APPLE_KEY_ID || !APPLE_KEY_FILE) return null;
  const now = Math.floor(Date.now() / 1000);
  const part = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
  const input = `${part({ alg: 'ES256', kid: APPLE_KEY_ID })}.${part({
    iss: APPLE_TEAM_ID, iat: now, exp: now + 300, aud: APPLE_ISSUER, sub: APPLE_BUNDLE_ID,
  })}`;
  const signature = crypto.sign('sha256', Buffer.from(input), {
    key: require('node:fs').readFileSync(APPLE_KEY_FILE, 'utf8'),
    dsaEncoding: 'ieee-p1363',
  });
  return `${input}.${signature.toString('base64url')}`;
}

async function appleRequest(path, fields) {
  const secret = appleClientSecret();
  if (!secret) {
    console.error(`apple ${path} skipped: the Sign in with Apple key is not set up`);
    return null;
  }
  const response = await fetch(`${APPLE_ISSUER}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ client_id: APPLE_BUNDLE_ID, client_secret: secret, ...fields }),
    signal: AbortSignal.timeout(10 * 1000),
  });
  if (!response.ok) {
    console.error(`apple ${path} failed:`, response.status);
    return null;
  }
  return path === '/auth/token' ? response.json() : {};
}

// The refresh token, kept only so the link can be cancelled on deletion.
async function appleRefreshToken(authorizationCode) {
  if (typeof authorizationCode !== 'string' || authorizationCode.length > 1024) return null;
  const tokens = await appleRequest('/auth/token', {
    code: authorizationCode, grant_type: 'authorization_code',
  }).catch(() => null);
  return tokens?.refresh_token ?? null;
}

async function revokeApple(refreshToken) {
  if (!refreshToken) return;
  await appleRequest('/auth/revoke', {
    token: refreshToken, token_type_hint: 'refresh_token',
  }).catch((err) => console.error('apple revoke failed:', err?.constructor?.name));
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

// A sign-in lasts until it goes unused for this long, then the person signs in
// again. The privacy policy states this period.
const SESSION_IDLE_DAYS = 90;

async function authenticate(req) {
  const match = /^Bearer ([A-Za-z0-9_-]{20,})$/.exec(req.headers.authorization || '');
  if (!match) throw httpError(401, 'Sign in first.');
  const tokenHash = sha256(match[1]);
  const { rows } = await pool.query(
    `SELECT user_id, last_used_at < now() - interval '1 day' AS stale
       FROM sessions
      WHERE token_hash = $1 AND last_used_at > now() - interval '${SESSION_IDLE_DAYS} days'`,
    [tokenHash],
  );
  if (rows.length === 0) throw httpError(401, 'Sign in again.');
  // Recorded at most once a day, so ordinary requests don't write.
  if (rows[0].stale) {
    await pool.query('UPDATE sessions SET last_used_at = now() WHERE token_hash = $1', [tokenHash]);
  }
  return { userId: rows[0].user_id, tokenHash };
}

// What is deleted once it expires, as the privacy policy states: unused
// sign-ins, unused pairing codes, and one-tap messages once they are a day
// old (an ask goes with his reply to it, an offer with her answer).
const CLEAN_UPS = [
  ['sign-ins', `DELETE FROM sessions WHERE last_used_at < now() - interval '${SESSION_IDLE_DAYS} days'`],
  ['note reports', "DELETE FROM ai_note_reports WHERE reported_at < now() - interval '90 days'"],
  ['partner chat', "DELETE FROM partner_messages WHERE sent_at < now() - interval '90 days'"],
  ['pairing codes', 'UPDATE pairings SET code = NULL, code_expires_at = NULL WHERE code_expires_at < now()'],
  ['asks', `UPDATE pairings SET ask = NULL, ask_at = NULL, reaction = NULL, reaction_at = NULL
             WHERE ask_at <= ${FRESH}`],
  ['offers', `UPDATE pairings SET offer = NULL, offer_at = NULL, offer_reply = NULL, offer_reply_at = NULL
               WHERE offer_at <= ${FRESH}`],
];

// Runs at start-up and then every 15 minutes.
async function removeExpiredData() {
  for (const [what, sql] of CLEAN_UPS) {
    await pool.query(sql).catch((err) => console.error(`clean-up of ${what} failed`, err));
  }
}
setInterval(removeExpiredData, 15 * 60 * 1000).unref();

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

// AI chat messages used today, per account. In memory: a restart gives
// everyone a fresh count, which is fine for a daily allowance.
const CHAT_PER_DAY = 20;
const chatCounts = new Map();
const chatKey = (userId) => `${userId}:${new Date().toISOString().slice(0, 10)}`;
const chatUsed = (userId) => chatCounts.get(chatKey(userId)) ?? 0;
setInterval(() => {
  const today = new Date().toISOString().slice(0, 10);
  for (const key of chatCounts.keys()) if (!key.endsWith(today)) chatCounts.delete(key);
}, 60 * 60 * 1000).unref();

const routes = {
  'GET /api/health': async () => ({ ok: true }),

  // ---- Accounts ------------------------------------------------------------

  'POST /api/account': async (req) => {
    throttle(`signup:${clientIp(req)}`, 10, 60 * 60 * 1000);
    const body = await readJson(req);
    const { email, password } = readCredentials(body);
    if (password.length < MIN_PASSWORD_LENGTH || password.length > MAX_PASSWORD_LENGTH) {
      throw httpError(400, `Use a password of at least ${MIN_PASSWORD_LENGTH} characters.`);
    }
    // The app checks the same before sending; this holds for any client.
    if (!/[A-Z]/.test(password) || !/[^A-Za-z0-9\s]/.test(password)) {
      throw httpError(400, 'Use at least one capital letter and one special character, such as ! # or ?.');
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
      `SELECT email, terms_version, ai_notes_version, password_hash IS NOT NULL AS password,
              CASE WHEN password_hash IS NOT NULL THEN 'password'
                   WHEN apple_id IS NOT NULL THEN 'apple'
                   ELSE 'google' END AS "signIn"
         FROM users WHERE id = $1`,
      [userId],
    );
    return {
      email: rows[0].email,
      admin: ADMIN_EMAILS.includes(rows[0].email),
      termsVersion: rows[0].terms_version,
      aiNotesVersion: rows[0].ai_notes_version,
      // False for accounts made with Google or Apple, which confirm with
      // them instead; signIn says which.
      password: rows[0].password,
      signIn: rows[0].signIn,
    };
  },

  // She turns AI-written notes on (giving her explicit consent to the
  // version of the explanation she read) or off.
  'PUT /api/account/ai-notes': async (req) => {
    const { userId } = await authenticate(req);
    const body = await readJson(req);
    if (body.on === true) {
      const version = String(body.version || '').trim();
      if (!/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(version)) throw httpError(400, 'unknown version');
      await pool.query(
        'UPDATE users SET ai_notes_consent_at = now(), ai_notes_version = $2 WHERE id = $1',
        [userId, version],
      );
    } else {
      await pool.query(
        'UPDATE users SET ai_notes_consent_at = NULL, ai_notes_version = NULL WHERE id = $1',
        [userId],
      );
    }
    return { ok: true };
  },

  // Today's AI-written note for the card her phone chose. Only with her
  // consent; a few a day at most. `note` is null whenever the note cannot be
  // written or fails a check, and her phone then shows the card as it is.
  // Neither her summary nor the note is stored or logged.
  // She reports an AI-written note from inside the app (a Google Play rule
  // for AI-generated content). Only the note and its card are kept, without
  // her account, for 90 days.
  'POST /api/her-note/report': async (req) => {
    const { userId } = await authenticate(req);
    throttle(`note-report:${userId}`, 10, 24 * 60 * 60 * 1000);
    const body = await readJson(req);
    const card = String(body.card || '');
    const note = String(body.note || '').trim();
    if (!/^(?:[A-Z]{1,3}\d{2}b?|NEW\d{2})$/.test(card)) throw httpError(400, 'unknown card');
    if (note.length === 0 || note.length > 800) throw httpError(400, 'bad note');
    await pool.query('INSERT INTO ai_note_reports (card, note) VALUES ($1, $2)', [card, note]);
    return { ok: true };
  },

  // Editors read the reports, newest first.
  'GET /api/admin/note-reports': async (req) => {
    await requireAdmin(req);
    const { rows } = await pool.query(
      `SELECT card, note, reported_at AS "reportedAt"
         FROM ai_note_reports ORDER BY reported_at DESC LIMIT 200`,
    );
    return { reports: rows };
  },

  'POST /api/her-note': async (req) => {
    const { userId } = await authenticate(req);
    const { rows } = await pool.query(
      'SELECT ai_notes_consent_at FROM users WHERE id = $1',
      [userId],
    );
    if (!rows[0].ai_notes_consent_at) throw httpError(403, 'AI notes are off.');
    throttle(`her-note:${userId}`, 6, 24 * 60 * 60 * 1000);
    const body = await readJson(req);
    try {
      const { note } = await herNotes.writeNote(body);
      return { note };
    } catch (error) {
      // Only what kind of failure, never what was in the request.
      console.error('her note failed:', error?.constructor?.name, error?.status ?? '');
      return { note: null };
    }
  },

  // One answer in her AI chat. Only with her consent, and 20 messages a day
  // (counted per UTC day). Neither her messages nor the answer are stored
  // or logged: her chat history is on her phone.
  'POST /api/her-chat': async (req) => {
    const { userId } = await authenticate(req);
    const { rows } = await pool.query(
      'SELECT ai_notes_consent_at FROM users WHERE id = $1',
      [userId],
    );
    if (!rows[0].ai_notes_consent_at) throw httpError(403, 'AI chat is off.');
    const body = await readJson(req);
    const used = chatUsed(userId);
    if (used >= CHAT_PER_DAY) {
      return { reply: null, limit: true, remaining: 0 };
    }
    chatCounts.set(chatKey(userId), used + 1);
    const remaining = CHAT_PER_DAY - used - 1;
    try {
      const answer = await herChat.reply(body);
      if (answer.reason) console.log('her chat fixed answer:', answer.reason);
      return { reply: answer.reply, urgent: answer.urgent, suggestions: answer.suggestions, remaining };
    } catch (error) {
      // A message she could not have sent from the app does not count.
      if (error instanceof herChat.NoteRefused) {
        chatCounts.set(chatKey(userId), used);
        throw httpError(400, 'bad chat request');
      }
      // Only what kind of failure, never what was in the request.
      console.error('her chat failed:', error?.constructor?.name, error?.status ?? '');
      chatCounts.set(chatKey(userId), used);
      return { reply: null, remaining: remaining + 1 };
    }
  },

  // She reports an answer from the chat (the Google Play rule for
  // AI-generated content). Only the answer is kept, without her account or
  // her messages, for 90 days.
  'POST /api/her-chat/report': async (req) => {
    const { userId } = await authenticate(req);
    throttle(`chat-report:${userId}`, 10, 24 * 60 * 60 * 1000);
    const body = await readJson(req);
    const answer = String(body.answer || '').trim();
    if (answer.length === 0 || answer.length > 1500) throw httpError(400, 'bad answer');
    await pool.query('INSERT INTO ai_note_reports (card, note) VALUES ($1, $2)', ['CHAT', answer]);
    return { ok: true };
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

  // Deleting needs a second check, so a borrowed, unlocked phone is not
  // enough: the phone's own fingerprint, face or PIN (the app checks it and
  // sends deviceConfirmed; the server cannot see that check), or, for phones
  // without a screen lock and the test website, the password (Google again
  // for accounts made with Google).
  // 403 rather than 401 for a failed check: the session itself is valid.
  'POST /api/account/delete': async (req) => {
    const { userId } = await authenticate(req);
    throttle(`delete:${userId}`, 10, 15 * 60 * 1000);
    const body = await readJson(req);
    if (body.deviceConfirmed !== true) {
      const { rows } = await pool.query(
        'SELECT password_hash, google_id, apple_id FROM users WHERE id = $1',
        [userId],
      );
      if (body.googleIdToken !== undefined) {
        const { googleId } = await verifyGoogleToken(body.googleIdToken);
        if (googleId !== rows[0].google_id) {
          throw httpError(403, 'That is a different Google account.');
        }
      } else if (body.appleIdentityToken !== undefined) {
        const { appleId } = await verifyAppleToken(body.appleIdentityToken);
        if (appleId !== rows[0].apple_id) {
          throw httpError(403, 'That is a different Apple account.');
        }
      } else if (rows[0].password_hash === null) {
        throw httpError(403, 'Confirm with Google or Apple to delete this account.');
      } else if (!(await verifyPassword(String(body.password || ''), rows[0].password_hash))) {
        throw httpError(403, 'Wrong password.');
      }
    }
    // Apple's link is cancelled first (Apple's rule for deleted accounts).
    const apple = await pool.query('SELECT apple_refresh_token FROM users WHERE id = $1', [userId]);
    await revokeApple(apple.rows[0]?.apple_refresh_token);
    // Sessions and her pairing go with the user; a pairing he had joined is unlinked.
    await pool.query('DELETE FROM users WHERE id = $1', [userId]);
    return { ok: true };
  },

  'POST /api/session': async (req) => {
    const { email, password } = readCredentials(await readJson(req));
    throttle(`signin:${clientIp(req)}`, 20, 10 * 60 * 1000);
    throttle(`signin:${email}`, 10, 15 * 60 * 1000);
    const { rows } = await pool.query('SELECT id, password_hash FROM users WHERE email = $1', [email]);
    // Sign-up already tells anyone that an email has an account, so saying
    // how it signs in gives nothing more away.
    if (rows.length > 0 && rows[0].password_hash === null) {
      throw httpError(401, 'This account uses Continue with Google or Sign in with Apple.');
    }
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

  // Continue with Google (Android for now). Google confirms the email, so the
  // first time makes the account. Consent is recorded with it when she ticked
  // both boxes on the sign-up screen first; otherwise the app asks for it
  // next, before anything else. An email that already has a password account
  // is not joined to it: emails are not confirmed for those, so the account
  // may have been made by someone else.
  'POST /api/session/google': async (req) => {
    throttle(`google:${clientIp(req)}`, 20, 10 * 60 * 1000);
    const body = await readJson(req);
    const { googleId, email } = await verifyGoogleToken(body.idToken);
    const signIn = async () => {
      const { rows } = await pool.query('SELECT id, email FROM users WHERE google_id = $1', [googleId]);
      return rows.length > 0 ? { email: rows[0].email, token: await openSession(rows[0].id) } : null;
    };
    const known = await signIn();
    if (known) return known;

    const termsVersion = body.healthConsent === undefined ? null : readConsent(body);
    const { rowCount } = await pool.query(
      `INSERT INTO users (id, email, google_id, terms_version, terms_accepted_at, health_consent_at)
       VALUES ($1, $2, $3, $4::text,
               CASE WHEN $4::text IS NULL THEN NULL ELSE now() END,
               CASE WHEN $4::text IS NULL THEN NULL ELSE now() END)
       ON CONFLICT DO NOTHING`,
      [crypto.randomUUID(), email, googleId, termsVersion],
    );
    if (rowCount === 0) {
      // Made a moment ago by a second tap, or the email is taken.
      const raced = await signIn();
      if (raced) return raced;
      throw httpError(409, 'This email already has a MoonCycle account. Sign in with your email and password.');
    }
    return signIn();
  },

  // Sign in with Apple (iPhone). Like Google: the first time makes the
  // account (Apple confirms the email, or gives a private relay address);
  // consent is recorded with it when she ticked both boxes first, otherwise
  // the app asks next. An email that already has another account is not
  // joined to it.
  'POST /api/session/apple': async (req) => {
    throttle(`apple:${clientIp(req)}`, 20, 10 * 60 * 1000);
    const body = await readJson(req);
    const { appleId, email } = await verifyAppleToken(body.identityToken);
    const refreshToken = await appleRefreshToken(body.authorizationCode);
    const signIn = async () => {
      const { rows } = await pool.query('SELECT id, email FROM users WHERE apple_id = $1', [appleId]);
      if (rows.length === 0) return null;
      if (refreshToken) {
        await pool.query('UPDATE users SET apple_refresh_token = $2 WHERE id = $1', [rows[0].id, refreshToken]);
      }
      return { email: rows[0].email, token: await openSession(rows[0].id) };
    };
    const known = await signIn();
    if (known) return known;

    if (!email) {
      throw httpError(400, 'Apple did not share an email address. Try again and choose to share or hide your email.');
    }
    const termsVersion = body.healthConsent === undefined ? null : readConsent(body);
    const { rowCount } = await pool.query(
      `INSERT INTO users (id, email, apple_id, apple_refresh_token, terms_version, terms_accepted_at, health_consent_at)
       VALUES ($1, $2, $3, $4, $5::text,
               CASE WHEN $5::text IS NULL THEN NULL ELSE now() END,
               CASE WHEN $5::text IS NULL THEN NULL ELSE now() END)
       ON CONFLICT DO NOTHING`,
      [crypto.randomUUID(), email, appleId, refreshToken, termsVersion],
    );
    if (rowCount === 0) {
      const raced = await signIn();
      if (raced) return raced;
      throw httpError(409, 'This email already has a MoonCycle account. Sign in the way you did before.');
    }
    return signIn();
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
    const body = await readJson(req);
    // Her first partner connection is free. After a partner has joined, a
    // new connection needs a one-time payment (402); until payments exist,
    // she can continue for free from the payment screen.
    const { rows: [account] } = await pool.query(
      'SELECT pairing_allowance, pairings_used FROM users WHERE id = $1',
      [userId],
    );
    if (account.pairings_used >= account.pairing_allowance) {
      if (PAIRING_PAYMENTS || body.continueFree !== true) {
        throw httpError(402, 'A new partner connection needs a one-time payment.');
      }
      await pool.query(
        `UPDATE users SET pairing_allowance = pairing_allowance + 1,
                          pairing_free_passes = pairing_free_passes + 1
          WHERE id = $1`,
        [userId],
      );
    }
    await pool.query('DELETE FROM partner_messages WHERE owner_id = $1', [userId]);
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
    if (ask) await addChat(userId, true, ask);
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
    if (reply) await addChat(userId, true, reply);
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
    const { rows } = await pool.query(
      `UPDATE pairings SET partner_id = $1, code = NULL, code_expires_at = NULL
       WHERE code = $2 AND code_expires_at > now() AND owner_id <> $1
       RETURNING owner_id`,
      [userId, code],
    );
    if (rows.length === 0) throw httpError(404, 'code not found or expired');
    // Her connection is used.
    await pool.query('UPDATE users SET pairings_used = pairings_used + 1 WHERE id = $1', [
      rows[0].owner_id,
    ]);
    return { ok: true };
  },

  // He answers her current ask, or takes the answer back with null.
  'PUT /api/ask/reaction': async (req) => {
    const { userId } = await authenticate(req);
    const reaction = optionalKey((await readJson(req)).reaction, REACTIONS);
    const { rows } = await pool.query(
      `UPDATE pairings
          SET reaction = $2,
              reaction_at = CASE WHEN $2::text IS NULL THEN NULL ELSE now() END
        WHERE partner_id = $1 AND ask IS NOT NULL AND ask_at > ${FRESH}
        RETURNING owner_id, ask`,
      [userId, reaction],
    );
    if (rows.length === 0) throw httpError(409, 'That ask has expired.');
    // "special" is the reply written for her ask, so the chat keeps which.
    if (reaction) {
      await addChat(rows[0].owner_id, false, reaction === 'special' ? `special:${rows[0].ask}` : reaction);
    }
    return { ok: true };
  },

  // He offers her something, or withdraws the offer with null. A new offer
  // replaces the previous one and her answer to it.
  'PUT /api/offer': async (req) => {
    const { userId } = await authenticate(req);
    const offer = optionalKey((await readJson(req)).offer, OFFERS);
    const { rows } = await pool.query(
      `UPDATE pairings
          SET offer = $2, offer_at = CASE WHEN $2::text IS NULL THEN NULL ELSE now() END,
              offer_reply = NULL, offer_reply_at = NULL
        WHERE partner_id = $1
        RETURNING owner_id`,
      [userId, offer],
    );
    if (rows.length === 0) throw httpError(409, 'Connect with her first.');
    if (offer) await addChat(rows[0].owner_id, false, offer);
    return { ok: true };
  },

  // He disconnects, for example to enter a different code.
  'POST /api/pairings/leave': async (req) => {
    const { userId } = await authenticate(req);
    const { rows } = await pool.query(
      'UPDATE pairings SET partner_id = NULL, partner_tone = NULL WHERE partner_id = $1 RETURNING owner_id',
      [userId],
    );
    for (const row of rows) {
      await pool.query('DELETE FROM partner_messages WHERE owner_id = $1', [row.owner_id]);
    }
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

  // ---- Partner chat --------------------------------------------------------
  // Both of them read the same chat: the last 90 days, oldest first.

  'GET /api/chat': async (req) => {
    const { userId } = await authenticate(req);
    const { ownerId, her } = await chatPairing(userId);
    const { rows } = await pool.query(
      `SELECT id, from_her AS "fromHer", kind, body, sent_at AS "sentAt",
              her_reaction AS "herReaction", his_reaction AS "hisReaction"
         FROM (SELECT * FROM partner_messages
                WHERE owner_id = $1 AND sent_at > now() - interval '90 days'
                ORDER BY id DESC LIMIT 500) recent
        ORDER BY id`,
      [ownerId],
    );
    return { me: her ? 'her' : 'him', messages: rows.map((m) => ({ ...m, id: Number(m.id) })) };
  },

  // Emojis only; the cards go through the ask and offer routes above.
  'POST /api/chat': async (req) => {
    const { userId } = await authenticate(req);
    throttle(`chat:${userId}`, 200, 24 * 60 * 60 * 1000);
    const { ownerId, her } = await chatPairing(userId);
    const emoji = String((await readJson(req)).emoji ?? '').trim();
    if (emoji.length === 0 || emoji.length > 40 || !EMOJI_ONLY.test(emoji) || !HAS_EMOJI.test(emoji)) {
      throw httpError(400, 'Only emojis can be sent.');
    }
    await pool.query(
      "INSERT INTO partner_messages (owner_id, from_her, kind, body) VALUES ($1, $2, 'emoji', $3)",
      [ownerId, her, emoji],
    );
    return { ok: true };
  },

  // Either of them likes or loves any message, or takes it back with null.
  'PUT /api/chat/reaction': async (req) => {
    const { userId } = await authenticate(req);
    const { ownerId, her } = await chatPairing(userId);
    const body = await readJson(req);
    const id = Number(body.id);
    if (!Number.isSafeInteger(id) || id <= 0) throw httpError(400, 'unknown message');
    const reaction = optionalKey(body.reaction, CHAT_REACTIONS);
    const column = her ? 'her_reaction' : 'his_reaction';
    const { rowCount } = await pool.query(
      `UPDATE partner_messages SET ${column} = $3 WHERE id = $1 AND owner_id = $2`,
      [id, ownerId, reaction],
    );
    if (rowCount === 0) throw httpError(404, 'unknown message');
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
  .then(() => {
    removeExpiredData();
    server.listen(PORT, '127.0.0.1', () => console.log(`mooncycle-api listening on 127.0.0.1:${PORT}`));
  })
  .catch((err) => {
    console.error('database setup failed', err);
    process.exit(1);
  });
