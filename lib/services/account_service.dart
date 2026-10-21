import 'api_client.dart';

/// Email-and-password accounts.
///
/// An account is identity only: it holds the email and the partner
/// connection. Logs and quiz answers never leave the device, so signing in
/// somewhere else does not bring them along.
class AccountService {
  AccountService([ApiClient? api]) : _api = api ?? ApiClient();

  final ApiClient _api;

  /// Both return the email as the server stored it. Signing up records that
  /// she agreed to [termsVersion] and gave explicit consent for health data.
  Future<String> signUp(
    String email,
    String password, {
    required String termsVersion,
  }) =>
      _open(
        '/account',
        email,
        password,
        {'termsVersion': termsVersion, 'healthConsent': true},
      );

  Future<String> signIn(String email, String password) =>
      _open('/session', email, password);

  /// The terms version this account last agreed to, or null if never.
  Future<String?> acceptedTermsVersion() async {
    final response = await _api.send('GET', '/account');
    if (response.statusCode != 200) throw ApiClient.failure(response);
    return ApiClient.json(response)['termsVersion'] as String?;
  }

  /// Agreeing to [termsVersion] and giving consent for health data, for an
  /// existing account.
  Future<void> recordConsent(String termsVersion) async {
    final response = await _api.send(
      'POST',
      '/account/consent',
      body: {'termsVersion': termsVersion, 'healthConsent': true},
    );
    if (response.statusCode != 200) throw ApiClient.failure(response);
  }

  Future<String> _open(
    String path,
    String email,
    String password, [
    Map<String, Object?> extra = const {},
  ]) async {
    final response = await _api.send(
      'POST',
      path,
      auth: false,
      body: {'email': email.trim(), 'password': password, ...extra},
    );
    if (response.statusCode != 200) throw ApiClient.failure(response);

    final json = ApiClient.json(response);
    final confirmed = json['email'] as String;
    await _api.saveSession(email: confirmed, token: json['token'] as String);
    return confirmed;
  }

  Future<void> signOut() async {
    try {
      await _api.send('DELETE', '/session');
    } on ApiException {
      // Offline or already signed out: the local session is dropped anyway.
    }
    await _api.clearSession();
  }

  /// Deletes the account on the server. [password] is null when the phone's
  /// own fingerprint, face or PIN check has just passed. Otherwise it is the
  /// password, asked for again; a wrong one throws and leaves everything in
  /// place.
  Future<void> deleteAccount({String? password}) async {
    final response = await _api.send(
      'POST',
      '/account/delete',
      body: password == null
          ? {'deviceConfirmed': true}
          : {'password': password},
    );
    if (response.statusCode != 200) throw ApiClient.failure(response);
    await _api.clearSession();
  }
}
