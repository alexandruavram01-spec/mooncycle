import '../domain/enums.dart';
import '../domain/profile.dart';
import 'app_language.dart';
import 'partner_messages_en_gb.dart';
import 'partner_messages_en_int.dart';
import 'partner_messages_ro.dart';

/// One line of partner copy and its stable code (T01, T49...). The code is
/// what ratings refer to; the text depends on the reader's language.
class Line {
  const Line(this.id, this.text);

  final String id;
  final String text;
}

/// What his screen says about one phase of her cycle (codes G01 to G30).
class PhaseCard {
  const PhaseCard({
    required this.name,
    required this.summary,
    required this.headline,
    required this.mayFeel,
    required this.howToHelp,
    this.note,
  });

  /// "Period", "Mid-cycle"... Same idea in every language.
  final String name;

  /// The large line at the top of his card, such as "Menstrual days".
  final String summary;
  final String headline;
  final List<String> mayFeel;
  final List<String> howToHelp;

  /// A safety note shown under the card (G22).
  final String? note;
}

/// One of her one-tap asks, and the reply he is offered first.
class Ask {
  const Ask(this.text, this.reply);

  final String text;
  final String reply;
}

/// Everything a partner reads, and the one-tap messages between them, in one
/// language. The files for each language must use exactly the same codes;
/// `test/partner_test.dart` checks that they do.
///
/// Only codes travel between the two phones and the server, never the text.
class PartnerMessages {
  const PartnerMessages({
    required this.tips,
    required this.anyPhaseTips,
    required this.headsUp,
    required this.tomorrow,
    required this.inAboutDays,
    required this.cards,
    required this.periodExpectedNow,
    required this.periodExpectedIn,
    required this.periodSoonAsk,
    required this.oneDay,
    required this.manyDays,
    required this.asks,
    required this.replies,
    required this.offers,
    required this.offerReplies,
  });

  /// Today's move, by her phase and the tone he chose.
  final Map<CyclePhase, Map<PartnerTone, List<Line>>> tips;

  /// Used when she does not share her phase.
  final Map<PartnerTone, List<Line>> anyPhaseTips;

  /// Keyed by the phase about to start (U01 to U12). Shown after
  /// [tomorrow] or [inAboutDays].
  final Map<CyclePhase, Map<PartnerTone, String>> headsUp;
  final String tomorrow;

  /// With `{n}` for the number of days.
  final String inAboutDays;

  final Map<CyclePhase, PhaseCard> cards;

  /// G31: her period is due today or overdue. Never says it has started.
  final String periodExpectedNow;

  /// G32, with `{days}` for "1 day" or "12 days".
  final String periodExpectedIn;

  /// G33, added to G32 when her period is two days away or less.
  final String periodSoonAsk;
  final String oneDay;

  /// With `{n}` for the number of days.
  final String manyDays;

  /// Her one-tap asks, in the order she sees them.
  final Map<String, Ask> asks;

  /// His general replies to an ask.
  final Map<String, String> replies;

  /// What he can offer her, in display order.
  final Map<String, String> offers;

  /// Her answers to an offer.
  final Map<String, String> offerReplies;

  static PartnerMessages of(AppLanguage language) => switch (language) {
        AppLanguage.enGB => enGbMessages,
        AppLanguage.enInt => enIntMessages,
        AppLanguage.ro => roMessages,
      };

  String days(int n) => n == 1 ? oneDay : manyDays.replaceAll('{n}', '$n');

  /// "Tomorrow" or "In about 3 days".
  String headsUpLead(int n) =>
      n == 1 ? tomorrow : inAboutDays.replaceAll('{n}', '$n');

  /// Every daily tip with where it is used. A null phase means "any phase".
  Iterable<(CyclePhase?, PartnerTone, Line)> get allTips sync* {
    for (final MapEntry(key: phase, value: byTone) in tips.entries) {
      for (final MapEntry(key: tone, value: lines) in byTone.entries) {
        for (final line in lines) {
          yield (phase, tone, line);
        }
      }
    }
    for (final MapEntry(key: tone, value: lines) in anyPhaseTips.entries) {
      for (final line in lines) {
        yield (null, tone, line);
      }
    }
  }
}
