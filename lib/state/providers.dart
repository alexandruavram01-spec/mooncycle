import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/insight_memory_store.dart';
import '../data/log_repository.dart';
import '../data/repository_factory.dart';
import '../data/settings_store.dart';
import '../domain/cycle_engine.dart';
import '../domain/day_key.dart';
import '../domain/her_insights.dart';
import '../domain/insights.dart';
import '../domain/models.dart';
import '../domain/partner.dart';
import '../domain/profile.dart';
import '../l10n/app_language.dart';
import '../l10n/her_insights.dart';
import '../l10n/partner_messages.dart';
import '../legal.dart';
import '../services/account_service.dart';
import '../services/api_client.dart';
import '../services/health_service.dart';
import '../services/notification_service.dart';
import '../services/partner_link_service.dart';
import '../services/tip_library_service.dart';

/// The cycle and period length she gave in the quiz stand in until a full
/// cycle has been logged; after that the engine uses her own history.
final cycleEngineProvider = Provider<CycleEngine>(
  (ref) => _engineFor(ref.watch(profileProvider)),
);

CycleEngine _engineFor(UserProfile profile) => CycleEngine(
      defaultCycleLength: profile.cycleLength ?? 28,
      defaultPeriodLength: profile.periodLength ?? 5,
    );
final insightsEngineProvider = Provider((_) => const InsightsEngine());
final settingsStoreProvider = Provider((_) => SettingsStore());
final healthServiceProvider = Provider((_) => HealthService());
final notificationServiceProvider =
    Provider((_) => NotificationService.create());

/// SQLite on device, browser storage on web. Overridden in tests with
/// [InMemoryLogRepository].
final logRepositoryProvider =
    FutureProvider<LogRepository>((ref) => createLogRepository());

/// The single source of truth for logged days. Every screen reads from here,
/// so a change made in the log sheet is instantly reflected in the calendar,
/// the home wheel and the insights.
class LogsNotifier extends AsyncNotifier<List<DayLog>> {
  @override
  Future<List<DayLog>> build() async {
    final repo = await ref.watch(logRepositoryProvider.future);
    return repo.all();
  }

  Future<void> save(DayLog log) async {
    final repo = await ref.read(logRepositoryProvider.future);
    await repo.save(log);
    state = AsyncData(await repo.all());
    await _rescheduleReminders();
  }

  Future<void> deleteDay(DayKey day) async {
    final repo = await ref.read(logRepositoryProvider.future);
    await repo.delete(day);
    state = AsyncData(await repo.all());
    await _rescheduleReminders();
  }

  /// Removes every log from this device. Used when an account is deleted.
  Future<void> eraseAll() async {
    final repo = await ref.read(logRepositoryProvider.future);
    for (final log in await repo.all()) {
      await repo.delete(log.date);
    }
    state = AsyncData(await repo.all());
    await _rescheduleReminders();
  }

  /// Pulls wearable data and folds it into existing logs.
  Future<int> importFromHealthConnect({int daysBack = 30}) async {
    final health = ref.read(healthServiceProvider);
    final repo = await ref.read(logRepositoryProvider.future);
    final today = DayKey.today();
    final data = await health.fetchRange(
      from: today.addDays(-daysBack),
      to: today,
    );

    var imported = 0;
    for (final entry in data.entries) {
      final existing = await repo.forDay(entry.key) ?? DayLog(date: entry.key);
      final merged = HealthService.merge(existing, entry.value);
      if (!merged.isEmpty) {
        await repo.save(merged);
        imported++;
      }
    }
    state = AsyncData(await repo.all());
    return imported;
  }

  Future<void> _rescheduleReminders() async {
    final logs = state.valueOrNull;
    if (logs == null) return;
    final status = ref.read(cycleEngineProvider).status(logs);
    final settings = ref.read(settingsProvider).valueOrNull;
    if (settings == null) return;
    await ref
        .read(notificationServiceProvider)
        .reschedule(status: status, settings: settings.reminders);
  }
}

final logsProvider =
    AsyncNotifierProvider<LogsNotifier, List<DayLog>>(LogsNotifier.new);

/// Current cycle position and predictions. Recomputed whenever logs change.
final cycleStatusProvider = Provider<CycleStatus?>((ref) {
  final logs = ref.watch(logsProvider).valueOrNull;
  if (logs == null) return null;
  return ref.watch(cycleEngineProvider).status(logs);
});

final logByDayProvider = Provider.family<DayLog?, DayKey>((ref, day) {
  final logs = ref.watch(logsProvider).valueOrNull;
  if (logs == null) return null;
  for (final l in logs) {
    if (l.date == day) return l;
  }
  return null;
});

