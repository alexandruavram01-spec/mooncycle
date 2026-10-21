import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/enums.dart';
import '../domain/models.dart';
import '../domain/profile.dart';
import 'api_client.dart';

/// Where her side of the pairing stands.
class PairingState {
  const PairingState.linked({
    this.ask,
    this.reaction,
    this.offer,
    this.offerReply,
    this.partnerTone,
  })  : linked = true,
        code = null;
  const PairingState.waiting(String value)
      : linked = false,
        code = value,
        ask = null,
        reaction = null,
        offer = null,
        offerReply = null,
        partnerTone = null;

  /// The tone he picked, so her app can show the tip he sees. Null until
  /// his app has reported it.
  final PartnerTone? partnerTone;

  final bool linked;

  /// The single-use code to hand over. Null once a partner has redeemed it.
  final String? code;

  /// The ask she sent and his reply to it, while it is still showing on his
  /// screen. Codes such as A01 and R02; the words are in `lib/l10n/`.
  final String? ask;
  final String? reaction;

  /// What he offered her and her answer. Codes such as O03 and O13.
  final String? offer;
  final String? offerReply;
}

/// What the partner's device receives.
class SharedSnapshot {
  const SharedSnapshot({
    required this.snapshot,
    required this.updatedAt,
    this.ask,
    this.askAt,
    this.reaction,
    this.offer,
    this.offerReply,
  });

  final PartnerSnapshot snapshot;
  final DateTime updatedAt;

  /// Her current ask and when she sent it, and his reply. Null when there is
  /// none, or it is more than a day old.
  final String? ask;
  final DateTime? askAt;
  final String? reaction;

  /// His current offer and her answer to it.
  final String? offer;
  final String? offerReply;
}

/// Partner pairing over the MoonCycle API.
///
/// Pairing is between two accounts. Only the redacted [PartnerSnapshot] ever
/// leaves the device — raw logs and free-text notes are never part of a
/// request.
class PartnerLinkService {
  PartnerLinkService([ApiClient? api]) : _api = api ?? ApiClient();

  final ApiClient _api;

  static const _codeKey = 'mooncycle.partner.code';
  static const _codeExpiryKey = 'mooncycle.partner.codeExpiry';
  static const _revokePendingKey = 'mooncycle.partner.revokePending';
  static const _joinedKey = 'mooncycle.partner.joined';

  // ---- Her side -----------------------------------------------------------

  /// Current pairing. Issues a code if there is neither a connected partner
  /// nor an unexpired code.
  Future<PairingState> pairing() async {
    final response = await _api.send('GET', '/pairings');
    if (response.statusCode != 200) throw ApiClient.failure(response);
    final status = ApiClient.json(response);
    if (status['linked'] == true) {
      return PairingState.linked(
        ask: status['ask'] as String?,
        reaction: status['reaction'] as String?,
        offer: status['offer'] as String?,
        offerReply: status['offerReply'] as String?,
        partnerTone: _tone(status['partnerTone']),
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_codeKey);
    final expiry = prefs.getInt(_codeExpiryKey) ?? 0;
    if (code != null && DateTime.now().millisecondsSinceEpoch < expiry) {
      return PairingState.waiting(code);
    }
    return PairingState.waiting(await newCode());
  }

  /// Issues a fresh code. The server drops any connected partner and the
  /// stored snapshot when it does this, so it doubles as "disconnect".
  Future<String> newCode() async {
    final response = await _api.send('POST', '/pairings');
    if (response.statusCode != 200) throw ApiClient.failure(response);
    final json = ApiClient.json(response);
    final code = json['code'] as String;
    final hours = (json['expiresInHours'] as num?)?.toInt() ?? 24;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_codeKey, code);
    await prefs.setInt(
      _codeExpiryKey,
      DateTime.now().add(Duration(hours: hours)).millisecondsSinceEpoch,
    );
    return code;
  }

  /// Uploads the redacted snapshot. Does nothing while signed out.
  Future<void> publishSnapshot(PartnerSnapshot snapshot) async {
    if (!await _api.hasSession()) return;

    final response =
        await _api.send('PUT', '/snapshot', body: encodeSnapshot(snapshot));
    // 409: no pairing exists yet, so there is nobody to share with.
    if (response.statusCode != 200 && response.statusCode != 409) {
      throw ApiClient.failure(response);
    }
  }

  /// Sends him one of the fixed asks, or takes the current one back with
  /// null. Only the code is sent; each phone shows it in its own language.
  Future<void> sendAsk(String? key) => _put('/ask', {'ask': key});

  /// She answers his offer, or takes the answer back with null.
  Future<void> replyToOffer(String? key) =>
      _put('/offer/reply', {'reply': key});

  /// He answers her current ask, or takes the answer back with null.
  Future<void> react(String? key) => _put('/ask/reaction', {'reaction': key});

  /// He offers her something, or withdraws the offer with null.
  Future<void> sendOffer(String? key) => _put('/offer', {'offer': key});

  /// He reports the tone he picked. Does nothing while signed out.
  Future<void> shareTone(PartnerTone tone) async {
    if (!await _api.hasSession()) return;
    await _put('/partner/tone', {'tone': tone.name});
  }

