# Before real users

Things that are fine while testing and must change before anyone outside the
test group uses MoonCycle.

## Remove

- **The four test accounts** were removed on 22 October 2026: the server
  deletes them at start-up and sign-in accepts email addresses only. For
  Google and Apple's reviewers, create two review accounts in the app with
  real email addresses and strong passwords, link them as partners, and give
  the logins in Play Console ("App access") and App Store Connect.

## Tip library

- **Editors** are set by `ADMIN_EMAILS` in `/etc/mooncycle-api.env` on the
  server. Keep it to real accounts with strong passwords, never a test
  account.
- **Health check of the partner copy.** The phase card lines (G codes) and
  any tip that touches health, in both `content/partner-messages-en-GB.txt`
  and `content/partner-messages-en-INT.txt`: check each against the NHS
  pages, as for her cards. (No clinician review: decided 21 October 2026.)
- **Insight cards for her are on for everyone tracking her cycle** (since
  22 October 2026). Still to do: our own check of every card, opening line
  and the "Get help now" page against the NHS pages they cite, and an
  International edition with urgent help adapted for outside the UK. See
  `content/her-insights-en-GB.txt` (last section).
- **Check the "Pulled" list** in the tip library for anything flagged.

## Privacy (from the DPIA, revised 22 October 2026)

The DPIA (shared doc "MoonCycle data protection impact assessment") is not
approved until its launch controls are verified. Its open actions, besides
those listed elsewhere here:

- **Breach procedure and breach log**: record every breach; report to the
  ICO within 72 hours of becoming aware unless unlikely to risk people's
  rights; tell people directly when the risk to them is high.
- **Data requests by email**: a written procedure and a request log.
- **Phone backups**: check on real phones what iCloud and Google backups
  contain (Android backup is on by default: no `allowBackup` setting in the
  manifest), then decide whether to exclude her log.
- **Her phone's screen**: reminders without health wording on the lock
  screen, content hidden in the app switcher, an optional app lock.
- **Sharing screen**: say that what her partner has already seen cannot be
  taken back; decide on domestic abuse support on Get help now.
- **"I am 18 or over"** confirmation at sign-up.
- **Server logs** kept no longer than 14 days: check log rotation.
- **Testers**: a short privacy questionnaire.

## AI-written notes (opt-in, at launch)

- **Anthropic account in the company's name**, its commercial terms and data
  processing agreement accepted. Transfers: check the Data Privacy Framework
  List (dataprivacyframework.gov) for an active UK Extension certification;
  if there is none, record a transfer risk assessment and rely on the
  safeguards in Anthropic's data processing terms. Review its sub-processors.
  Notes run with `inference_geo: "us"` (server/her-notes.js), so data is
  stored and processed only in the United States. Ask Anthropic whether zero data retention is
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

## Google sign-in

- **The Play client in Google Cloud**: after the first upload, an Android
  client with the App signing key SHA-1 (SIGN_IN_SETUP.md, Status).
- **iPhone**: the iOS client and Sign in with Apple, once the Apple developer
  account is approved. Until then the iPhone app shows email and password
  only, and an account made with Google cannot sign in on an iPhone.
- **Button style**: Google's guidelines ask for its "G" logo on the button.
  It is a plain text button for now.

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
