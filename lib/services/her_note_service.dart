import 'api_client.dart';

/// Asks the server for her AI-written note. Only used when she has turned
/// AI-written notes on.
class HerNoteService {
  HerNoteService([ApiClient? api]) : _api = api ?? ApiClient();

  final ApiClient _api;

  /// The note, or null whenever there is none for any reason: her phone
  /// then shows the reviewed card, so nothing here is an error for her.
  Future<String?> fetch(Map<String, Object?> request) async {
    try {
      final response = await _api.send(
        'POST',
        '/her-note',
        body: request,
        // Writing and checking a note can take a while.
        timeout: const Duration(seconds: 90),
      );
      if (response.statusCode != 200) return null;
      final note = ApiClient.json(response)['note'];
      return note is String && note.trim().isNotEmpty ? note.trim() : null;
    } on ApiException {
      return null;
    }
  }
}
