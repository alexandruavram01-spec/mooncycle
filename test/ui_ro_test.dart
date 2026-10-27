import 'package:flutter_test/flutter_test.dart';
import 'package:mooncycle/l10n/app_language.dart';
import 'package:mooncycle/l10n/ui.dart';
import 'package:mooncycle/l10n/ui_ro.dart';

void main() {
  tearDown(() => UiText.language = AppLanguage.enGB);

  test('every Romanian text keeps the same placeholders', () {
    final placeholder = RegExp(r'\{\w+\}');
    for (final entry in uiRo.entries) {
      final en = placeholder.allMatches(entry.key).map((m) => m[0]).toSet();
      final ro = placeholder.allMatches(entry.value).map((m) => m[0]).toSet();
      expect(ro, en, reason: entry.key);
    }
  });

  test('Romanian uses ș and ț with the comma below', () {
    for (final text in uiRo.values) {
      expect(text.contains(RegExp('[şţŞŢ]')), isFalse, reason: text);
    }
  });

  test('English is unchanged', () {
    expect(tr('Save'), 'Save');
    expect(trCount(3, '{n} day', '{n} days'), '3 days');
    expect(trCount(1, '{n} day', '{n} days'), '1 day');
  });

  test('Romanian counts add "de" from 20', () {
    UiText.language = AppLanguage.ro;
    expect(tr('Save'), 'Salvează');
    expect(trCount(1, '{n} day', '{n} days'), '1 zi');
    expect(trCount(5, '{n} day', '{n} days'), '5 zile');
    expect(trCount(21, '{n} day', '{n} days'), '21 de zile');
    expect(trCount(101, '{n} day', '{n} days'), '101 zile');
    expect(trf('Day {n}', {'n': 14}), 'Ziua 14');
    // Not in the dictionary: falls back to the English.
    expect(tr('Something new'), 'Something new');
  });

  test('counts inside filled-in card sentences', () {
    expect(roCounts('acum 1 zile'), 'acum 1 zi');
    expect(roCounts('timp de 21 zile consecutive'), 'timp de 21 de zile consecutive');
    expect(roCounts('Cele 20 menstruații'), 'Cele 20 de menstruații');
    expect(roCounts('a durat 28 zile'), 'a durat 28 de zile');
    expect(roCounts('cu 5 zile mai devreme'), 'cu 5 zile mai devreme');
    expect(roCounts('Ai înregistrat 7.5 ore de somn'), 'Ai înregistrat 7.5 ore de somn');
    expect(roCounts('In about 21 days'), 'In about 21 days');
  });
}
