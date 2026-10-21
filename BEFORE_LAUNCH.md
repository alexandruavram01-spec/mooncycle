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
- **Privacy policy**, naming what the account holds and what partner sharing
  sends.

## Server

- **Root SSH by password.** Logins currently use the root password. Switch to
  key-only login.
- **Search engines.** nginx sends `X-Robots-Tag: noindex`. Decide whether the
  public site should be indexed.

## Android

- **App ID** is still `com.example.mooncycle`, and release builds are signed
  with the debug key. Both must change for Google Play.
