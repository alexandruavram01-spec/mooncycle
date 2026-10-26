/// Core vocabulary of the app. Kept dependency-free so it can be unit tested
/// and later reused by a backend or a partner-facing client.

enum FlowIntensity {
  none,
  spotting,
  light,
  medium,
  heavy;

  static FlowIntensity fromName(String? v) =>
      FlowIntensity.values.firstWhere((e) => e.name == v,
          orElse: () => FlowIntensity.none);

  /// Anything from spotting upward counts as "bleeding" but only light+
  /// starts a new cycle, so spotting before a period doesn't shift predictions.
  bool get isBleeding => index >= FlowIntensity.spotting.index;
  bool get startsCycle => index >= FlowIntensity.light.index;

  String get label => switch (this) {
        FlowIntensity.none => 'None',
        FlowIntensity.spotting => 'Spotting',
        FlowIntensity.light => 'Light',
        FlowIntensity.medium => 'Medium',
        FlowIntensity.heavy => 'Heavy',
      };
}

enum CyclePhase {
  menstrual,
  follicular,
  ovulatory,
  luteal;

  String get label => switch (this) {
        CyclePhase.menstrual => 'Menstrual',
        CyclePhase.follicular => 'Follicular',
        CyclePhase.ovulatory => 'Ovulatory',
        CyclePhase.luteal => 'Luteal',
      };
}

/// Symptom catalogue, grouped the way the logging sheet renders it.
class SymptomCatalog {
  static const Map<String, List<String>> groups = {
    'Pain': [
      'Cramps',
      'Headache',
      'Backache',
      'Breast tenderness',
      'Joint pain',
      'Ovulation pain',
    ],
    'Mood': [
      'Happy',
      'Calm',
      'Irritable',
      'Anxious',
      'Sad',
      'Sensitive',
      'Confident',
    ],
    'Body': [
      'Bloating',
      'Acne',
      'Nausea',
      'Fatigue',
      'Dizziness',
      'Hot flush',
      'Food cravings',
    ],
    'Digestion': ['Constipation', 'Diarrhoea', 'Appetite up', 'Appetite down'],
    'Fluid': ['Dry', 'Sticky', 'Creamy', 'Egg white', 'Watery'],
    'Sex': ['Low drive', 'Usual drive', 'High drive', 'Protected', 'Unprotected'],
  };

  /// Desire is one of these three (the log sheet keeps only one ticked).
  static const desire = {'Low drive', 'Usual drive', 'High drive'};

  static List<String> get all =>
      groups.values.expand((e) => e).toList(growable: false);
}
