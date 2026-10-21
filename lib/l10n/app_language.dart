/// The languages the app can show, chosen by each person on their own phone
/// before signing in, and changeable in Settings.
///
/// One app for every language: adding one means a new value here and a new
/// messages file next to `partner_messages_en_int.dart`. Everything the two
/// phones exchange is a code (A01, T12...), so she and her partner can each
/// read it in their own language.
enum AppLanguage {
  enGB(
    'en-GB',
    'English (UK)',
    'British wording: a cuppa, the washing-up, the diary.',
  ),
  enInt(
    'en-INT',
    'English (International)',
    'Plain English that reads naturally anywhere.',
  );

  const AppLanguage(this.code, this.label, this.hint);

  /// Stored on the device. Never change one once released.
  final String code;
  final String label;
  final String hint;

  static AppLanguage? fromCode(String? code) {
    for (final language in values) {
      if (language.code == code) return language;
    }
    return null;
  }
}
