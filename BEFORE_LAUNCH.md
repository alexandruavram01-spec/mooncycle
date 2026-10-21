# Before real users

Things that are fine while testing and must change before anyone outside the
test group uses MoonCycle.

## Remove

- **The four test accounts.** `server/server.js` creates `alex`, `sorana`,
  `robert` and `oana` at start-up, all with the password `123456`. To remove
  them:
  1. Delete `TEST_USERS`, `TEST_PASSWORD` and `seedTestUsers` from
     `server/server.js`, and the `.then(seedTestUsers)` line at the bottom.
  2. Change `requireEmail: false` back to `true` in the `POST /api/session`
     route, so sign-in only accepts email addresses again.
  3. In `lib/ui/screens/account_screen.dart`, make the email check apply to
     sign-in as well as sign-up.
  4. Delete the accounts from the database (removing the code does not):
     `DELETE FROM users WHERE email IN ('alex', 'sorana', 'robert', 'oana');`
  5. The "Start over" button only shows for these accounts (any name without
     an `@`), so it disappears with them. Remove `isTestAccountProvider` and
     its two uses (Settings, the partner menu) if no longer wanted.

## Tip library

- **Editors** are set by `ADMIN_EMAILS` in `/etc/mooncycle-api.env` on the
  server. Keep it to real accounts with strong passwords, never a test
  account.
- **Health check of the partner copy.** The phase card lines (G codes) and
  any tip that touches health, in both `content/partner-messages-en-GB.txt`
  and `content/partner-messages-en-INT.txt`: check each against the NHS
  pages, as for her cards. (No clinician review: decided 21 October 2026.)
- **Insight cards for her are test-accounts only.** Before switching them on
  for everyone (`herInsightsEnabledProvider` in `lib/state/providers.dart`):
  our own check of every card, opening line and the "Get help now" page
  against the NHS pages they cite, and an International edition with urgent
  help adapted for outside the UK. See `content/her-insights-en-GB.txt`
  (last section).
- **Check the "Pulled" list** in the tip library for anything flagged.

## AI-written notes (opt-in, at launch)

- **Anthropic account in the company's name**, its commercial terms and data
  processing agreement accepted. Confirm in those terms how transfers from
  the UK are covered (the UK addendum to the standard contractual clauses),
  as `web/privacy.html` says. Ask Anthropic whether zero data retention is
  available; if it is, update the privacy policy and the AI notes screen
  (both say "deleted within 30 days").
- **Data protection impact assessment** for sending health summaries to
  Anthropic: our own, on the ICO's template. Keep it with the company records.
- **The medical device self-assessment** (Legal and company, below) must
  cover the AI notes.
- **Server setup**: the SDK and the key, DEPLOY.md, "AI-written notes on the
  server".
- **Cost**: about 1p per note with the second reading. Watch the usage page
  in the Anthropic Console after launch.
- The notes follow the cards: only where the cards are switched on
  (`herInsightsEnabledProvider`), and only for those who turn them on.

## Still to build

- **Password reset and email confirmation.** Neither exists; a forgotten
  password means a new account. Needs an email service.
- **Secure storage for the sign-in token on Android.** It is in the app's
  private storage for now.
- **Home screens for the life-stage journeys.** "Navigate life's changes",
  "Embrace my next chapter" and "Feel more like myself" are hidden from the
  quiz (`hidden: true` in `lib/domain/quiz.dart`) because they would land on
  the cycle-tracking home. Remove that line once each has its own home.
- **Bundle the Gelasio typeface** in the app instead of downloading it from
  Google Fonts at run time (that shows the user's IP address to Google; the
  privacy policy says so until it is fixed). Then remove that paragraph from
  `web/privacy.html`.
- **Data export** for her logs, so she can take her data elsewhere.

## Legal and company (IONCODEX LTD, 16798601)

- **Solicitor review** of `web/terms.html`, `web/privacy.html`,
  `web/health.html` and `web/delete-account.html`, including the minimum age
  (18 in the drafts; lowering it brings in the ICO Children's Code) and
  whether a Data Protection Impact Assessment is needed (likely, for health
  data). After any material change, bump `Legal.version` in `lib/legal.dart`:
  everyone is then asked to agree again.
- **ICO data protection fee** paid in the company's name, and its
  registration number added to `web/privacy.html`.
- **mooncycle_contact@ioncodex.org** (an alias of contact@ioncodex.org) is the
  address in every legal page: someone must read it, and answer data
  requests within one month.
- **Hetzner** in the company's name, and its data processing agreement
  concluded at accounts.hetzner.com/account/dpa.
- **Medical device check**: our own written assessment, against the MHRA's
  guidance on software and apps, that MoonCycle stays outside the
  software-as-a-medical-device rules: general information from the NHS,
  estimates, no diagnosis, no triage (urgent help is signposting only, the
  same numbers for everyone), not contraception. Keep store descriptions and
  marketing to those claims. With AI-written notes this needs extra care:
  they must stay general information too.

## Server

- **Server logs**: the privacy policy promises 14 days. Check
  `/etc/logrotate.d/nginx` keeps no more (`rotate 14` with `daily`).
- **Search engines.** nginx sends `X-Robots-Tag: noindex`. Decide whether the
  public site should be indexed.

## Retire the web app (it is for testing only)

- Replace the Flutter web app at mooncycle.fit with a small static page:
  logo, one paragraph, App Store and Google Play badges, legal links.
- Keep `/api/` (the phone apps need it) and the legal pages
  (`privacy.html`, `terms.html`, `health.html`, `delete-account.html`): both
  stores require a public privacy policy link, and Google Play a public
  account deletion page. They may move to ioncodex.org instead; if so, update
  the URLs in `lib/legal.dart` and the store listings.
- In `.github/workflows/deploy.yml`, drop "Build the website" and upload only
  the static page and legal pages.
- In `web/privacy.html`, remove the mentions of the website (section 9).

## App stores

- **App ID** `com.ioncodex.mooncycle` on both platforms. Permanent once the
  first build is uploaded.
- **App icon** from the logo: square, no text, no rounded corners (the stores
  add their own). Put it in `assets/icon/` and run
  `dart run flutter_launcher_icons`.
- **Android release signing**: upload keystore on Codemagic (or
  `android/key.properties` locally, never committed).
