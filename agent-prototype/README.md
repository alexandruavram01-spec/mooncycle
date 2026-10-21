# Her daily note: AI prototype

A first look at the stage 2 agent, before anything is built for real users.
It writes the daily note for 18 invented situations, checks each one, and
saves a review file for you and the clinician: `samples/latest.md`.

**Only invented data.** The privacy policy promises that personal data is
not sent to AI services, so never put a real person's log, including a test
account's, into `scenarios.mjs`.

## How it works

- Her phone's rules still decide **what** is said: which reviewed card
  (`content/her-insights-en-GB-combined.json`) and whether anything is urgent.
- The agent (Claude Opus 5.5) only decides **how**: it rewrites that card
  around her day, from a short summary her phone works out.
- The card's reviewed "See a GP" and "Get help now" text stays word for word
  under the note; the agent is told to leave those out.
- Every note is checked twice: by rules in `checks.mjs` (no condition the card
  does not name, no pregnancy unless the sources raise it, no medicines, no
  numbers that are not in the sources, no certainty about estimates, no
  disappointment while trying to conceive, at most 70 words...), and by a
  second reading by the model against the card.
- If the model's safety checks decline a request, Anthropic's recommended
  fallback model answers instead (the `fallbacks: "default"` setting).

## Running it (PowerShell, in this folder)

1. Install once (`npm.cmd`, because Windows blocks npm's PowerShell
   launcher):
   ```
   npm.cmd install
   ```
2. See what would be sent, without calling anything or paying:
   ```
   node run.mjs --dry-run
   ```
3. Set the API key for this terminal only (it is not saved anywhere):
   ```
   $env:ANTHROPIC_API_KEY = "paste the key here"
   ```
4. Run all 18 scenarios:
   ```
   node run.mjs
   ```
   A full run makes 36 requests and costs about $0.25; the exact
   estimate is printed at the end. One scenario:
   `node run.mjs --only=good-day`. Without the second reading:
   `--no-judge`.

The key comes from an Anthropic account in the company's name
(console.anthropic.com, API keys). Never paste it into chat or a file in
this repository.

## What to look at in `samples/latest.md`

For each note: is it accurate to the card, is the tone right, would a
clinician change anything? Notes that fail a check are marked FAILED with
the words that tripped it.
