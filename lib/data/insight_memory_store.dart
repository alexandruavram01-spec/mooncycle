import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/her_insights.dart';

/// Keeps [InsightMemory] on the device. Never sent anywhere.
class InsightMemoryStore {
  static const _key = 'mooncycle.insights.v1';

  Future<InsightMemory> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(memory.toJson()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
