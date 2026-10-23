import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/partner.dart';
import '../domain/profile.dart';
import 'account_storage.dart';

class ReminderSettings {
  const ReminderSettings({
    this.periodReminder = true,
    this.periodReminderDaysBefore = 2,
    this.fertileWindowReminder = false,
    this.dailyLogReminder = true,
    this.dailyLogHour = 20,
    this.dailyLogMinute = 0,
  });

  final bool periodReminder;
  final int periodReminderDaysBefore;
  final bool fertileWindowReminder;
  final bool dailyLogReminder;
  final int dailyLogHour;
  final int dailyLogMinute;

  ReminderSettings copyWith({
    bool? periodReminder,
    int? periodReminderDaysBefore,
    bool? fertileWindowReminder,
    bool? dailyLogReminder,
    int? dailyLogHour,
    int? dailyLogMinute,
  }) =>
      ReminderSettings(
        periodReminder: periodReminder ?? this.periodReminder,
        periodReminderDaysBefore:
            periodReminderDaysBefore ?? this.periodReminderDaysBefore,
        fertileWindowReminder:
            fertileWindowReminder ?? this.fertileWindowReminder,
        dailyLogReminder: dailyLogReminder ?? this.dailyLogReminder,
        dailyLogHour: dailyLogHour ?? this.dailyLogHour,
        dailyLogMinute: dailyLogMinute ?? this.dailyLogMinute,
      );

  Map<String, Object?> toJson() => {
        'periodReminder': periodReminder,
        'periodReminderDaysBefore': periodReminderDaysBefore,
        'fertileWindowReminder': fertileWindowReminder,
        'dailyLogReminder': dailyLogReminder,
        'dailyLogHour': dailyLogHour,
        'dailyLogMinute': dailyLogMinute,
      };

  static ReminderSettings fromJson(Map<String, Object?> j) => ReminderSettings(
        periodReminder: j['periodReminder'] as bool? ?? true,
        periodReminderDaysBefore: j['periodReminderDaysBefore'] as int? ?? 2,
        fertileWindowReminder: j['fertileWindowReminder'] as bool? ?? false,
        dailyLogReminder: j['dailyLogReminder'] as bool? ?? true,
        dailyLogHour: j['dailyLogHour'] as int? ?? 20,
        dailyLogMinute: j['dailyLogMinute'] as int? ?? 0,
      );
}

class AppSettings {
  const AppSettings({
    this.reminders = const ReminderSettings(),
    this.sharing = const SharingPreferences(),
    this.profile = const UserProfile(),
    this.healthConnectEnabled = false,
    this.onboardingComplete = false,
  });

  final ReminderSettings reminders;
  final SharingPreferences sharing;
  final UserProfile profile;
  final bool healthConnectEnabled;
  final bool onboardingComplete;

  AppSettings copyWith({
    ReminderSettings? reminders,
    SharingPreferences? sharing,
    UserProfile? profile,
    bool? healthConnectEnabled,
    bool? onboardingComplete,
  }) =>
      AppSettings(
        reminders: reminders ?? this.reminders,
        sharing: sharing ?? this.sharing,
        profile: profile ?? this.profile,
        healthConnectEnabled:
            healthConnectEnabled ?? this.healthConnectEnabled,
        onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      );
}

/// One account's settings on this phone. With no account (nobody signed
/// in) it holds the defaults and saves nothing.
class SettingsStore {
  SettingsStore(String? accountId)
      : _key = accountId == null
            ? null
            : AccountStorage.key('mooncycle.settings.v1', accountId);

  final String? _key;

  Future<AppSettings> load() async {
    final key = _key;
    if (key == null) return const AppSettings();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return const AppSettings();
    final j = jsonDecode(raw) as Map<String, Object?>;
    return AppSettings(
      reminders: ReminderSettings.fromJson(
        (j['reminders'] as Map?)?.cast<String, Object?>() ?? const {},
      ),
      sharing: SharingPreferences.fromJson(
        (j['sharing'] as Map?)?.cast<String, Object?>() ?? const {},
      ),
      profile: UserProfile.fromJson(
        (j['profile'] as Map?)?.cast<String, Object?>() ?? const {},
      ),
      healthConnectEnabled: j['healthConnectEnabled'] as bool? ?? false,
      onboardingComplete: j['onboardingComplete'] as bool? ?? false,
    );
  }

  Future<void> save(AppSettings settings) async {
    final key = _key;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key,
      jsonEncode({
        'reminders': settings.reminders.toJson(),
        'sharing': settings.sharing.toJson(),
        'profile': settings.profile.toJson(),
        'healthConnectEnabled': settings.healthConnectEnabled,
        'onboardingComplete': settings.onboardingComplete,
      }),
    );
  }
}
