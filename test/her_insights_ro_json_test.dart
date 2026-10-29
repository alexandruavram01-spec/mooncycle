import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mooncycle/l10n/her_insights_ro.dart';

/// The AI-notes server writes Romanian notes from
/// content/her-insights-ro.json. If this fails, run:
///   python tool/export_ro_cards.py
void main() {
  test('the server copy of the Romanian cards matches the app', () {
    final json = jsonDecode(
      File('content/her-insights-ro.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final cards = json['cards'] as Map<String, dynamic>;
    expect(cards.keys.toSet(), roHerInsights.cards.keys.toSet());
    roHerInsights.cards.forEach((id, text) {
      expect(cards[id]['title'], text.title, reason: id);
      expect(cards[id]['body'], text.body, reason: id);
    });
    expect(
      Map<String, String>.from(json['openings'] as Map),
      roHerInsights.openings,
    );
    expect(
      Map<String, String>.from(json['loggedPhrase'] as Map),
      roHerInsights.loggedPhrase,
    );
    expect(List<String>.from(json['months'] as List), roHerInsights.months);
  });
}
