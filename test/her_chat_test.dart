import 'package:flutter_test/flutter_test.dart';
import 'package:mooncycle/domain/cycle_engine.dart';
import 'package:mooncycle/domain/day_key.dart';
import 'package:mooncycle/domain/enums.dart';
import 'package:mooncycle/domain/her_chat.dart';
import 'package:mooncycle/domain/models.dart';
import 'package:mooncycle/domain/profile.dart';

void main() {
  const engine = CycleEngine();
  final today = DayKey(2026, 10, 30);

  List<DayLog> period(DayKey start) => List.generate(
        5,
        (i) => DayLog(date: start.addDays(i), flow: FlowIntensity.medium),
      );

  test('the context holds her cycle and the last 14 days, nothing else', () {
    final logs = [
      ...period(DayKey(2026, 9, 1)),
      ...period(DayKey(2026, 9, 29)),
      ...period(DayKey(2026, 10, 27)).take(4).map(
        (log) => log.date == today
            ? DayLog(
                date: today,
                flow: FlowIntensity.light,
                symptoms: const {'Cramps'},
                notes: 'private',
                weightKg: 60,
              )
            : log,
      ),
      // Older than 14 days: left out of "recent".
      DayLog(date: DayKey(2026, 10, 1), symptoms: const {'Headache'}),
    ];
    final context = herChatContext(
      today: today,
      status: engine.status(logs, today: today),
      logs: logs,
      profile: const UserProfile(),
      card: 'I01',
    );

    expect(context['today'], '2026-10-30');
    expect(context['goal'], 'track');
    expect(context['card'], 'I01');
    final cycle = context['cycle']! as Map;
    expect(cycle['day'], 4);
    expect(cycle['phase'], 'menstrual');
    expect(context['todayLogged'], ['light flow', 'Cramps']);
    final recent = {
      for (final r in context['recent']! as List) (r as Map)['item']: r['days'],
    };
    expect(recent, {'medium flow': 3, 'light flow': 1, 'Cramps': 1});
    // Never her notes or weight.
    expect(context.toString(), isNot(contains('private')));
    expect(context.toString(), isNot(contains('60.0')));
  });

  test('with no period logged there is no cycle', () {
    final context = herChatContext(
      today: today,
      status: null,
      logs: const [],
      profile: const UserProfile(),
    );
    expect(context['cycle'], isNull);
    expect(context['recent'], isEmpty);
  });

  ChatMessage message(bool hers, String text, {ChatNotice? notice}) =>
      ChatMessage(
        fromHer: hers,
        text: text,
        at: DateTime(2026, 10, 30, 9),
        notice: notice,
      );

  test('requests skip notices, keep the latest and end with hers', () {
    final today = [
      message(false, 'Opener'),
      message(true, 'First'),
      message(false, '', notice: ChatNotice.failed),
      message(true, 'Again'),
    ];
    expect(chatRequestMessages(today), [
      {'role': 'assistant', 'text': 'Opener'},
      {'role': 'user', 'text': 'First'},
      {'role': 'user', 'text': 'Again'},
    ]);

    final many = [
      for (var i = 0; i < 30; i++) message(i.isOdd, 'm$i'),
    ];
    final sent = chatRequestMessages(many);
    expect(sent.length, 10);
    expect(sent.last, {'role': 'user', 'text': 'm29'});
  });

  test('the history survives saving and loading', () {
    final history = ChatHistory(
      openedDay: today,
      messages: [
        ChatMessage(
          fromHer: false,
          text: 'Hello',
          at: DateTime.now(),
          ai: true,
          urgent: true,
          suggestions: const ['More?'],
          opener: true,
        ),
        ChatMessage.notice(ChatNotice.limit),
      ],
    );
    final loaded = ChatHistory.fromJson(history.toJson());
    expect(loaded.openedDay, today);
    expect(loaded.unread(today), isFalse);
    expect(loaded.unread(today.addDays(1)), isTrue);
    final first = loaded.messages.first;
    expect(
      [first.text, first.ai, first.urgent, first.suggestions, first.opener],
      ['Hello', true, true, ['More?'], true],
    );
    expect(loaded.messages.last.notice, ChatNotice.limit);
  });

  test('old messages are not kept', () {
    final old = ChatMessage(
      fromHer: true,
      text: 'Old',
      at: DateTime.now().subtract(const Duration(days: 61)),
    );
    final fresh = ChatMessage(fromHer: true, text: 'New', at: DateTime.now());
    final history = const ChatHistory().copyWith(messages: [old, fresh]);
    expect(history.messages.map((m) => m.text), ['New']);
  });
}