final patternsProvider = Provider<List<Pattern>>((ref) {
  final logs = ref.watch(logsProvider).valueOrNull ?? const <DayLog>[];
  return ref.watch(insightsEngineProvider).detectPatterns(logs);
});

final phaseAveragesProvider = Provider<List<PhaseAverages>>((ref) {
  final logs = ref.watch(logsProvider).valueOrNull ?? const <DayLog>[];
  return ref.watch(insightsEngineProvider).byPhase(logs);
});

final cycleLengthHistoryProvider = Provider<List<int>>((ref) {
  final logs = ref.watch(logsProvider).valueOrNull ?? const <DayLog>[];
  return ref.watch(insightsEngineProvider).cycleLengthHistory(logs);
});

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() => ref.watch(settingsStoreProvider).load();

  /// Not named `update` — `AsyncNotifier` already defines that with an
  /// incompatible signature.
  Future<void> replaceAll(AppSettings next) async {
    await ref.read(settingsStoreProvider).save(next);
    state = AsyncData(next);

    final logs = ref.read(logsProvider).valueOrNull;
    if (logs != null) {
      // Built directly rather than read from cycleEngineProvider, which now
      // depends on these settings — reading it from here would be circular.
      final status = _engineFor(next.profile).status(logs);
      await ref
          .read(notificationServiceProvider)
          .reschedule(status: status, settings: next.reminders);
    }
  }

  Future<void> updateSharing(SharingPreferences sharing) async {
    final current = state.valueOrNull ?? const AppSettings();
    await replaceAll(current.copyWith(sharing: sharing));
  }

  Future<void> updateReminders(ReminderSettings reminders) async {
    final current = state.valueOrNull ?? const AppSettings();
    await replaceAll(current.copyWith(reminders: reminders));
  }

  Future<void> updateProfile(UserProfile profile) async {
    final current = state.valueOrNull ?? const AppSettings();
    await replaceAll(current.copyWith(profile: profile));
  }
}

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

final profileProvider = Provider<UserProfile>(
  (ref) =>
      ref.watch(settingsProvider).valueOrNull?.profile ?? const UserProfile(),
);

/// Fertile days and ovulation are hidden everywhere unless this is on.
final showFertileDaysProvider = Provider<bool>(
  (ref) => ref.watch(profileProvider).showFertileDays,
);

final partnerSnapshotProvider = Provider<PartnerSnapshot?>((ref) {
  final status = ref.watch(cycleStatusProvider);
  final settings = ref.watch(settingsProvider).valueOrNull;
  if (status == null || settings == null || !status.hasData) return null;
  final todayLog = ref.watch(logByDayProvider(status.today));
  return buildPartnerSnapshot(
    status: status,
    prefs: settings.sharing,
    todayLog: todayLog,
    conceiving: settings.profile.goal == TrackingGoal.conceive,
  );
});

final apiClientProvider = Provider((_) => ApiClient());
final accountServiceProvider =
    Provider((ref) => AccountService(ref.watch(apiClientProvider)));
final partnerLinkServiceProvider =
    Provider((ref) => PartnerLinkService(ref.watch(apiClientProvider)));

/// The signed-in email, or null when nobody is signed in. The gate in
/// `main.dart` shows the account screen whenever this is null.
class SessionNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() {
    final api = ref.watch(apiClientProvider);
    api.onSessionLost = () => state = const AsyncData(null);
    return api.signedInEmail();
  }

  Future<void> signUp(String email, String password) async {
    state = AsyncData(
      await ref
          .read(accountServiceProvider)
          .signUp(email, password, termsVersion: Legal.version),
    );
  }

  Future<void> signIn(String email, String password) async {
    state = AsyncData(
      await ref.read(accountServiceProvider).signIn(email, password),
    );
  }

  /// Logs and quiz answers stay on the device; only the session ends.
  Future<void> signOut() async {
    await ref.read(accountServiceProvider).signOut();
    await ref.read(partnerLinkServiceProvider).forgetLocal();
    state = const AsyncData(null);
  }

  /// For test accounts: back to the first question with a clean slate. The
  /// account stays signed in. Server calls are best effort, so a reset still
  /// works offline.
  Future<void> startOver() async {
    final partner = ref.read(partnerLinkServiceProvider);
    try {
      await partner.revoke();
    } on ApiException {
      // Nothing to remove, or offline.
    }
    try {
      await partner.leave();
    } on ApiException {
      // Not anyone's partner, or offline.
    }
    await partner.forgetLocal();
    await ref.read(logsProvider.notifier).eraseAll();
    await ref.read(insightMemoryProvider.notifier).clear();
    await ref.read(settingsProvider.notifier).replaceAll(const AppSettings());
  }

  /// Deletes the account on the server, then erases this device as well, so
  /// "delete" leaves nothing behind in either place.
  /// [password] is null when the phone's own lock confirmed it.
  Future<void> deleteAccount({String? password}) async {
    await ref.read(accountServiceProvider).deleteAccount(password: password);
    await ref.read(partnerLinkServiceProvider).forgetLocal();
    await ref.read(logsProvider.notifier).eraseAll();
    await ref.read(insightMemoryProvider.notifier).clear();
    await ref.read(settingsProvider.notifier).replaceAll(const AppSettings());
    state = const AsyncData(null);
  }
}

