import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Client for the Purr relay (server/). Everything the phone sends or
/// receives through here is ciphertext except routing metadata.
class RelayApi {
  RelayApi({this.baseUrl = defaultBaseUrl, http.Client? client})
      : _client = client ?? http.Client();

  /// Overridable at build time for local/staging testing:
  ///   flutter build apk --dart-define=TWOKEYS_RELAY=http://10.0.2.2:3000
  static const defaultBaseUrl = String.fromEnvironment(
    'TWOKEYS_RELAY',
    defaultValue: 'https://2fa.apps.not-final.com',
  );

  final String baseUrl;
  final http.Client _client;

  Uri _u(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> _headers({String? bearer}) => {
        'content-type': 'application/json',
        if (bearer != null) 'authorization': 'Bearer $bearer',
      };

  // ---- Backups -----------------------------------------------------------

  Future<void> uploadBackup({
    required String backupId,
    required String backupAuth,
    required Uint8List blob,
    required String digest,
  }) async {
    final res = await _client.put(
      _u('/v1/backups/$backupId'),
      headers: _headers(),
      body: json.encode({
        'blob': base64.encode(blob),
        'digest': digest,
        'backupAuth': backupAuth,
      }),
    );
    if (res.statusCode != 200) {
      throw RelayException('backup upload', res.statusCode);
    }
    // Write-time verification (research commandment 6): the server echoes the
    // digest; a mismatch means corruption in transit.
    final body = json.decode(res.body) as Map<String, dynamic>;
    if (body['digest'] != digest) {
      throw const RelayCorruptionException();
    }
  }

  Future<(Uint8List blob, String digest)?> fetchBackup({
    required String backupId,
    required String backupAuth,
  }) async {
    final res = await _client.post(
      _u('/v1/backups/$backupId/fetch'),
      headers: _headers(),
      body: json.encode({'backupAuth': backupAuth}),
    );
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw RelayException('backup fetch', res.statusCode);
    }
    final body = json.decode(res.body) as Map<String, dynamic>;
    return (
      Uint8List.fromList(base64.decode(body['blob'] as String)),
      body['digest'] as String,
    );
  }

  Future<void> deleteBackup({
    required String backupId,
    required String backupAuth,
  }) async {
    final res = await _client.delete(
      _u('/v1/backups/$backupId'),
      headers: _headers(bearer: backupAuth),
    );
    if (res.statusCode != 204 && res.statusCode != 404) {
      throw RelayException('backup delete', res.statusCode);
    }
  }

  // ---- Pairing (phone side) ---------------------------------------------

  Future<({String phoneToken, String extPub})> completePairing({
    required String pairingId,
    required String phonePubB64,
    String? phoneNameBlobB64,
    String? fcmToken,
  }) async {
    final res = await _client.post(
      _u('/v1/pairings/$pairingId/complete'),
      headers: _headers(),
      body: json.encode({
        'phonePub': phonePubB64,
        'phoneNameBlob': ?phoneNameBlobB64,
        'fcmToken': ?fcmToken,
      }),
    );
    if (res.statusCode != 200) {
      throw RelayException('pairing complete', res.statusCode);
    }
    final body = json.decode(res.body) as Map<String, dynamic>;
    return (
      phoneToken: body['phoneToken'] as String,
      extPub: body['extPub'] as String,
    );
  }

  Future<void> unpair({
    required String pairingId,
    required String token,
  }) async {
    final res = await _client.delete(
      _u('/v1/pairings/$pairingId'),
      headers: _headers(bearer: token),
    );
    if (res.statusCode != 204 && res.statusCode != 404) {
      throw RelayException('unpair', res.statusCode);
    }
  }

  // ---- Approval requests (phone side) -----------------------------------

  Future<List<PendingRelayRequest>> pendingRequests({
    required String pairingId,
    required String phoneToken,
    bool wait = false,
  }) async {
    final path = wait
        ? '/v1/requests/wait-pending?pairingId=$pairingId'
        : '/v1/requests?pairingId=$pairingId';
    final res =
        await _client.get(_u(path), headers: _headers(bearer: phoneToken));
    if (res.statusCode != 200) {
      throw RelayException('pending requests', res.statusCode);
    }
    final body = json.decode(res.body) as Map<String, dynamic>;
    return [
      for (final r in body['requests'] as List)
        PendingRelayRequest(
          requestId: (r as Map)['requestId'] as String,
          requestBlobB64: r['requestBlob'] as String,
          createdAt:
              DateTime.fromMillisecondsSinceEpoch(r['createdAt'] as int),
          expiresAt:
              DateTime.fromMillisecondsSinceEpoch(r['expiresAt'] as int),
        ),
    ];
  }

  Future<void> answerRequest({
    required String requestId,
    required String phoneToken,
    required String answerBlobB64,
  }) async {
    final res = await _client.post(
      _u('/v1/requests/$requestId/answer'),
      headers: _headers(bearer: phoneToken),
      body: json.encode({'answerBlob': answerBlobB64}),
    );
    if (res.statusCode == 410) throw const RelayExpiredException();
    if (res.statusCode != 204) {
      throw RelayException('answer', res.statusCode);
    }
  }

  Future<void> updateFcmToken({
    required String pairingId,
    required String phoneToken,
    required String fcmToken,
  }) async {
    final res = await _client.put(
      _u('/v1/pairings/$pairingId/fcm-token'),
      headers: _headers(bearer: phoneToken),
      body: json.encode({'fcmToken': fcmToken}),
    );
    if (res.statusCode != 204) {
      throw RelayException('fcm token', res.statusCode);
    }
  }
}

class PendingRelayRequest {
  const PendingRelayRequest({
    required this.requestId,
    required this.requestBlobB64,
    required this.createdAt,
    required this.expiresAt,
  });

  final String requestId;
  final String requestBlobB64;
  final DateTime createdAt;
  final DateTime expiresAt;
}

class RelayException implements Exception {
  const RelayException(this.what, this.status);
  final String what;
  final int status;
  @override
  String toString() => 'Relay $what failed ($status)';
}

class RelayExpiredException implements Exception {
  const RelayExpiredException();
}

class RelayCorruptionException implements Exception {
  const RelayCorruptionException();
}
