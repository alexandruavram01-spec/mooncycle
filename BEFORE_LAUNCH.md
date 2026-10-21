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
- **Health review of the partner copy.** The phase card lines (G codes) and
  any tip that touches health, in both `content/partner-messages-en-GB.txt`
  and `content/partner-messages-en-INT.txt`, need a check by a gynaecologist
  or midwife.
- **Insight cards for her are test-accounts only.** Before switching them on
  for everyone (`herInsightsEnabledProvider` in `lib/state/providers.dart`):
  clinical sign-off of the cards, the pattern cards H01–H03 and the "Get help
  now" page, plus an International edition with urgent advice adapted for
  outside the UK. See `content/her-insights-en-GB.txt`.
- **Check the "Pulled" list** in the tip library for anything flagged.
- **Remove the old AI tip routes** from `server/server.js` (the
  "Tip library (AI drafting)" section, `tip-writer.js` and `tips-seed.json`)
  once the AI work has its own server. The app no longer uses them.

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
- **Medical device check**: confirm with the clinician or a regulatory
  adviser that MoonCycle stays outside the MHRA's software-as-a-medical-device
  rules (general information and estimates, no diagnosis, not contraception),
  and keep store descriptions and marketing to those claims.

## Server

- **Server logs**: the privacy policy promises 14 days. Check
  `/etc/logrotate.d/nginx` keeps no more (`rotate 14` with `daily`).
- **Search engines.** nginx sends `X-Robots-Tag: noindex`. Decide whether the
  public site should be indexed.

## App stores

- **App ID** `com.ioncodex.mooncycle` on both platforms. Permanent once the
  first build is uploaded.
- **App icon** from the logo: square, no text, no rounded corners (the stores
  add their own). Put it in `assets/icon/` and run
  `dart run flutter_launcher_icons`.
- **Android release signing**: upload keystore on Codemagic (or
  `android/key.properties` locally, never committed).
