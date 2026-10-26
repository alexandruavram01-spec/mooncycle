import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Each account keeps its own logs, settings and card memory on the phone,
/// so signing in as someone else never shows the previous person's data,
/// and signing back in brings your own back.
class AccountStorage {
  AccountStorage._();

  /// A short, stable name for [email], used in storage keys and the database
  /// file name: two 32-bit FNV-1a hashes with different seeds.
  static String idFor(String email) {
    final bytes = utf8.encode(email.trim().toLowerCase());
    String fnv(int seed) {
      var h = seed;
      for (final b in bytes) {
        h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF;
      }
      return h.toRadixString(16).padLeft(8, '0');
    }

    return fnv(0x811c9dc5) + fnv(0x01234567);
  }

  /// The storage key [base] for the account [id].
  static String key(String base, String id) => '$base.$id';

  /// Keys every account on the phone shared before 23 October 2026.
  static const legacyKeys = [
    'mooncycle.settings.v1',
    'mooncycle.insights.v1',
    'mooncycle.logs.v1',
  ];

  static const _ownerKey = 'mooncycle.storage.legacyOwner';

  /// Once per phone: what was stored before accounts were kept apart goes to
  /// the first account that opens this version, which is the one that was
  /// signed in. The SQLite file follows in `LocalDatabase.open`.
  static Future<void> claimLegacy(String id) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_ownerKey) != null) return;
    for (final base in legacyKeys) {
      final value = prefs.getString(base);
      if (value != null) {
        if (prefs.getString(key(base, id)) == null) {
          await prefs.setString(key(base, id), value);
        }
        await prefs.remove(base);
      }
    }
    await prefs.setString(_ownerKey, id);
  }

  /// The account that took the shared data, or null if none has yet.
  static Future<String?> legacyOwner() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_ownerKey);
  }

  /// Whether the account has seen the notice that its logs live only on
  /// this phone.
  static const dataNoticeKey = 'mooncycle.dataNotice.v1';

  /// Removes this account's settings, card memory, notice and (on web) logs.
  static Future<void> eraseKeys(String id) async {
    final prefs = await SharedPreferences.getInstance();
    for (final base in [...legacyKeys, dataNoticeKey]) {
      await prefs.remove(key(base, id));
    }
  }
}
