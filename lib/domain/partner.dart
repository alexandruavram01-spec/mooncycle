import 'cycle_engine.dart';
import 'enums.dart';
import 'models.dart';

/// How much the tracker chooses to reveal. Defaults are deliberately minimal —
/// sharing is opt-in per field, never all-or-nothing.
class SharingPreferences {
  const SharingPreferences({
    this.enabled = false,
    this.sharePhase = true,
    this.shareNextPeriodDate = true,
    this.shareSymptoms = false,
    this.shareEnergy = false,
    this.shareFertileWindow = false,
    this.shareMood = false,
    this.sharePain = false,
    this.allowRequests = true,
    this.allowJokes = true,
    this.allowPeriodHumour = false,
    this.partnerName = '',
  });

  /// Lets his tips stay funny during her period too. Off until she turns it
  /// on; rough days stay joke-free either way.
  final bool allowPeriodHumour;

  /// Mood-group symptoms and energy from the day's log.
  final bool shareMood;

  /// Pain and discomfort symptoms from the day's log. Never the fluid, sex
  /// or digestion groups.
  final bool sharePain;

  /// Whether she can send him nudges ("I need a hug").
  final bool allowRequests;

  /// He picks how funny his tips are, but they are about her, so she can
  /// switch the jokes off altogether.
  final bool allowJokes;

  final bool enabled;
  final bool sharePhase;
  final bool shareNextPeriodDate;
  final bool shareSymptoms;
  final bool shareEnergy;

  /// Off by default: fertility status is the most sensitive field in the app.
  final bool shareFertileWindow;
  final String partnerName;

  SharingPreferences copyWith({
    bool? enabled,
    bool? sharePhase,
    bool? shareNextPeriodDate,
    bool? shareSymptoms,
    bool? shareEnergy,
    bool? shareFertileWindow,
    bool? shareMood,
    bool? sharePain,
    bool? allowRequests,
    bool? allowJokes,
    bool? allowPeriodHumour,
    String? partnerName,
  }) =>
      SharingPreferences(
        enabled: enabled ?? this.enabled,
        sharePhase: sharePhase ?? this.sharePhase,
        shareNextPeriodDate: shareNextPeriodDate ?? this.shareNextPeriodDate,
        shareSymptoms: shareSymptoms ?? this.shareSymptoms,
        shareEnergy: shareEnergy ?? this.shareEnergy,
        shareFertileWindow: shareFertileWindow ?? this.shareFertileWindow,
        shareMood: shareMood ?? this.shareMood,
        sharePain: sharePain ?? this.sharePain,
        allowRequests: allowRequests ?? this.allowRequests,
        allowJokes: allowJokes ?? this.allowJokes,
        allowPeriodHumour: allowPeriodHumour ?? this.allowPeriodHumour,
        partnerName: partnerName ?? this.partnerName,
      );

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'sharePhase': sharePhase,
        'shareNextPeriodDate': shareNextPeriodDate,
        'shareSymptoms': shareSymptoms,
        'shareEnergy': shareEnergy,
        'shareFertileWindow': shareFertileWindow,
        'shareMood': shareMood,
        'sharePain': sharePain,
        'allowRequests': allowRequests,
        'allowJokes': allowJokes,
        'allowPeriodHumour': allowPeriodHumour,
        'partnerName': partnerName,
      };

  static SharingPreferences fromJson(Map<String, Object?> j) =>
      SharingPreferences(
        enabled: j['enabled'] as bool? ?? false,
        sharePhase: j['sharePhase'] as bool? ?? true,
        shareNextPeriodDate: j['shareNextPeriodDate'] as bool? ?? true,
        shareSymptoms: j['shareSymptoms'] as bool? ?? false,
        shareEnergy: j['shareEnergy'] as bool? ?? false,
        shareFertileWindow: j['shareFertileWindow'] as bool? ?? false,
        // Settings saved before mood and pain were split inherit the old
        // "Today's symptoms" switch.
        shareMood: j['shareMood'] as bool? ??
            (j['shareSymptoms'] as bool? ?? false),
        sharePain: j['sharePain'] as bool? ??
            (j['shareSymptoms'] as bool? ?? false),
        allowRequests: j['allowRequests'] as bool? ?? true,
        allowJokes: j['allowJokes'] as bool? ?? true,
        allowPeriodHumour: j['allowPeriodHumour'] as bool? ?? false,
        partnerName: j['partnerName'] as String? ?? '',
      );
}

