import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/settings_store.dart';
import '../domain/cycle_engine.dart';
import '../domain/day_key.dart';
import '../l10n/ui.dart';

/// Local, on-device reminders. No server, no push token.
class NotificationService {
  NotificationService(this._plugin);

  factory NotificationService.create() =>
      NotificationService(FlutterLocalNotificationsPlugin());

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  /// False on desktop, where the plugin has no implementation. Every public
  /// method becomes a no-op rather than throwing, so the app stays runnable on
  /// Windows for UI work without littering call sites with platform checks.
  bool _supported = true;

  // Stable IDs so rescheduling replaces rather than duplicates.
  static const int _periodId = 100;
  static const int _fertileId = 101;
  static const int _dailyId = 102;
  static const int _partnerTipId = 103;

  static const AndroidNotificationDetails _partnerChannel =
      AndroidNotificationDetails(
    'partner_tips',
    'Partner tips',
    channelDescription: "A daily look at the tip your partner got",
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  static const AndroidNotificationDetails _cycleChannel =
      AndroidNotificationDetails(
    'cycle_reminders',
    'Cycle reminders',
    channelDescription: 'Upcoming period and fertile window reminders',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  static const AndroidNotificationDetails _logChannel =
      AndroidNotificationDetails(
    'log_reminders',
    'Daily logging',
    channelDescription: 'A nudge to log how today felt',
    importance: Importance.low,
    priority: Priority.low,
  );

  Future<void> init() async {
    if (_ready) return;
    // `kIsWeb` must be checked first: `defaultTargetPlatform` reports the
    // underlying OS in a browser, so on Android Chrome it would say "android"
    // and we would try to schedule notifications that cannot exist.
    final supported = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (!supported) {
      _supported = false;
      _ready = true;
      return;
    }
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _ready = true;
  }

  Future<bool> requestPermissions() async {
    await init();
    if (!_supported) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission();
    return granted ?? false;
  }

  Future<void> cancelAll() async {
    await init();
    if (!_supported) return;
    await _plugin.cancelAll();
  }

  /// Recomputes every scheduled reminder from the current prediction.
  /// Call after any log change so a shifted cycle moves the reminders too.
  Future<void> reschedule({
    required CycleStatus status,
    required ReminderSettings settings,
  }) async {
    await init();
    if (!_supported) return;
    await _plugin.cancel(_periodId);
    await _plugin.cancel(_fertileId);
    await _plugin.cancel(_dailyId);

    final nextStart = status.predictedNextStart;

    if (settings.periodReminder && nextStart != null) {
      final when = nextStart.addDays(-settings.periodReminderDaysBefore);
      await _scheduleAt(
        id: _periodId,
        day: when,
        hour: 9,
        title: tr('Your period is coming'),
        body: settings.periodReminderDaysBefore == 1
            ? tr('Expected tomorrow. Worth having what you need to hand.')
            : trCount(settings.periodReminderDaysBefore, 'Expected in {n} day.',
                'Expected in {n} days.'),
        details: _cycleChannel,
      );
    }

    if (settings.fertileWindowReminder && status.fertileWindowStart != null) {
      await _scheduleAt(
        id: _fertileId,
        day: status.fertileWindowStart!,
        hour: 9,
        title: tr('Fertile window starts today'),
        body: tr('Based on your recent cycles. Predictions are estimates, not '
            'contraception.'),
        details: _cycleChannel,
      );
    }

    if (settings.dailyLogReminder) {
      await _scheduleDaily(
        id: _dailyId,
        hour: settings.dailyLogHour,
        minute: settings.dailyLogMinute,
        title: tr('How did today feel?'),
        body: tr('A few taps keeps your predictions sharp.'),
      );
    }
  }

  /// Once a day, a prompt to look at the tip her partner got and flag it if
  /// it does not feel right. On only while she shares her phase with a
  /// connected partner.
  Future<void> setPartnerTipReminder({required bool on}) async {
    await init();
    if (!_supported) return;
    await _plugin.cancel(_partnerTipId);
    if (!on) return;
    await _scheduleDaily(
      id: _partnerTipId,
      hour: 10,
      minute: 0,
      title: '💌 ${tr("Today's tip for your partner")}',
      body: tr('Have a look, and flag it if it does not feel right.'),
      details: _partnerChannel,
    );
  }

  Future<void> _scheduleAt({
    required int id,
    required DayKey day,
    required int hour,
    required String title,
    required String body,
    required AndroidNotificationDetails details,
  }) async {
    final when = tz.TZDateTime.local(day.year, day.month, day.day, hour);
    if (when.isBefore(tz.TZDateTime.now(tz.local))) return;
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      when,
      NotificationDetails(android: details),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> _scheduleDaily({
    required int id,
    required int hour,
    required int minute,
    required String title,
    required String body,
    AndroidNotificationDetails details = _logChannel,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var when =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!when.isAfter(now)) when = when.add(const Duration(days: 1));

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      when,
      NotificationDetails(android: details),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      // The reminder should fire at 20:00 wall-clock time wherever the user
      // is, so the scheduled time is interpreted absolutely rather than
      // shifted when they travel.
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }
}
