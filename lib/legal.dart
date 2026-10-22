/// Who provides MoonCycle, and where its legal pages are. The pages are in
/// `web/` (privacy.html, terms.html, health.html, delete-account.html) and go
/// live with the website.
///
/// Drafts until a UK solicitor has reviewed them: see BEFORE_LAUNCH.md.
class Legal {
  static const appName = 'MoonCycle';
  static const company = 'IONCODEX LTD';
  static const companyNumber = '16798601';
  static const address = '127 Calshot Road, Birmingham, B42 2BZ, England';

  /// The version of the terms and privacy policy people agree to. Change it
  /// whenever either changes materially: everyone is then asked again.
  static const version = '2026-10-22';

  /// The version of the AI-written notes explanation she agrees to when she
  /// turns them on. Change it when that explanation changes materially:
  /// the notes then stay off until she agrees again.
  static const aiNotesVersion = '2026-10-21';

  /// An alias of contact@ioncodex.org, named in every legal page.
  static const contactEmail = 'mooncycle_contact@ioncodex.org';

  static const minimumAge = 18;

  static const privacyUrl = 'https://mooncycle.fit/privacy.html';
  static const termsUrl = 'https://mooncycle.fit/terms.html';
  static const healthUrl = 'https://mooncycle.fit/health.html';
  static const deleteUrl = 'https://mooncycle.fit/delete-account.html';

  /// Shown in Settings and at sign-up.
  static const healthNotice =
      'MoonCycle gives general information and estimates to help you '
      'understand your own cycle. It is not a medical device, does not '
      'diagnose or treat any condition, is not contraception, and does not '
      'replace a doctor, nurse or pharmacist. In an emergency, call 999.';
}
