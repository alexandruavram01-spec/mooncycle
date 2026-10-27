import 'app_language.dart';
import 'ui_ro.dart';

/// On-screen text in the chosen language. The code keeps the English
/// wording; tr() swaps it for the translation, and keeps the English where a
/// translation is missing, so nothing breaks while a language is growing.
///
/// Stored values never go through tr(): symptoms, quiz answers and codes stay
/// in English underneath, so logs read the same in every language.
class UiText {
  UiText._();

  /// Set by the app from the language she chose (main.dart).
  static AppLanguage language = AppLanguage.enGB;

  static bool get romanian => language == AppLanguage.ro;
}

String tr(String english) =>
    UiText.romanian ? (uiRo[english] ?? english) : english;

/// tr() with {name} placeholders: trf('Period in {n} days', {'n': 5}).
String trf(String english, Map<String, Object?> values) {
  var text = tr(english);
  values.forEach((key, value) => text = text.replaceAll('{$key}', '$value'));
  return text;
}

/// A count with its noun: trCount(n, '{n} day', '{n} days').
/// Romanian adds "de" from 20 on ("20 de zile", "101 zile", "120 de zile").
String trCount(int n, String one, String other) {
  if (n == 1) return trf(one, {'n': n});
  var text = tr(other);
  final rest = n.abs() % 100;
  if (UiText.romanian && (rest >= 20 || (rest == 0 && n != 0))) {
    text = text.replaceFirst('{n} ', '{n} de ');
  }
  return text.replaceAll('{n}', '$n');
}

/// Romanian number agreement in text already filled in: "1 zi" for
/// "1 zile", and "de" from 20 on ("21 de zile", "20 de menstruații").
/// Leaves English, and decimals such as "7.5 ore", untouched.
String roCounts(String text) => text.replaceAllMapped(
      RegExp(r'(?<![\d.,])(\d+) (zile|ore|cicluri|menstruații)\b'),
      (m) {
        final n = int.parse(m[1]!);
        const one = {
          'zile': 'zi',
          'ore': 'oră',
          'cicluri': 'ciclu',
          'menstruații': 'menstruație',
        };
        if (n == 1) return '1 ${one[m[2]]}';
        final rest = n % 100;
        final de = rest >= 20 || (rest == 0 && n != 0) ? 'de ' : '';
        return '$n $de${m[2]}';
      },
    );
