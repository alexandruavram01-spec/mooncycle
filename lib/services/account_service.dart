import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'apple_account.dart';
import 'google_account.dart';

/// How an account signs in, and so how it confirms deleting itself.
enum SignInMethod { password, google, apple }

/// Email-and-password accounts, Continue with Google, or Sign in with Apple
/// (iPhone).
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

  /// Continue with Google. The first time makes the account; with
  /// [termsVersion] (she ticked both boxes on the sign-up screen) her consent
  /// is recorded with it, otherwise the app asks for it next. Returns the
  /// email, or null if she closed Google's account picker.
  Future<String?> signInWithGoogle({String? termsVersion}) async {
    final idToken = await GoogleAccount.idToken();
    if (idToken == null) return null;
    final response = await _api.send(
      'POST',
      '/session/google',
      auth: false,
      body: {
        'idToken': idToken,
        if (termsVersion != null) ...{
          'termsVersion': termsVersion,
          'healthConsent': true,
        },
      },
    );
    return _save(response);
  }

  /// Sign in with Apple, the same way. Null if she closed Apple's sheet.
  Future<String?> signInWithApple({String? termsVersion}) async {
    final credential = await AppleAccount.credential();
    if (credential == null) return null;
    final response = await _api.send(
      'POST',
      '/session/apple',
      auth: false,
      body: {
        'identityToken': credential.identityToken,
        'authorizationCode': credential.authorizationCode,
        if (termsVersion != null) ...{
          'termsVersion': termsVersion,
          'healthConsent': true,
        },
      },
    );
    return _save(response);
  }

  /// How this account signs in: accounts made with Google or Apple confirm
  /// with them, not a password.
  Future<SignInMethod> signInMethod() async {
    final response = await _api.send('GET', '/account');
    if (response.statusCode != 200) throw ApiClient.failure(response);
    final json = ApiClient.json(response);
    return switch (json['signIn']) {
      'google' => SignInMethod.google,
      'apple' => SignInMethod.apple,
      // Older servers sent only "password": false for Google accounts.
      _ => json['password'] == false
          ? SignInMethod.google
          : SignInMethod.password,
    };
  }

  /// The terms version this account last agreed to, or null if never.
  Future<String?> acceptedTermsVersion() async {
    final response = await _api.send('GET', '/account');
    if (response.statusCode != 200) throw ApiClient.failure(response);
    return ApiClient.json(response)['termsVersion'] as String?;
  }

  /// The version of the AI-notes explanation she agreed to, or null when
  /// AI-written notes are off.
  Future<String?> aiNotesVersion() async {
    final response = await _api.send('GET', '/account');
    if (response.statusCode != 200) throw ApiClient.failure(response);
    return ApiClient.json(response)['aiNotesVersion'] as String?;
  }

  /// Turns AI-written notes on, recording her explicit consent to the
  /// [version] she read, or off.
  Future<void> setAiNotes({required bool on, required String version}) async {
    final response = await _api.send(
      'PUT',
      '/account/ai-notes',
      body: {'on': on, if (on) 'version': version},
    );
    if (response.statusCode != 200) throw ApiClient.failure(response);
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
    return _save(response);
  }

  /// Keeps the session the server opened, and returns its email.
  Future<String> _save(http.Response response) async {
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
    await GoogleAccount.signOut();
  }

  /// Deletes the account on the server. Both are null when the phone's own
  /// fingerprint, face or PIN check has just passed. Otherwise it is the
  /// [password], asked for again, or for accounts made with Google a fresh
  /// [googleIdToken]; a failed check throws and leaves everything in place.
  Future<void> deleteAccount({
    String? password,
    String? googleIdToken,
    String? appleIdentityToken,
  }) async {
    final response = await _api.send(
      'POST',
      '/account/delete',
      body: password != null
          ? {'password': password}
          : googleIdToken != null
              ? {'googleIdToken': googleIdToken}
              : appleIdentityToken != null
                  ? {'appleIdentityToken': appleIdentityToken}
                  : {'deviceConfirmed': true},
    );
    if (response.statusCode != 200) throw ApiClient.failure(response);
    await _api.clearSession();
    await GoogleAccount.signOut();
  }
}
