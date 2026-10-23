import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/her_insights.dart';
import 'account_storage.dart';

/// Keeps one account's [InsightMemory] on the device. Never sent anywhere.
/// With no account it holds nothing.
class InsightMemoryStore {
  InsightMemoryStore(String? accountId)
      : _key = accountId == null
            ? null
            : AccountStorage.key('mooncycle.insights.v1', accountId);

  final String? _key;

  Future<InsightMemory> load() async {
    final key = _key;
    if (key == null) return const InsightMemory();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return const InsightMemory();
    try {
      return InsightMemory.fromJson(
        (jsonDecode(raw) as Map).cast<String, Object?>(),
      );
    } on FormatException {
      return const InsightMemory();
    }
  }

  Future<void> save(InsightMemory memory) async {
    final key = _key;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(memory.toJson()));
  }

  Future<void> clear() async {
    final key = _key;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}
