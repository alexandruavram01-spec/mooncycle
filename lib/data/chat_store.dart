import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/her_chat.dart';
import 'account_storage.dart';

/// Keeps one account's AI chat on the device. The server keeps none of it.
/// With no account it holds nothing.
class ChatStore {
  ChatStore(String? accountId)
      : _key = accountId == null ? null : AccountStorage.key(AccountStorage.chatKey, accountId);

  final String? _key;

  Future<ChatHistory> load() async {
    final key = _key;
    if (key == null) return const ChatHistory();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return const ChatHistory();
    try {
      return ChatHistory.fromJson(
        (jsonDecode(raw) as Map).cast<String, Object?>(),
      );
    } on FormatException {
      return const ChatHistory();
    }
  }

  Future<void> save(ChatHistory history) async {
    final key = _key;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(history.toJson()));
  }

  Future<void> clear() async {
    final key = _key;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}