final Set<String> _moodSymptoms = {...?SymptomCatalog.groups['Mood']};
final Set<String> _painSymptoms = {
  ...?SymptomCatalog.groups['Pain'],
  'Bloating',
  'Nausea',
  'Fatigue',
  'Dizziness',
  'Hot flush',
};

/// Logged symptoms that make a day a rough one: no jokes for him that day.
const _roughDaySymptoms = {
  'Cramps',
  'Headache',
  'Backache',
  'Breast tenderness',
  'Nausea',
  'Dizziness',
  'Fatigue',
  'Sad',
  'Anxious',
  'Irritable',
  'Sensitive',
};

/// Whether his tips may be funny today.
///
/// She decides first. After that the jokes stop on their own during her
/// period (unless she allows them then too), while she is trying to conceive,
/// when her period is late, and on any day she logged as rough. Fun is for
/// the days they can both laugh.
bool jokesAllowed({
  required CycleStatus status,
  required SharingPreferences prefs,
  DayLog? todayLog,
  bool conceiving = false,
}) {
  if (!prefs.allowJokes || conceiving || status.isLate) return false;
  if (status.phase == CyclePhase.menstrual && !prefs.allowPeriodHumour) {
    return false;
  }

  final log = todayLog;
  if (log == null) return true;
  if (log.flow == FlowIntensity.heavy) return false;
  if ((log.energy ?? 5) <= 2) return false;
  return !log.symptoms.any(_roughDaySymptoms.contains);
}

/// The next phase change and how many days away it is, or null when telling
/// him would reveal a date she has not chosen to share.
(CyclePhase, int)? _upcoming(CycleStatus status, SharingPreferences prefs) {
  if (!prefs.sharePhase) return null;
  final today = status.today;
  final ovulation = status.predictedOvulation;

  switch (status.phase) {
    case CyclePhase.menstrual:
      final days = status.typicalPeriodLength - status.dayOfCycle + 1;
      return days > 0 ? (CyclePhase.follicular, days) : null;
    case CyclePhase.follicular:
      // When her fertile days begin is the most sensitive date here, so it
      // is announced in advance only if she shares the fertile window.
      if (!prefs.shareFertileWindow || ovulation == null) return null;
      final days = ovulation.addDays(-1).differenceInDays(today);
      return days > 0 ? (CyclePhase.ovulatory, days) : null;
    case CyclePhase.ovulatory:
      if (ovulation == null) return null;
      final days = ovulation.addDays(2).differenceInDays(today);
      return days > 0 ? (CyclePhase.luteal, days) : null;
    case CyclePhase.luteal:
      final days = status.daysUntilNextPeriod;
      if (!prefs.shareNextPeriodDate || days == null || days <= 0) {
        return null;
      }
      return (CyclePhase.menstrual, days);
  }
}

/// Builds the redacted view a partner is allowed to see. It holds no text:
/// his phone writes the card from the phase, in his own language.
///
/// The menstrual phase only ever comes from days she logged (see
/// [CycleEngine.status]), so "Her period has started" is never a guess.
PartnerSnapshot buildPartnerSnapshot({
  required CycleStatus status,
  required SharingPreferences prefs,
  DayLog? todayLog,
  bool conceiving = false,
}) {
  final phase = status.phase;
  // Only the mood and pain groups ever leave the phone, and only the ones
  // she chose. The older all-symptoms switch now means both groups.
  final mood = prefs.shareMood || prefs.shareSymptoms;
  final pain = prefs.sharePain || prefs.shareSymptoms;
  final symptoms = [
    for (final s in todayLog?.symptoms ?? const <String>{})
      if ((mood && _moodSymptoms.contains(s)) ||
          (pain && _painSymptoms.contains(s)))
        s,
  ];
  final upcoming = _upcoming(status, prefs);

  return PartnerSnapshot(
    // With phase sharing off, neither value is in the snapshot at all —
    // hiding them on his screen would still have sent them to the server.
    dayOfCycle: prefs.sharePhase ? status.dayOfCycle : null,
    phase: prefs.sharePhase ? phase : null,
    nextPhase: upcoming?.$1,
    daysUntilNextPhase: upcoming?.$2,
    jokes: jokesAllowed(
      status: status,
      prefs: prefs,
      todayLog: todayLog,
      conceiving: conceiving,
    ),
    daysUntilNextPeriod:
        prefs.shareNextPeriodDate ? (status.daysUntilNextPeriod ?? 0) : -999,
    sharedSymptoms: symptoms,
    energy: (mood || prefs.shareEnergy) ? todayLog?.energy : null,
  );
}
