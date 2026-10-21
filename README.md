# MoonCycle

A Flutter/Android period, symptom and hormone tracker with an opt-in partner view.

Local-only in this build: everything lives in SQLite on the device, there is no
account and nothing is uploaded.

## Getting it running

The `lib/` and `test/` code is complete; the Android platform folder still needs
generating (it is machine-specific, so it is not checked in).

```bash
cd C:\src\mooncycle_app

# 1. Generate android/ without clobbering the app code.
copy pubspec.yaml pubspec.backup.yaml
flutter create --org com.mooncycle --project-name mooncycle --platforms=android .
copy /Y pubspec.backup.yaml pubspec.yaml && del pubspec.backup.yaml

# 2. Dependencies and checks
flutter pub get
flutter analyze
flutter test

# 3. Run
flutter run
```

### Running outside Android

Android is the target, but the app also runs in a browser (`flutter run -d
chrome`) and on Windows for fast UI iteration. Several plugins have no
implementation there, so they are handled explicitly rather than crashing:

| Plugin | Web | Desktop |
| --- | --- | --- |
| `sqflite` | Not compiled at all — `PrefsLogRepository` is used instead | `sqflite_common_ffi` |
| `flutter_local_notifications` | No-op | No-op |
| `health` | "Only available on Android" | Same |

Storage is chosen by **conditional export** in `data/repository_factory.dart`,
not a `kIsWeb` check. `sqflite` cannot be compiled for web at all, so a runtime
branch would be far too late — the build fails first, and the symptom is a
blank page with no error. Keeping the SQLite import out of the web bundle
entirely is the only thing that works.

Reminders and wearables can only be tested on a real Android device.

Then merge `tool/AndroidManifest.additions.xml` into
`android/app/src/main/AndroidManifest.xml`, and set `minSdkVersion 26` in
`android/app/build.gradle` (Health Connect and the notification scheduler both
need it).

## How it is put together

```
lib/
  domain/          pure Dart, no Flutter imports — fully unit tested
    day_key.dart     timezone-safe calendar day
    enums.dart       flow, phases, symptom catalogue
    models.dart      DayLog, Cycle, PartnerSnapshot
    cycle_engine.dart  prediction + phase detection
    insights.dart    pattern detection across cycles
    partner.dart     sharing preferences + redaction
  data/            SQLite store, repositories, settings
  services/        Health Connect, local notifications, partner pairing
  state/           Riverpod providers
  ui/              screens and widgets
```

`domain/` deliberately has zero Flutter dependencies. That is what makes the
prediction logic testable without a device, and what will let the same code run
on a server if partner sync ever moves off-device.

### The prediction model

- Cycle length is the **median** of the last 6 cycles, not the mean — one month
  of forgotten logging otherwise drags the prediction by a week.
- Ovulation is counted **backwards** from the next predicted period using a
  fixed 14-day luteal phase. Counting forwards from the last period is the
  common shortcut and it falls apart on irregular cycles, because it is the
  follicular phase that varies, not the luteal one.
- Spotting does not start a cycle; bleeding within 15 days of the last start is
  treated as mid-cycle, not a new period. The user can override either way.
- A late period keeps showing as "n days late" for 10 days before the engine
  assumes a cycle went unlogged and projects forward.
- Confidence is surfaced in the UI rather than hidden: with two cycles logged it
  says so, instead of presenting a guess as fact.

### The partner feature

The design constraint was that this must not become surveillance. So:

- Sharing is **off** by default, and every field is a separate opt-in.
  Fertile-window sharing is off even when sharing is on.
- The partner receives a `PartnerSnapshot` — a redacted projection built in
  `partner.dart`. Raw logs and free-text notes are never included in the
  payload; `test/partner_test.dart` asserts this.
- Guidance is phrased as "may feel" / "often", never "she is", and the partner
  view ends with a line telling him to ask her rather than assume.
- Turning sharing off revokes access immediately.

## What is not built yet

- **Partner pairing needs a server.** The pairing code, the redacted payload
  and the privacy switches all exist; only the transport is missing. Swap the
  body of `PartnerLinkService` and nothing else changes.
- **Health Connect** is wired but unverified — it needs a physical device with
  Health Connect installed to test properly. HRV is not read: the RMSSD type
  is not exposed by the resolved `health` version and nothing consumes it yet.
- No onboarding flow, no data export, no perimenopause or pregnancy modes.

## Testing

```bash
flutter test
```

`test/cycle_engine_test.dart` covers DST-safe date maths, cycle derivation,
spotting vs. period, manual overrides, median/variance statistics, late-period
handling and phase boundaries. `test/partner_test.dart` covers redaction.

## A note on health claims

Predictions are estimates from the user's own history. The app says so on the
home screen. It is not contraception and not a medical device — if this ever
ships, that line needs to stay, and anything resembling diagnosis needs to stay
out.
