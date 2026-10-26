import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import 'api_client.dart';

/// "Continue with Google", on Android, and on iPhone once [iosClientId] is
/// set. The website would need a button drawn by Google, so it has none.
class GoogleAccount {
  GoogleAccount._();

  /// The "MoonCycle server" web client in Google Cloud (project MoonCycle).
  /// Not a secret: Google makes the ID token for it, and the server accepts
  /// only tokens made for it (GOOGLE_CLIENT_IDS in server/server.js).
  static const serverClientId =
      '531774189485-hqam3gqj4ola0p2b277u2e87sv8es266.apps.googleusercontent.com';

  /// The "MoonCycle iPhone" iOS client in Google Cloud. Empty until it is
  /// made (it needs the Apple Team ID); the iPhone shows no Google button
  /// until then. Setting it also needs, in ios/Runner/Info.plist, a URL type
  /// whose scheme is this ID reversed (com.googleusercontent.apps.…), and the
  /// same ID in GOOGLE_CLIENT_IDS on the server.
  static const iosClientId = '';

  static bool get _iPhone =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static bool get available =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          (_iPhone && iosClientId.isNotEmpty));

  static Future<void>? _ready;

  static Future<void> _init() async {
    final ready = _ready ??= GoogleSignIn.instance.initialize(
      clientId: _iPhone ? iosClientId : null,
      serverClientId: serverClientId,
    );
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
      debugPrint('Google sign-in: ${e.code.name} ${e.description ?? ''}');
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      // The code helps tell a setup problem from anything else.
      throw ApiException('$_failed (${e.code.name})');
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