  Future<void> _put(String path, Map<String, Object?> body) async {
    final response = await _api.send('PUT', path, body: body);
    if (response.statusCode != 200) throw ApiClient.failure(response);
  }

  /// Removes the pairing and the stored snapshot from the server. If the
  /// request cannot be sent it is remembered and retried by [retryRevoke].
  Future<void> revoke() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_codeKey);
    await prefs.remove(_codeExpiryKey);
    if (!await _api.hasSession()) {
      await prefs.remove(_revokePendingKey);
      return;
    }

    await prefs.setBool(_revokePendingKey, true);
    final response = await _api.send('DELETE', '/pairings');
    if (response.statusCode != 200) throw ApiClient.failure(response);
    await prefs.remove(_revokePendingKey);
  }

  Future<void> retryRevoke() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_revokePendingKey) ?? false) await revoke();
  }

  // ---- His side -----------------------------------------------------------

  /// Whether this account is connected as a partner. The server decides; the
  /// last known answer is used when it cannot be reached.
  Future<bool> hasJoined() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final response = await _api.send('GET', '/pairings');
      if (response.statusCode == 200) {
        final joined = ApiClient.json(response)['joined'] == true;
        await prefs.setBool(_joinedKey, joined);
        return joined;
      }
    } on ApiException {
      // Fall back to what this device last knew.
    }
    return prefs.getBool(_joinedKey) ?? false;
  }

  Future<void> join(String code) async {
    final response = await _api.send(
      'POST',
      '/pairings/join',
      body: {'code': code.trim().toUpperCase()},
    );
    if (response.statusCode == 404) {
      throw const ApiException(
        'That code is not valid or has expired. Ask her for a new one.',
      );
    }
    if (response.statusCode != 200) throw ApiClient.failure(response);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_joinedKey, true);
  }

  /// The latest snapshot she shared, or null if nothing is shared right now.
  Future<SharedSnapshot?> fetchShared() async {
    final response = await _api.send('GET', '/snapshot');
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) throw ApiClient.failure(response);

    final json = ApiClient.json(response);
    final askAt = json['askAt'] as String?;
    return SharedSnapshot(
      snapshot: decodeSnapshot(
        (json['snapshot'] as Map).cast<String, Object?>(),
      ),
      updatedAt: DateTime.parse(json['updatedAt'] as String).toLocal(),
      ask: json['ask'] as String?,
      askAt: askAt == null ? null : DateTime.tryParse(askAt)?.toLocal(),
      reaction: json['reaction'] as String?,
      offer: json['offer'] as String?,
      offerReply: json['offerReply'] as String?,
    );
  }

  /// Disconnects from her, so another code can be entered.
  Future<void> leave() async {
    final response = await _api.send('POST', '/pairings/leave');
    if (response.statusCode != 200) throw ApiClient.failure(response);

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_joinedKey);
  }

  /// Clears what this device remembers about pairing. Used when the account
  /// signs out, since the next person to sign in may be someone else.
  Future<void> forgetLocal() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      _codeKey,
      _codeExpiryKey,
      _revokePendingKey,
      _joinedKey,
    ]) {
      await prefs.remove(key);
    }
  }

  // ---- Payload ------------------------------------------------------------

  /// The exact payload a partner device receives. Deliberately contains no
  /// raw logs — only the redacted snapshot the user opted into — and no
  /// sentences: his app writes those in his own language.
  static String encodeSnapshot(PartnerSnapshot snapshot) => jsonEncode({
        'v': 2,
        'dayOfCycle': snapshot.dayOfCycle,
        'phase': snapshot.phase?.name,
        'nextPhase': snapshot.nextPhase?.name,
        'daysUntilNextPhase': snapshot.daysUntilNextPhase,
        'jokes': snapshot.jokes,
        'daysUntilNextPeriod': snapshot.daysUntilNextPeriod,
        'symptoms': snapshot.sharedSymptoms,
        'energy': snapshot.energy,
      });

  static PartnerSnapshot decodeSnapshot(Map<String, Object?> json) =>
      PartnerSnapshot(
        dayOfCycle: (json['dayOfCycle'] as num?)?.toInt(),
        phase: _phase(json['phase']),
        nextPhase: _phase(json['nextPhase']),
        daysUntilNextPhase: (json['daysUntilNextPhase'] as num?)?.toInt(),
        // Missing in summaries from older builds: no jokes, to be safe.
        jokes: json['jokes'] == true,
        daysUntilNextPeriod:
            (json['daysUntilNextPeriod'] as num?)?.toInt() ?? -999,
        sharedSymptoms: _strings(json['symptoms']),
        energy: (json['energy'] as num?)?.toInt(),
      );

  static PartnerTone? _tone(Object? name) {
    for (final tone in PartnerTone.values) {
      if (tone.name == name) return tone;
    }
    return null;
  }

  /// Null when she does not share the phase, or the name is not one we know.
  static CyclePhase? _phase(Object? name) {
    for (final phase in CyclePhase.values) {
      if (phase.name == name) return phase;
    }
    return null;
  }

  static List<String> _strings(Object? value) =>
      value is List ? value.whereType<String>().toList() : const <String>[];
}
