import 'cycle_engine.dart';
import 'day_key.dart';
import 'enums.dart';
import 'models.dart';
import 'profile.dart';

/// Messages the app adds to her chat itself. Shown in her language, never
/// sent to the server.
enum ChatNotice {
  /// No answer came: no connection, or the server could not write one.
  failed,

  /// Today's 20 messages are used up.
  limit,
}

/// One message in her AI chat.
class ChatMessage {
  const ChatMessage({
    required this.fromHer,
    required this.text,
    required this.at,
    this.ai = false,
    this.urgent = false,
    this.notice,
    this.reported = false,
    this.suggestions = const [],
    this.opener = false,
  });

  /// A notice from the app; [text] is empty and is shown from [kind].
  ChatMessage.notice(ChatNotice kind)
      : this(fromHer: false, text: '', at: DateTime.now(), notice: kind);

  final bool fromHer;
  final String text;
  final DateTime at;

  /// Written by the AI: labelled as such, and she can report it.
  final bool ai;

  /// An answer that sends her to Get help now.
  final bool urgent;

  /// Set for a message the app added, which is never sent to the server.
  final ChatNotice? notice;

  /// She reported this answer.
  final bool reported;

  /// Follow-up questions she can tap.
  final List<String> suggestions;

  /// Today's first message, about today's card or her cycle.
  final bool opener;

  DayKey get day => DayKey.fromDateTime(at);

  ChatMessage copyWith({bool? reported}) => ChatMessage(
        fromHer: fromHer,
        text: text,
        at: at,
        ai: ai,
        urgent: urgent,
        notice: notice,
        reported: reported ?? this.reported,
        suggestions: suggestions,
        opener: opener,
      );

  Map<String, Object?> toJson() => {
        'her': fromHer,
        'text': text,
        'at': at.toIso8601String(),
        if (ai) 'ai': true,
        if (urgent) 'urgent': true,
        if (notice != null) 'notice': notice!.name,
        if (reported) 'reported': true,
        if (suggestions.isNotEmpty) 'suggestions': suggestions,
        if (opener) 'opener': true,
      };

  static ChatMessage? fromJson(Object? json) {
    if (json is! Map) return null;
    final text = json['text'];
    final at = DateTime.tryParse('${json['at']}');
    if (text is! String || at == null) return null;
    return ChatMessage(
      fromHer: json['her'] == true,
      text: text,
      at: at,
      ai: json['ai'] == true,
      urgent: json['urgent'] == true,
      notice: ChatNotice.values.asNameMap()[json['notice']],
      reported: json['reported'] == true,
      suggestions: [
        for (final s in (json['suggestions'] as List?) ?? const [])
          if (s is String) s,
      ],
      opener: json['opener'] == true,
    );
  }
}

/// Her chat on this phone: the messages, and the day she last opened it.
class ChatHistory {
  const ChatHistory({this.messages = const [], this.openedDay});

  final List<ChatMessage> messages;
  final DayKey? openedDay;

  /// How much is kept on the phone.
  static const keepDays = 60;
  static const keepMessages = 400;

  /// Whether today's message is waiting for her.
  bool unread(DayKey today) => openedDay != today;

  /// Today's messages, oldest first.
  List<ChatMessage> on(DayKey day) =>
      [for (final m in messages) if (m.day == day) m];

  ChatHistory copyWith({List<ChatMessage>? messages, DayKey? openedDay}) {
    var kept = messages ?? this.messages;
    final cutoff =
        DateTime.now().subtract(const Duration(days: keepDays));
    kept = [for (final m in kept) if (m.at.isAfter(cutoff)) m];
    if (kept.length > keepMessages) {
      kept = kept.sublist(kept.length - keepMessages);
    }
    return ChatHistory(messages: kept, openedDay: openedDay ?? this.openedDay);
  }

  Map<String, Object?> toJson() => {
        'opened': openedDay?.iso,
        'messages': [for (final m in messages) m.toJson()],
      };

  factory ChatHistory.fromJson(Map<String, Object?> json) {
    final opened = json['opened'];
    return ChatHistory(
      openedDay: opened is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(opened)
          ? DayKey.parse(opened)
          : null,
      messages: [
        for (final m in (json['messages'] as List?) ?? const [])
          if (ChatMessage.fromJson(m) case final message?) message,
      ],
    );
  }
}

/// What the chat may know about her cycle, worked out on her phone: the
/// day and phase, estimated dates, typical lengths, today's card and what
/// she logged in the last 14 days (names and how many days only). Never her
/// notes, temperature, weight or anything about her account.
Map<String, Object?> herChatContext({
  required DayKey today,
  required CycleStatus? status,
  required List<DayLog> logs,
  required UserProfile profile,
  String? card,
}) {
  List<String> items(DayLog log) => [
        if (log.flow != FlowIntensity.none) '${log.flow.name} flow',
        ...log.symptoms,
      ];
  final from = today.addDays(-13);
  final counts = <String, int>{};
  DayLog? todays;
  for (final log in logs) {
    if (log.date == today) todays = log;
    if (log.date.compareTo(from) < 0 || log.date.compareTo(today) > 0) {
      continue;
    }
    for (final item in items(log)) {
      counts[item] = (counts[item] ?? 0) + 1;
    }
  }
  return {
    'today': today.iso,
    'goal': profile.goal == TrackingGoal.conceive ? 'conceive' : 'track',
    'fertility': profile.journey == 'fertility' || profile.showFertileDays,
    'cycle': status != null && status.hasData
        ? {
            'day': status.dayOfCycle.clamp(1, 400),
            'phase': status.phase.name,
            'nextPeriod': status.predictedNextStart?.iso,
            'typicalCycle': status.typicalCycleLength.clamp(10, 120),
            'typicalPeriod': status.typicalPeriodLength.clamp(1, 20),
            'completedCycles': status.completedCycles.clamp(0, 500),
          }
        : null,
    'todayLogged': todays == null ? const <String>[] : items(todays),
    'recent': [
      for (final MapEntry(:key, :value) in counts.entries)
        {'item': key, 'days': value.clamp(1, 14)},
    ],
    'card': card,
  };
}

/// The last messages of today's chat, oldest first, as the server takes
/// them: at most 10, within its length limits, ending with hers.
List<Map<String, Object?>> chatRequestMessages(List<ChatMessage> today) {
  const maxMessages = 10;
  const budget = 4000;
  final out = <Map<String, Object?>>[];
  var used = 0;
  for (final m in today.reversed) {
    // The app's own notices are not part of the conversation.
    if (m.notice != null) continue;
    final limit = m.fromHer ? 500 : 800;
    final text = m.text.trim();
    if (text.isEmpty) continue;
    final clipped = text.length > limit ? text.substring(0, limit) : text;
    if (out.length == maxMessages || used + clipped.length > budget) break;
    used += clipped.length;
    out.insert(0, {'role': m.fromHer ? 'user' : 'assistant', 'text': clipped});
  }
  return out;
}
