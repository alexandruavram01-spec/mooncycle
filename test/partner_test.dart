import 'package:flutter_test/flutter_test.dart';
import 'package:mooncycle/domain/cycle_engine.dart';
import 'package:mooncycle/domain/day_key.dart';
import 'package:mooncycle/domain/enums.dart';
import 'package:mooncycle/domain/models.dart';
import 'package:mooncycle/domain/partner.dart';
import 'package:mooncycle/domain/partner_tips.dart';
import 'package:mooncycle/domain/profile.dart';
import 'package:mooncycle/l10n/app_language.dart';
import 'package:mooncycle/l10n/partner_messages.dart';
import 'package:mooncycle/services/partner_link_service.dart';

void main() {
  const engine = CycleEngine();

  List<DayLog> period(DayKey start) => List.generate(
        5,
        (i) => DayLog(date: start.addDays(i), flow: FlowIntensity.medium),
      );

  final logs = [
    ...period(const DayKey(2024, 1, 1)),
    ...period(const DayKey(2024, 1, 29)),
    ...period(const DayKey(2024, 2, 26)),
    DayLog(
      date: const DayKey(2024, 3, 10),
      symptoms: const {'Cramps', 'Irritable'},
      energy: 2,
      notes: 'Private note that must never be shared',
    ),
  ];

  final status = engine.status(logs, today: const DayKey(2024, 3, 10));
  final todayLog = logs.last;

  test('default preferences share nothing sensitive', () {
    final snapshot = buildPartnerSnapshot(
      status: status,
      prefs: const SharingPreferences(),
      todayLog: todayLog,
    );

    expect(snapshot.sharedSymptoms, isEmpty);
    expect(snapshot.energy, isNull);
  });

  test('symptoms are only included when explicitly enabled', () {
    final snapshot = buildPartnerSnapshot(
      status: status,
      prefs: const SharingPreferences(shareSymptoms: true, shareEnergy: true),
      todayLog: todayLog,
    );

    expect(snapshot.sharedSymptoms, containsAll(['Cramps', 'Irritable']));
    expect(snapshot.energy, 2);
  });

  test('notes are never exposed to a partner under any preference', () {
    final snapshot = buildPartnerSnapshot(
      status: status,
      prefs: const SharingPreferences(
        enabled: true,
        sharePhase: true,
        shareNextPeriodDate: true,
        shareSymptoms: true,
        shareEnergy: true,
        shareFertileWindow: true,
      ),
      todayLog: todayLog,
    );

    final serialised = PartnerLinkService.encodeSnapshot(snapshot);

    expect(serialised, isNot(contains('Private note')));
  });

  test('withholding the period date hides it from the snapshot', () {
    final snapshot = buildPartnerSnapshot(
      status: status,
      prefs: const SharingPreferences(shareNextPeriodDate: false),
      todayLog: todayLog,
    );

    expect(snapshot.daysUntilNextPeriod, -999);
  });

  group('period humour', () {
    final periodLogs = period(const DayKey(2024, 3, 25));
    final onPeriod = engine.status(
      [...logs, ...periodLogs],
      today: const DayKey(2024, 3, 26),
    );

    test('is off during her period by default', () {
      expect(onPeriod.phase, CyclePhase.menstrual);
      expect(
        jokesAllowed(status: onPeriod, prefs: const SharingPreferences()),
        isFalse,
      );
    });

    test('is on during her period only when she allows it', () {
      expect(
        jokesAllowed(
          status: onPeriod,
          prefs: const SharingPreferences(allowPeriodHumour: true),
        ),
        isTrue,
      );
    });

    test('a rough day stays plain even when she allows it', () {
      expect(
        jokesAllowed(
          status: onPeriod,
          prefs: const SharingPreferences(allowPeriodHumour: true),
          todayLog: DayLog(
            date: const DayKey(2024, 3, 26),
            symptoms: const {'Cramps'},
          ),
        ),
        isFalse,
      );
    });
  });

  group('partner messages', () {
    final languages = [
      for (final language in AppLanguage.values)
        (language, PartnerMessages.of(language)),
    ];

    Set<String> tipCodes(PartnerMessages m) =>
        {for (final (_, _, line) in m.allTips) line.id};

    test('every language has a card, tips and heads-ups for every phase', () {
      for (final (language, m) in languages) {
        for (final phase in CyclePhase.values) {
          final card = m.cards[phase];
          expect(card, isNotNull, reason: '${language.code} $phase card');
          expect(card!.mayFeel, isNotEmpty);
          expect(card.howToHelp, isNotEmpty);
          for (final tone in PartnerTone.values) {
            expect(m.tips[phase]?[tone], isNotEmpty,
                reason: '${language.code} $phase $tone tips');
            expect(m.headsUp[phase]?[tone], isNotNull,
                reason: '${language.code} $phase $tone heads-up');
          }
        }
        for (final tone in PartnerTone.values) {
          expect(m.anyPhaseTips[tone], isNotEmpty,
              reason: '${language.code} any-phase $tone tips');
        }
      }
    });

    test('tip codes are unique within each language', () {
      for (final (language, m) in languages) {
        final all = [for (final (_, _, line) in m.allTips) line.id];
        expect(all.toSet().length, all.length, reason: language.code);
      }
    });

    test('every language uses exactly the same codes', () {
      final (_, first) = languages.first;
      for (final (language, m) in languages.skip(1)) {
        expect(tipCodes(m), tipCodes(first), reason: language.code);
        expect(m.asks.keys.toList(), first.asks.keys.toList());
        expect(m.replies.keys.toList(), first.replies.keys.toList());
        expect(m.offers.keys.toList(), first.offers.keys.toList());
        expect(m.offerReplies.keys.toList(), first.offerReplies.keys.toList());
      }
    });

    test('a tip that is the same code is in the same place everywhere', () {
      final (_, first) = languages.first;
      final where = {
        for (final (phase, tone, line) in first.allTips)
          line.id: (phase, tone),
      };
      for (final (language, m) in languages.skip(1)) {
        for (final (phase, tone, line) in m.allTips) {
          expect((phase, tone), where[line.id],
              reason: '${language.code} ${line.id}');
        }
      }
    });

    test('the special codes exist in every language', () {
      for (final (_, m) in languages) {
        expect(m.replies, contains(PartnerReactions.done));
        expect(m.offerReplies, contains(OfferReplies.yes));
      }
    });

    test('no placeholder is left unfilled', () {
      for (final (_, m) in languages) {
        final texts = [
          for (final (_, _, line) in m.allTips) line.text,
          for (final ask in m.asks.values) ...[ask.text, ask.reply],
          ...m.replies.values,
          ...m.offers.values,
          ...m.offerReplies.values,
        ];
        for (final text in texts) {
          expect(text, isNot(contains('{')), reason: text);
        }
        expect(
          m.periodExpectedIn.replaceAll('{days}', m.days(2)),
          isNot(contains('{')),
        );
      }
    });

    test('pulled tips are skipped, and any-phase tips cover a hidden phase',
        () {
      final (_, m) = languages.first;
      const day = DayKey(2024, 3, 10);
      final pool = m.tips[CyclePhase.luteal]![PartnerTone.light]!;
      final pulled = {for (final line in pool) line.id};

      final move = PartnerTips.pickMove(
          m, CyclePhase.luteal, PartnerTone.light, day, pulled);
      expect(move, isNotNull);
      expect(pulled, isNot(contains(move!.id)));

      final hidden =
          PartnerTips.pickMove(m, null, PartnerTone.playful, day, const {});
      expect(
        m.anyPhaseTips[PartnerTone.playful]!.map((l) => l.id),
        contains(hidden!.id),
      );
    });
  });
}
