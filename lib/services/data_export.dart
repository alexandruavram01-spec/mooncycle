import 'dart:convert';

import 'package:share_plus/share_plus.dart';

import '../data/settings_store.dart';
import '../domain/day_key.dart';
import '../domain/her_chat.dart';
import '../domain/models.dart';

/// "Export my data": her logs and quiz answers as two files she keeps
/// wherever she chooses (Drive, email, her files), through the phone's share
/// sheet. Her logs live only on this phone, so this is her copy, and her
/// right to take her data elsewhere (UK GDPR, data portability).
class DataExport {
  DataExport._();

  /// One row per logged day, for a spreadsheet.
  static String csv(List<DayLog> logs) {
    final rows = <List<Object?>>[
      [
        'date',
        'flow',
        'symptoms',
        'energy (1-5)',
        'sleep (hours)',
        'temperature (°C)',
        'weight (kg)',
        'first day of period',
        'notes',
      ],
      for (final log in logs)
        [
          log.date.iso,
          log.flow.name,
          (log.symptoms.toList()..sort()).join('; '),
          log.energy,
          log.sleepHours,
          log.basalTemperature,
          log.weightKg,
          log.isPeriodStartOverride == true ? 'yes' : '',
          log.notes,
        ],
    ];
    return rows.map((row) => row.map(_cell).join(',')).join('\r\n');
  }

  /// Everything, in a form another app could read back, with her AI chat
  /// when she has one (it is kept only on this phone too).
  static String json(
    List<DayLog> logs,
    AppSettings settings, {
    ChatHistory chat = const ChatHistory(),
  }) =>
      const JsonEncoder.withIndent('  ').convert({
        'app': 'MoonCycle',
        'exported': DateTime.now().toUtc().toIso8601String(),
        'logs': [for (final log in logs) log.toMap()],
        'profile': settings.profile.toJson(),
        'reminders': settings.reminders.toJson(),
        'partnerSharing': settings.sharing.toJson(),
        if (chat.messages.isNotEmpty)
          'aiChat': [
            for (final m in chat.messages)
              if (m.notice == null)
                {
                  'at': m.at.toIso8601String(),
                  'from': m.fromHer ? 'me' : 'MoonCycle',
                  'text': m.text,
                },
          ],
      });

  /// Opens the share sheet with both files. True if she shared or saved
  /// them, false if she closed the sheet.
  static Future<bool> share(
    List<DayLog> logs,
    AppSettings settings, {
    ChatHistory chat = const ChatHistory(),
  }) async {
    final day = DayKey.today().iso;
    final result = await SharePlus.instance.share(
      ShareParams(
        subject: 'My MoonCycle data',
        files: [
          XFile.fromData(utf8.encode(csv(logs)), mimeType: 'text/csv'),
          XFile.fromData(
            utf8.encode(json(logs, settings, chat: chat)),
            mimeType: 'application/json',
          ),
        ],
        fileNameOverrides: [
          'mooncycle-logs-$day.csv',
          'mooncycle-data-$day.json',
        ],
      ),
    );
    return result.status == ShareResultStatus.success;
  }

  /// A spreadsheet cell: quoted when needed, and never read as a formula
  /// (a note starting with = or + would otherwise run in Excel).
  static String _cell(Object? value) {
    if (value == null) return '';
    var text = '$value';
    if (text.isNotEmpty && '=+-@'.contains(text[0]) && value is String) {
      text = "'$text";
    }
    if (text.contains(RegExp('[",\r\n]'))) {
      text = '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }
}
