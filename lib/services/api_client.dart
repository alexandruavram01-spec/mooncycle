import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// A failure the UI can show as-is.
class ApiException implements Exception {
  const ApiException(this.message, {this.status});

  final String message;
  final int? status;

  @override
  String toString() => message;
}

/// Talks to the MoonCycle API and holds the signed-in session for this
/// device.
class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Set at build time with `--dart-define=MOONCYCLE_API=...` to point the
  /// app somewhere else, such as a test server.
  static const _override = String.fromEnvironment('MOONCYCLE_API');
  static const _appBaseUrl = 'https://mooncycle.fit/api';
  static const _timeout = Duration(seconds: 15);

  /// The website calls the API on whatever domain it was loaded from, so the
  /// same build works on any domain. The phone app has no such origin and
  /// uses the fixed address.
  static Uri _url(String path) {
    if (_override.isNotEmpty) return Uri.parse('$_override$path');
    if (kIsWeb) return Uri.base.resolve('/api$path');
    return Uri.parse('$_appBaseUrl$path');
  }

  static const _tokenKey = 'mooncycle.account.token';
  static const _emailKey = 'mooncycle.account.email';

  /// Called when the server rejects the stored session, so the app can go
  /// back to the sign-in screen.
  void Function()? onSessionLost;

  Future<bool> hasSession() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey) != null;
  }

  /// The signed-in email, or null when nobody is signed in.
  Future<String?> signedInEmail() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_tokenKey) == null) return null;
    return prefs.getString(_emailKey);
  }

  Future<void> saveSession({
    required String email,
    required String token,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_emailKey, email);
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_emailKey);
  }

  /// Sends a request. With [auth], it carries the session token, and a 401
  /// ends the local session. [timeout] overrides the usual 15 seconds for
  /// calls known to be slow.
  Future<http.Response> send(
    String method,
    String path, {
    Object? body,
    bool auth = true,
    Duration? timeout,
  }) async {
    final limit = timeout ?? _timeout;
    final request = http.Request(method, _url(path));
    if (auth) {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenKey);
      if (token == null) {
        throw const ApiException('Sign in first.', status: 401);
      }
      request.headers['Authorization'] = 'Bearer $token';
    }
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = body is String ? body : jsonEncode(body);
    }

    final http.Response response;
    try {
      final streamed = await _client.send(request).timeout(limit);
      response = await http.Response.fromStream(streamed).timeout(limit);
    } catch (_) {
      throw const ApiException(
        'Could not reach the server. Check your connection and try again.',
      );
    }

    if (auth && response.statusCode == 401) {
      await clearSession();
      onSessionLost?.call();
      throw const ApiException('Please sign in again.', status: 401);
    }
    return response;
  }

  static Map<String, Object?> json(http.Response response) =>
      (jsonDecode(response.body) as Map).cast<String, Object?>();

  /// Turns an error response into something to show. The server words its
  /// account errors for people, so those are passed through.
  static ApiException failure(http.Response response) {
    final status = response.statusCode;
    if (status == 429) {
      return const ApiException(
        'Too many attempts. Wait a few minutes and try again.',
        status: 429,
      );
    }
    if (status == 400 ||
        status == 401 ||
        status == 403 ||
        status == 409 ||
        status == 502) {
      try {
        final message = json(response)['error'];
        if (message is String && message.isNotEmpty) {
          return ApiException(message, status: status);
        }
      } catch (_) {
        // Not JSON: fall through to the generic message.
      }
    }
    return ApiException(
      'The server answered with an error ($status).',
      status: status,
    );
  }
}
