import 'api_client.dart';

/// One message in the chat between her and her partner: a fixed card (by
/// code, written in each phone's language) or emojis. Never free text.
class PartnerChatMessage {
  const PartnerChatMessage({
    required this.id,
    required this.fromHer,
    required this.emoji,
    required this.body,
    required this.sentAt,
    this.herReaction,
    this.hisReaction,
  });

  final int id;
  final bool fromHer;

  /// Emojis in [body]; otherwise [body] is a card code such as A01, O03,
  /// R02 or "special:A05" (the reply written for that ask).
  final bool emoji;
  final String body;
  final DateTime sentAt;

  /// "like" or "love", from each of them.
  final String? herReaction;
  final String? hisReaction;

  static PartnerChatMessage? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final body = json['body'];
    final sentAt = DateTime.tryParse('${json['sentAt']}');
    if (id is! num || body is! String || sentAt == null) return null;
    return PartnerChatMessage(
      id: id.toInt(),
      fromHer: json['fromHer'] == true,
      emoji: json['kind'] == 'emoji',
      body: body,
      sentAt: sentAt.toLocal(),
      herReaction: json['herReaction'] as String?,
      hisReaction: json['hisReaction'] as String?,
    );
  }
}

/// The chat as one of them sees it.
class PartnerChat {
  const PartnerChat({required this.isHer, required this.messages});

  /// Whether this phone is hers (she shares) or his.
  final bool isHer;

  /// The last 90 days, oldest first.
  final List<PartnerChatMessage> messages;

  bool mine(PartnerChatMessage m) => m.fromHer == isHer;

  /// The newest message from the other one, for the "new" dot.
  int get latestFromThem {
    for (final m in messages.reversed) {
      if (!mine(m)) return m.id;
    }
    return 0;
  }
}

/// The partner chat over the MoonCycle API. Cards are sent through
/// [PartnerLinkService] (asks, offers and replies), which adds them here.
class PartnerChatService {
  PartnerChatService([ApiClient? api]) : _api = api ?? ApiClient();

  final ApiClient _api;

  /// The chat, or null while they are not connected.
  Future<PartnerChat?> fetch() async {
    if (!await _api.hasSession()) return null;
    final response = await _api.send('GET', '/chat');
    if (response.statusCode == 409) return null;
    if (response.statusCode != 200) throw ApiClient.failure(response);
    final json = ApiClient.json(response);
    return PartnerChat(
      isHer: json['me'] == 'her',
      messages: [
        for (final m in (json['messages'] as List?) ?? const [])
          if (PartnerChatMessage.fromJson(m) case final message?) message,
      ],
    );
  }

  /// Sends emojis (only emojis; the server refuses anything else).
  Future<void> sendEmoji(String emoji) async {
    final response =
        await _api.send('POST', '/chat', body: {'emoji': emoji.trim()});
    if (response.statusCode != 200) throw ApiClient.failure(response);
  }

  /// Likes or loves a message, or takes it back with null.
  Future<void> react(int id, String? reaction) async {
    final response = await _api.send(
      'PUT',
      '/chat/reaction',
      body: {'id': id, 'reaction': reaction},
    );
    if (response.statusCode != 200) throw ApiClient.failure(response);
  }
}