final sessionProvider =
    AsyncNotifierProvider<SessionNotifier, String?>(SessionNotifier.new);

/// Whether the signed-in account has agreed to the current terms and given
/// consent for health data. Remembered per account on the device, so the
/// app opens offline; asked from the server otherwise, so agreeing on one
/// device counts on all of them.
class LegalConsentNotifier extends AsyncNotifier<bool> {
  String _key(String account) => 'mooncycle.legal.accepted.$account';

  @override
  Future<bool> build() async {
    final account = ref.watch(sessionProvider).valueOrNull;
    if (account == null) return false;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_key(account)) == Legal.version) return true;
    try {
      final accepted =
          await ref.read(accountServiceProvider).acceptedTermsVersion();
      if (accepted != Legal.version) return false;
    } on ApiException {
      return false;
    }
    await prefs.setString(_key(account), Legal.version);
    return true;
  }

  Future<void> accept() async {
    final account = ref.read(sessionProvider).valueOrNull;
    if (account == null) return;
    await ref.read(accountServiceProvider).recordConsent(Legal.version);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(account), Legal.version);
    state = const AsyncData(true);
  }
}

final legalConsentProvider =
    AsyncNotifierProvider<LegalConsentNotifier, bool>(LegalConsentNotifier.new);

/// Keeps her daily "today's tip for your partner" notification on while she
/// shares her phase with a connected partner, and off otherwise. Phones only;
/// a no-op in the browser.
final partnerTipReminderProvider = Provider<void>((ref) {
  final sharing = ref.watch(
    settingsProvider.select((s) => s.valueOrNull?.sharing),
  );
  final role = ref.watch(profileProvider.select((p) => p.role));

  var on = false;
  if (role == AppRole.tracker &&
      sharing != null &&
      sharing.enabled &&
      sharing.sharePhase) {
    // Only watched while sharing is on, so it never triggers a pairing
    // request for someone who does not share.
    on = ref.watch(pairingProvider).valueOrNull?.linked ?? false;
  }
  ref
      .read(notificationServiceProvider)
      .setPartnerTipReminder(on: on)
      .catchError((Object _) {});
});

/// The test accounts are the only ones whose name is not an email address
/// (see BEFORE_LAUNCH.md). They get a "Start over" button.
final isTestAccountProvider = Provider<bool>((ref) {
  final name = ref.watch(sessionProvider).valueOrNull;
  return name != null && !name.contains('@');
});

final tipLibraryServiceProvider =
    Provider((ref) => TipLibraryService(ref.watch(apiClientProvider)));

/// Codes of the daily tips someone flagged "not okay", which nobody gets
/// until an editor puts them back. Empty when signed out or offline.
final pulledTipsProvider = FutureProvider<Set<String>>((ref) async {
  if (ref.watch(sessionProvider).valueOrNull == null) return const <String>{};
  try {
    return await ref.watch(tipLibraryServiceProvider).pulled();
  } on ApiException {
    return const <String>{};
  }
});

/// The language this person chose, kept on the device and separate from
/// the other settings, so signing out or starting over keeps it. Null until
/// chosen: the gate in `main.dart` asks before anything else.
class LanguageNotifier extends AsyncNotifier<AppLanguage?> {
  static const _key = 'mooncycle.language';

  @override
  Future<AppLanguage?> build() async {
    final prefs = await SharedPreferences.getInstance();
    return AppLanguage.fromCode(prefs.getString(_key));
  }

  Future<void> choose(AppLanguage language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, language.code);
    state = AsyncData(language);
  }
}

final languageProvider =
    AsyncNotifierProvider<LanguageNotifier, AppLanguage?>(LanguageNotifier.new);

/// Partner tips and one-tap messages in this person's language. Nothing that
/// uses them shows before a language is chosen, so the fallback is never
/// seen.
final partnerMessagesProvider = Provider<PartnerMessages>(
  (ref) => PartnerMessages.of(
    ref.watch(languageProvider).valueOrNull ?? AppLanguage.enInt,
  ),
);

/// Whether the signed-in account may draft and approve tips.
final isEditorProvider = FutureProvider<bool>((ref) async {
  if (ref.watch(sessionProvider).valueOrNull == null) return false;
  try {
    return await ref.watch(tipLibraryServiceProvider).isEditor();
  } on ApiException {
    return false;
  }
});

