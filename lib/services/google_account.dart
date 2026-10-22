import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import 'api_client.dart';

/// "Continue with Google", on Android for now. The iPhone needs its own
/// client ID and Sign in with Apple beside it (Apple's rule), and the website
/// a button drawn by Google, so neither shows it yet.
class GoogleAccount {
  GoogleAccount._();

  /// The "MoonCycle server" web client in Google Cloud (project MoonCycle).
  /// Not a secret: Google makes the ID token for it, and the server accepts
  /// only tokens made for it (GOOGLE_CLIENT_IDS in server/server.js).
  static const serverClientId =
      '531774189485-hqam3gqj4ola0p2b277u2e87sv8es266.apps.googleusercontent.com';

  static bool get available =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void>? _ready;

  static Future<void> _init() async {
    final ready = _ready ??=
        GoogleSignIn.instance.initialize(serverClientId: serverClientId);
    try {
      await ready;
    } catch (_) {
      _ready = null;
      rethrow;
    }
  }

  /// Google's account picker, then an ID token for our server. Null if the
  /// picker was closed. A setup problem (such as a missing SHA-1 in Google
  /// Cloud) can also look like a closed picker: Google does not tell them
  /// apart.
  static Future<String?> idToken() async {
    try {
      await _init();
      final account = await GoogleSignIn.instance.authenticate();
      final token = account.authentication.idToken;
      if (token == null) throw const ApiException(_failed);
      return token;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw const ApiException(_failed);
    }
  }

  /// So the next sign-in shows the account picker again. Best effort.
  static Future<void> signOut() async {
    if (!available) return;
    try {
      await _init();
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Nothing to forget, or offline.
    }
  }

  static const _failed =
      'Google sign-in did not work. Try again, or use your email and '
      'password.';
}
