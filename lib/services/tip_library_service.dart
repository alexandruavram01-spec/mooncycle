import 'api_client.dart';

/// How people rated one daily tip, and whether it is pulled.
class TipRating {
  const TipRating({
    required this.code,
    this.likes = 0,
    this.notFunny = 0,
    this.notOkay = 0,
    this.pulled = false,
  });

  final String code;
  final int likes;
  final int notFunny;
  final int notOkay;

  /// Someone flagged it "not okay": nobody sees it until an editor puts it
  /// back.
  final bool pulled;
}

/// Feedback on the daily partner tips. The tips themselves are in the app
/// (`lib/l10n/`); the server only knows their codes, who rated them, and
/// which are pulled.
class TipLibraryService {
  TipLibraryService([ApiClient? api]) : _api = api ?? ApiClient();

  final ApiClient _api;

  /// Codes of the tips taken down for everyone.
  Future<Set<String>> pulled() async {
    final response = await _api.send('GET', '/tips/pulled');
    if (response.statusCode != 200) throw ApiClient.failure(response);
    return ((ApiClient.json(response)['codes'] as List?) ?? const [])
        .whereType<String>()
        .toSet();
  }

  /// `like`, `not_funny` or `not_okay`. A "not okay" takes the tip down for
  /// everyone until an editor looks at it.
  Future<void> rate(String code, String kind) async {
    final response = await _api.send(
      'POST',
      '/tips/rating',
      body: {'code': code, 'kind': kind},
    );
    if (response.statusCode != 200) throw ApiClient.failure(response);
  }

  Future<bool> isEditor() async {
    final response = await _api.send('GET', '/account');
    if (response.statusCode != 200) throw ApiClient.failure(response);
    return ApiClient.json(response)['admin'] == true;
  }

  /// Every tip that has been rated or pulled. Editors only.
  Future<List<TipRating>> ratings() async {
    final response = await _api.send('GET', '/admin/tips/ratings');
    if (response.statusCode != 200) throw ApiClient.failure(response);
    final rows = ((ApiClient.json(response)['ratings'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => m.cast<String, Object?>());
    return [
      for (final row in rows)
        TipRating(
          code: row['code'] as String,
          likes: (row['likes'] as num?)?.toInt() ?? 0,
          notFunny: (row['notFunny'] as num?)?.toInt() ?? 0,
          notOkay: (row['notOkay'] as num?)?.toInt() ?? 0,
          pulled: row['pulled'] == true,
        ),
    ];
  }

  /// Puts a pulled tip back. Editors only.
  Future<void> restore(String code) async {
    final response = await _api.send(
      'POST',
      '/admin/tips/restore',
      body: {'code': code},
    );
    if (response.statusCode != 200) throw ApiClient.failure(response);
  }
}
