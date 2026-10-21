import '../l10n/partner_messages.dart';
import 'day_key.dart';
import 'enums.dart';
import 'profile.dart';

/// Chooses what the partner's screen says. The words live in `lib/l10n/`, one
/// file per language, under stable codes.
///
/// Two rules for every line there. The joke is on him or the situation, never
/// on her. And nothing claims to know how she feels: these are typical
/// patterns, which is why his screen frames them as possibilities.
class PartnerTips {
  /// Today's move, rotating by date so he does not read the same line all
  /// week. Lines someone flagged "not okay" ([pulled]) are skipped.
  ///
  /// With no phase shared, the any-phase lines are used. If his tone has
  /// nothing left, the plain lines stand in.
  static Line? pickMove(
    PartnerMessages messages,
    CyclePhase? phase,
    PartnerTone tone,
    DayKey day,
    Set<String> pulled,
  ) {
    List<Line> usable(List<Line>? lines) => [
          for (final line in lines ?? const <Line>[])
            if (!pulled.contains(line.id)) line,
        ];

    final pools = [
      if (phase != null) usable(messages.tips[phase]?[tone]),
      if (phase != null) usable(messages.tips[phase]?[PartnerTone.straight]),
      usable(messages.anyPhaseTips[tone]),
      usable(messages.anyPhaseTips[PartnerTone.straight]),
    ];
    for (final pool in pools) {
      if (pool.isNotEmpty) return pool[day.epochDay % pool.length];
    }
    return null;
  }

  /// A heads-up about the phase that starts in [days] days.
  static String headsUp(
    PartnerMessages messages,
    CyclePhase next,
    int days,
    PartnerTone tone,
  ) =>
      '${messages.headsUpLead(days)}: ${messages.headsUp[next]![tone]!}';
}

/// His replies to an ask. The keys must match `REACTIONS` in
/// `server/server.js`.
class PartnerReactions {
  /// The reply written for her particular ask ([Ask.reply]).
  static const special = 'special';

  /// "It's done": her ask gets a "Delivered" stamp.
  static const done = 'R02';

  static String? label(PartnerMessages messages, String? reaction, String? ask) =>
      reaction == special ? messages.asks[ask]?.reply : messages.replies[reaction];
}

/// Her answers to an offer. The keys must match `OFFER_REPLIES` in
/// `server/server.js`.
class OfferReplies {
  /// "Yes, please!": his offer gets an "Accepted" stamp.
  static const yes = 'O13';
}

/// What he can offer her without being asked, so he is not only ever taking
/// orders. The keys must match `OFFERS` in `server/server.js`.
class PartnerOffers {
  /// Phases an offer suits best. Offers not listed suit any day.
  static const Map<String, Set<CyclePhase>> _bestIn = {
    'O02': {CyclePhase.menstrual, CyclePhase.luteal},
    'O04': {CyclePhase.menstrual, CyclePhase.luteal},
    'O05': {CyclePhase.menstrual, CyclePhase.luteal},
    'O06': {CyclePhase.menstrual, CyclePhase.luteal},
    'O07': {CyclePhase.menstrual, CyclePhase.luteal},
    'O10': {CyclePhase.follicular, CyclePhase.ovulatory, CyclePhase.luteal},
    'O11': {CyclePhase.follicular, CyclePhase.ovulatory},
    'O12': {CyclePhase.follicular, CyclePhase.ovulatory},
    'O18': {CyclePhase.menstrual, CyclePhase.luteal},
    'O22': {CyclePhase.menstrual, CyclePhase.luteal},
    'O23': {CyclePhase.follicular, CyclePhase.ovulatory},
    'O24': {CyclePhase.follicular, CyclePhase.ovulatory, CyclePhase.luteal},
  };

  /// Every offer, with the ones that suit [phase] first.
  static List<String> forPhase(PartnerMessages messages, CyclePhase? phase) {
    final keys = messages.offers.keys.toList();
    if (phase == null) return keys;
    bool suits(String key) => _bestIn[key]?.contains(phase) ?? true;
    return [...keys.where(suits), ...keys.where((k) => !suits(k))];
  }
}