/// Her side of the pairing. The current snapshot is published as soon as the
/// pairing is known, because issuing a code clears whatever the server held.
final pairingProvider = FutureProvider<PairingState>((ref) async {
  final service = ref.watch(partnerLinkServiceProvider);
  final state = await service.pairing();
  final snapshot = ref.read(partnerSnapshotProvider);
  if (snapshot != null) {
    try {
      await service.publishSnapshot(snapshot);
    } on ApiException {
      // Retried by partnerSyncProvider on the next change.
    }
  }
  return state;
});

/// Keeps the server in step with what she has chosen to share: the redacted
/// snapshot is uploaded whenever it changes, and switching sharing off removes
/// it from the server straight away.
final partnerSyncProvider = Provider<void>((ref) {
  final service = ref.watch(partnerLinkServiceProvider);

  // Failures are deliberately quiet: an upload is retried on the next change,
  // and a failed revoke on the next launch.
  void quietly(Future<void> Function() action) {
    action().catchError((Object _) {});
  }

  ref.listen<PartnerSnapshot?>(partnerSnapshotProvider, (_, snapshot) {
    final sharing = ref.read(settingsProvider).valueOrNull?.sharing;
    if (snapshot == null || sharing == null || !sharing.enabled) return;
    quietly(() => service.publishSnapshot(snapshot));
  }, fireImmediately: true);

  // His side: report the tone he picked, so her app can show her the tip he
  // sees today.
  ref.listen<UserProfile>(profileProvider, (_, profile) {
    if (profile.role != AppRole.partner) return;
    quietly(() => service.shareTone(profile.partnerTone));
  }, fireImmediately: true);

  ref.listen<AsyncValue<AppSettings>>(settingsProvider, (previous, next) {
    final enabled = next.valueOrNull?.sharing.enabled;
    if (enabled == null) return;
    final wasEnabled = previous?.valueOrNull?.sharing.enabled;
    if (wasEnabled == true && !enabled) {
      quietly(service.revoke);
    } else if (wasEnabled == null && !enabled) {
      quietly(service.retryRevoke);
    }
  }, fireImmediately: true);
});

// ---- Insight cards for her ---------------------------------------------------

/// The cards are not clinically approved yet, so only the test accounts see
/// them. Once a clinician has signed them off, this becomes "trackers only".
final herInsightsEnabledProvider = Provider<bool>(
  (ref) =>
      ref.watch(isTestAccountProvider) &&
      ref.watch(profileProvider).role == AppRole.tracker,
);

/// Which cards were shown when, which she hid, and today's choice. On the
/// device only.
class InsightMemoryNotifier extends AsyncNotifier<InsightMemory> {
  final _store = InsightMemoryStore();

  @override
  Future<InsightMemory> build() => _store.load();

  Future<void> save(InsightMemory memory) async {
    state = AsyncData(memory);
    await _store.save(memory);
  }

  InsightMemory get _current => state.valueOrNull ?? const InsightMemory();

  /// Closed with the cross: gone for today, back after its cooldown.
  Future<void> dismiss(String id) => save(
        _current.copyWith(dismissed: {..._current.dismissed, id}),
      );

  /// "Not relevant to me": never again, unless she brings hidden cards back.
  Future<void> markNotRelevant(String id) => save(
        _current.copyWith(notRelevant: {..._current.notRelevant, id}),
      );

  Future<void> restoreHidden() =>
      save(_current.copyWith(notRelevant: const {}));

  Future<void> setScreeningReminders(bool on) =>
      save(_current.copyWith(screeningReminders: on));

  Future<void> clear() async {
    state = const AsyncData(InsightMemory());
    await _store.clear();
  }
}

final insightMemoryProvider =
    AsyncNotifierProvider<InsightMemoryNotifier, InsightMemory>(
  InsightMemoryNotifier.new,
);

/// Every card that applies today. Worked out on her phone from her logs.
final herInsightCandidatesProvider = Provider<List<InsightCandidate>>((ref) {
  final logs = ref.watch(logsProvider).valueOrNull;
  final status = ref.watch(cycleStatusProvider);
  final screening = ref.watch(
    insightMemoryProvider.select((m) => m.valueOrNull?.screeningReminders),
  );
  if (logs == null || status == null || screening == null) return const [];
  return const HerInsightPicker().candidates(
    InsightContext(
      today: status.today,
      status: status,
      logs: logs,
      profile: ref.watch(profileProvider),
      screeningReminders: screening,
      engine: ref.watch(cycleEngineProvider),
    ),
  );
});

/// Her cards and the "Get help now" page, in her language.
final herInsightTextsProvider = Provider<HerInsightTexts>(
  (ref) => HerInsightTexts.of(
    ref.watch(languageProvider).valueOrNull ?? AppLanguage.enGB,
  ),
);
