# Google and Apple sign-in: accounts setup

## Status (22 October 2026)

- Google Cloud project `MoonCycle`, consent screen In production, External.
- Clients made: `MoonCycle server` (web, ID
  `531774189485-hqam3gqj4ola0p2b277u2e87sv8es266.apps.googleusercontent.com`,
  in `lib/services/google_account.dart` and `server/server.js`),
  `MoonCycle Android (debug)` and `MoonCycle Android (upload)`.
- **Still to do:** `MoonCycle Android (Play)` with the App signing key SHA-1
  from Play Console (Test and release, App integrity), after the first
  upload. Until then Google sign-in fails in builds installed from Play.
- Continue with Google works on Android (Play build tested 23 October 2026).
- iPhone, prepared 26 October 2026: Sign in with Apple is built (app button,
  server route `POST /api/session/apple`, entitlement in
  `ios/Runner/Runner.entitlements`). Google on iPhone: client `MoonCycle iPhone`
  (531774189485-d3phbm38s9tbget6rj5qvl1gbicv3c4o.apps.googleusercontent.com,
  Team ID 4889D8DM69, App Store ID 6827181527), set in
  `GoogleAccount.iosClientId`, as a URL scheme in `ios/Runner/Info.plist`,
  and in the server's default `GOOGLE_CLIENT_IDS` (26 October 2026).
- The Apple key for cancelling Apple's link on deletion: DEPLOY.md,
  "Sign in with Apple on the server".
- Known gap: an account made with Apple cannot sign in on Android yet (Apple
  sign-in on Android needs a web flow).
- A Google sign-in whose email already has a password account is refused,
  not joined to it: emails are not confirmed for password accounts.

Done once, by hand, before the sign-in code is built. Use the company's
accounts (IONCODEX LTD) where you can: these are hard to move later.

What to send back in chat is marked **Send**. Client IDs, Team ID and Key ID
are not secrets. The Apple `.p8` key file **is** a secret: never paste it in
chat; it goes only onto the server.

Google sign-in is for the Android and iPhone apps. Apple sign-in is for the
iPhone app only (Apple requires it there once Google is offered).

## Google

1. Go to <https://console.cloud.google.com>, signed in with the account that
   should own MoonCycle. Top bar, project picker, **New project**, name
   `MoonCycle`, Create, then select it.
2. Menu, **Google Auth Platform** (also called "OAuth consent screen"),
   **Get started**:
   - App name `MoonCycle`; user support email: yours.
   - Audience: **External**.
   - Contact email: yours. Agree, Create.
3. **Branding**:
   - Home page `https://mooncycle.fit`
   - Privacy policy `https://mooncycle.fit/privacy.html`
   - Terms of service `https://mooncycle.fit/terms.html`
   - Authorised domain `mooncycle.fit`
   - Skip the logo for now: adding one sends the app to Google for a brand
     check first.
   Save.
4. **Data access**: add nothing. Sign-in only needs the basic
   email and profile, which need no review.
5. **Audience**: **Publish app** (to "In production"), so anyone can sign
   in, not only listed test users.
6. **Clients**, **Create client**, three times:
   1. **Web application**, name `MoonCycle server`. No URLs. Create.
      **Send:** its Client ID (ends in `.apps.googleusercontent.com`).
      Ignore the client secret; it is not needed.
   2. **iOS**, name `MoonCycle iPhone`, bundle ID `com.ioncodex.mooncycle`,
      Team ID from developer.apple.com, Account, Membership details. Create.
      **Send:** its Client ID.
   3. **Android**, name `MoonCycle Android (debug)`, package
      `com.ioncodex.mooncycle`, and the SHA-1 of this PC's debug key, shown by:
      ```
      keytool -list -v -keystore $env:USERPROFILE\.android\debug.keystore -alias androiddebugkey -storepass android -keypass android
      ```
      (copy the `SHA1:` line). Nothing to send for Android clients.
7. Later, when the Android release key exists (Play setup), add two more
   Android clients the same way: one with the upload key's SHA-1, one with
   the **App signing key** SHA-1 from Play Console, Test and release, App
   integrity. Without them, Google sign-in fails in store builds only.

## Apple

1. <https://developer.apple.com/account>, **Certificates, Identifiers &
   Profiles**, **Identifiers**, open `com.ioncodex.mooncycle`.
2. Tick **Sign In with Apple** (leave "Enable as a primary App ID"). Save,
   Confirm. Codemagic picks this up on its next build.
3. **Keys**, **+**:
   - Name `MoonCycle Sign in with Apple`.
   - Tick **Sign in with Apple**, **Configure**, primary App ID
     `com.ioncodex.mooncycle`, Save.
   - Continue, Register, **Download**. The file `AuthKey_XXXXXXXXXX.p8` can
     be downloaded only once: keep it next to your other keys in `C:\src`.
   This key lets the server cancel Apple's link when someone deletes their
   account, which Apple requires.
4. **Send:** the Key ID (on the key's page) and your Team ID. Not the file.

## After that

I build the sign-in, then give you the steps to put the `.p8` key on the
server (`/etc/`, readable only by the API).
