import 'api_client.dart';

/// The server's answer to one chat message.
class ChatAnswer {
  const ChatAnswer({
    this.reply,
    this.urgent = false,
    this.suggestions = const [],
    this.remaining,
    this.limitReached = false,
  });

  /// Null when there is no answer: no connection, or the server could not
  /// write one.
  final String? reply;
  final bool urgent;
  final List<String> suggestions;

  /// Messages left today, when the server said.
  final int? remaining;

  /// Today's 20 messages are used up.
  final bool limitReached;
}

/// Sends her chat messages to the server, which has them answered and
/// forgets them. Only used when she has turned the AI chat on.
class HerChatService {
  HerChatService([ApiClient? api]) : _api = api ?? ApiClient();

  final ApiClient _api;

  Future<ChatAnswer> send({
    required String language,
    required Map<String, Object?> context,
    required List<Map<String, Object?>> messages,
  }) async {
    try {
      final response = await _api.send(
        'POST',
        '/her-chat',
        body: {
          'language': language,
          'context': context,
          'messages': messages,
        },
        // Writing and checking an answer can take a while.
        timeout: const Duration(seconds: 90),
      );
      if (response.statusCode != 200) return const ChatAnswer();
      final json = ApiClient.json(response);
      final reply = json['reply'];
      final remaining = json['remaining'];
      return ChatAnswer(
        reply: reply is String && reply.trim().isNotEmpty ? reply.trim() : null,
        urgent: json['urgent'] == true,
        suggestions: [
          for (final s in (json['suggestions'] as List?) ?? const [])
            if (s is String) s,
        ],
        remaining: remaining is num ? remaining.toInt() : null,
        limitReached: json['limit'] == true,
      );
    } on ApiException {
      return const ChatAnswer();
    }
  }

  /// Reports an answer. Only the answer is sent, never who she is or what
  /// she wrote. True when the server has it.
  Future<bool> report(String answer) async {
    try {
      final response = await _api.send(
        'POST',
        '/her-chat/report',
        body: {'answer': answer},
      );
      return response.statusCode == 200;
    } on ApiException {
      return false;
    }
  }
}
