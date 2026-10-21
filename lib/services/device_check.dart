import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:local_auth/local_auth.dart';

enum DeviceCheckResult {
  /// The fingerprint, face or PIN matched.
  passed,

  /// The prompt was closed, or the check did not match.
  cancelled,

  /// The phone could not ask, for example no lock is set: use the password.
  unavailable,
}

/// The phone's own lock (fingerprint, face, PIN, pattern or passcode), used to
/// confirm deleting the account. Android and iPhone only; the website and
/// desktop builds use the password.
class DeviceCheck {
  DeviceCheck._();

  static final _auth = LocalAuthentication();

  static bool get _onPhone =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Whether this phone has a lock to check with.
  static Future<bool> available() async {
    if (!_onPhone) return false;
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Shows the phone's own prompt with [reason] under it. The PIN or
  /// passcode is always offered as well as the fingerprint or face.
  static Future<DeviceCheckResult> confirm(String reason) async {
    try {
      final passed = await _auth.authenticate(localizedReason: reason);
      return passed ? DeviceCheckResult.passed : DeviceCheckResult.cancelled;
    } on LocalAuthException catch (e) {
      switch (e.code) {
        case LocalAuthExceptionCode.userCanceled:
        case LocalAuthExceptionCode.systemCanceled:
        case LocalAuthExceptionCode.timeout:
        case LocalAuthExceptionCode.authInProgress:
          return DeviceCheckResult.cancelled;
        default:
          return DeviceCheckResult.unavailable;
      }
    } catch (_) {
      return DeviceCheckResult.unavailable;
    }
  }
}
