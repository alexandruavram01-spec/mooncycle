import '../domain/enums.dart';
import 'app_language.dart';
import 'her_insights_en_gb.dart';

/// One insight card's wording. The code (I01...) is the same in every
/// language; which card shows is decided in `lib/domain/her_insights.dart`.
class InsightText {
  const InsightText({
    required this.title,
    required this.body,
    this.seeGp,
    this.helpNow,
    this.sources = const [],
  });

  final String title;

  /// May hold `{placeholders}` for the cards built from her own log (H01...).
  final String body;

  /// When to see a GP, if the card has advice on that.
  final String? seeGp;

  /// When to get help now. Shown folded away inside the card.
  final String? helpNow;

  /// Codes from [HerInsightTexts.sources].
  final List<String> sources;
}

class InsightSource {
  const InsightSource(this.name, this.url);

  final String name;
  final String url;
}

/// One way to get help on the "Get help now" page.
class HelpOption {
  const HelpOption({
    required this.title,
    required this.body,
    this.callLabel,
    this.phone,
    this.linkLabel,
    this.link,
  });

  final String title;
  final String body;
  final String? callLabel;
  final String? phone;
  final String? linkLabel;
  final String? link;
}

/// Everything her insight cards and the "Get help now" page say, in one
/// language.
class HerInsightTexts {
  const HerInsightTexts({
    required this.cards,
    required this.sources,
    required this.loggedPhrase,
    required this.patternPhrase,
    required this.when,
    required this.labels,
    required this.becauseYouLogged,
    required this.ui,
    required this.help,
    required this.helpIntro,
    required this.helpOutside,
    required this.helpSources,
  });

  final Map<String, InsightText> cards;
  final Map<String, InsightSource> sources;

  /// For "Because you logged {x}": "Headache" -> "a headache".
  final Map<String, String> loggedPhrase;

  /// For pattern cards: "Headache" -> "headaches".
  final Map<String, String> patternPhrase;

  /// "in the days before your period"...
  final Map<CyclePhase, String> when;

  /// The small line above a card, by code or by tier name (`safety`,
  /// `history`, `education`).
  final Map<String, String> labels;

  /// With `{x}`.
  final String becauseYouLogged;

  /// Buttons and headings: `seeGp`, `helpNow`, `notRelevant`, `hide`,
  /// `source`, `ownLog`, `openHelp`, `linkFailed`, `notRelevantDone`.
  final Map<String, String> ui;

  final List<HelpOption> help;
  final String helpIntro;
  final String helpOutside;
  final List<String> helpSources;

  /// The International edition still has to be written: its urgent advice
  /// needs adapting, not just respelling. Until then everyone gets the UK
  /// text, and the cards are switched on for the test accounts only.
  static HerInsightTexts of(AppLanguage language) => switch (language) {
        AppLanguage.enGB => enGbHerInsights,
        AppLanguage.enInt => enGbHerInsights,
      };
}
