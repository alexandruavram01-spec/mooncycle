/// Whose app this is: someone tracking their own cycle, or their partner.
enum AppRole {
  tracker,
  partner;

  static AppRole fromName(String? v) =>
      v == AppRole.partner.name ? AppRole.partner : AppRole.tracker;
}

/// How the partner wants his tips to sound.
enum PartnerTone {
  straight,
  light,
  playful;

  static PartnerTone fromName(String? v) => PartnerTone.values
      .firstWhere((e) => e.name == v, orElse: () => PartnerTone.light);

  String get label => switch (this) {
        PartnerTone.straight => 'Straight to the point',
        PartnerTone.light => 'A little humour',
        PartnerTone.playful => 'Make me laugh',
      };

  String get hint => switch (this) {
        PartnerTone.straight => 'No jokes, just what helps',
        PartnerTone.light => 'Mostly practical, with a light touch',
        PartnerTone.playful => 'Funny first, still useful',
      };
}

enum TrackingGoal {
  track,
  conceive,
  unspecified;

  static TrackingGoal fromName(String? v) => TrackingGoal.values
      .firstWhere((e) => e.name == v, orElse: () => TrackingGoal.unspecified);

  String get label => switch (this) {
        TrackingGoal.track => 'Tracking my cycle',
        TrackingGoal.conceive => 'Trying to get pregnant',
        TrackingGoal.unspecified => 'Basic tracking',
      };
}

enum CycleRegularity {
  regular,
  varies,
  unpredictable,
  unsure;

  static CycleRegularity? fromName(String? v) {
    for (final e in CycleRegularity.values) {
      if (e.name == v) return e;
    }
    return null;
  }
}

/// What the person told the app in the onboarding quiz. Kept on the device;
/// none of it is part of the partner snapshot.
class UserProfile {
  const UserProfile({
    this.role = AppRole.tracker,
    this.journey,
    this.quizAnswers = const <String, Object?>{},
    this.quizResumeAt,
    this.partnerNickname = '',
    this.partnerTone = PartnerTone.light,
    this.goal = TrackingGoal.unspecified,
    this.cycleLength,
    this.periodLength,
    this.regularity,
    this.showFertileDays = false,
    this.tryingSince,
    this.trackedSigns = const <String>[],
    this.focus = const <String>[],
    this.usualSymptoms = const <String>[],
  });

  final AppRole role;

  /// The quiz journey chosen (see `journeys` in quiz.dart), and every answer
  /// as given, keyed by question. Kept for features that do not exist yet,
  /// such as dashboards per journey.
  final String? journey;
  final Map<String, Object?> quizAnswers;

  /// The question she stopped at when she chose "finish the rest later".
  /// Null once the quiz has been completed.
  final int? quizResumeAt;

  /// What a partner calls her. Empty when he skipped the question.
  final String partnerNickname;
  final PartnerTone partnerTone;

  final TrackingGoal goal;

  /// Her own estimate, used until a full cycle has been logged. Null when she
  /// did not know.
  final int? cycleLength;
  final int? periodLength;
  final CycleRegularity? regularity;

  /// Off unless she is trying to conceive or asked to see them. Always an
  /// estimate, never presented as contraception.
  final bool showFertileDays;

  /// `start`, `lt6`, `6to12` or `year`.
  final String? tryingSince;

  /// Any of `bbt`, `fluid`, `lh`.
  final List<String> trackedSigns;

  /// Any of `period`, `pain`, `mood`, `irregular`, `record`.
  final List<String> focus;

  /// Names from the symptom catalogue.
  final List<String> usualSymptoms;

  UserProfile copyWith({
    bool? showFertileDays,
    String? partnerNickname,
    PartnerTone? partnerTone,
    Map<String, Object?>? quizAnswers,
  }) =>
      UserProfile(
        role: role,
        journey: journey,
        quizAnswers: quizAnswers ?? this.quizAnswers,
        quizResumeAt: quizResumeAt,
        partnerNickname: partnerNickname ?? this.partnerNickname,
        partnerTone: partnerTone ?? this.partnerTone,
        goal: goal,
        cycleLength: cycleLength,
        periodLength: periodLength,
        regularity: regularity,
        showFertileDays: showFertileDays ?? this.showFertileDays,
        tryingSince: tryingSince,
        trackedSigns: trackedSigns,
        focus: focus,
        usualSymptoms: usualSymptoms,
      );

  Map<String, Object?> toJson() => {
        'role': role.name,
        'journey': journey,
        'quizAnswers': quizAnswers,
        'quizResumeAt': quizResumeAt,
        'partnerNickname': partnerNickname,
        'partnerTone': partnerTone.name,
        'goal': goal.name,
        'cycleLength': cycleLength,
        'periodLength': periodLength,
        'regularity': regularity?.name,
        'showFertileDays': showFertileDays,
        'tryingSince': tryingSince,
        'trackedSigns': trackedSigns,
        'focus': focus,
        'usualSymptoms': usualSymptoms,
      };

  static UserProfile fromJson(Map<String, Object?> j) => UserProfile(
        role: AppRole.fromName(j['role'] as String?),
        journey: j['journey'] as String?,
        quizAnswers:
            (j['quizAnswers'] as Map?)?.cast<String, Object?>() ?? const {},
        quizResumeAt: j['quizResumeAt'] as int?,
        partnerNickname: j['partnerNickname'] as String? ?? '',
        partnerTone: PartnerTone.fromName(j['partnerTone'] as String?),
        goal: TrackingGoal.fromName(j['goal'] as String?),
        cycleLength: j['cycleLength'] as int?,
        periodLength: j['periodLength'] as int?,
        regularity: CycleRegularity.fromName(j['regularity'] as String?),
        showFertileDays: j['showFertileDays'] as bool? ?? false,
        tryingSince: j['tryingSince'] as String?,
        trackedSigns: _strings(j['trackedSigns']),
        focus: _strings(j['focus']),
        usualSymptoms: _strings(j['usualSymptoms']),
      );

  static List<String> _strings(Object? value) =>
      value is List ? value.whereType<String>().toList() : const <String>[];
}
