import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'api_client.dart';

/// What Apple returns for the server to check: the signed identity token,
/// and a one-time code the server swaps for the token it needs to cancel
/// Apple's link if the account is ever deleted.
typedef AppleCredential = ({String identityToken, String authorizationCode});

/// Sign in with Apple, on iPhone. Apple requires it beside Continue with
/// Google. The server checks Apple's token (server/server.js).
class AppleAccount {
  AppleAccount._();

  static bool get available =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Apple's sheet (Face ID or passcode). Null if she closed it.
  static Future<AppleCredential?> credential() async {
    try {
      final result = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email],
      );
      final token = result.identityToken;
      if (token == null) throw const ApiException(_failed);
      return (identityToken: token, authorizationCode: result.authorizationCode);
    } on SignInWithAppleAuthorizationException catch (e) {
      debugPrint('Sign in with Apple: ${e.code.name} ${e.message}');
      if (e.code == AuthorizationErrorCode.canceled) return null;
      throw ApiException('$_failed (${e.code.name})');
    }
  }

  static const _failed =
      'Sign in with Apple did not work. Try again, or use your email and '
      'password.';
}
