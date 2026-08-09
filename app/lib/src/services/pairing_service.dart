import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'pairing_crypto.dart';
import 'push.dart';
import 'relay_api.dart';

/// A stored browser pairing (phone side).
class StoredPairing {
  StoredPairing({
    required this.pairingId,
    required this.phoneToken,
    required this.sessionKeyB64,
    required this.relayUrl,
    required this.pairedAt,
  });

  final String pairingId;
  final String phoneToken;
  final String sessionKeyB64;
  final String relayUrl;
  final DateTime pairedAt;

  Uint8List get sessionKey =>
      Uint8List.fromList(base64.decode(sessionKeyB64));

  Map<String, dynamic> toJson() => {
        'pairingId': pairingId,
        'phoneToken': phoneToken,
        'sessionKeyB64': sessionKeyB64,
        'relayUrl': relayUrl,
        'pairedAt': pairedAt.toUtc().toIso8601String(),
      };

  static StoredPairing fromJson(Map<String, dynamic> json) => StoredPairing(
        pairingId: json['pairingId'] as String,
        phoneToken: json['phoneToken'] as String,
        sessionKeyB64: json['sessionKeyB64'] as String,
        relayUrl: json['relayUrl'] as String,
        pairedAt: DateTime.parse(json['pairedAt'] as String),
      );
}

class PairingService {
  PairingService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
        );

  final FlutterSecureStorage _storage;
  static const _key = 'twokeys.pairing';

  Future<StoredPairing?> current() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    return StoredPairing.fromJson(json.decode(raw) as Map<String, dynamic>);
  }

  Future<void> _save(StoredPairing pairing) =>
      _storage.write(key: _key, value: json.encode(pairing.toJson()));

  /// Completes a pairing from a scanned `purr-pair:` QR payload.
  /// Throws [FormatException] on unusable QR content.
  Future<StoredPairing> completeFromQr(String qrPayload) async {
    if (!qrPayload.startsWith('purr-pair:')) {
      throw const FormatException('Not a pairing code');
    }
    final Map<String, dynamic> data;
    try {
      data = json.decode(
        utf8.decode(base64.decode(
            base64.normalize(qrPayload.substring('purr-pair:'.length)))),
      ) as Map<String, dynamic>;
    } catch (_) {
      throw const FormatException('That pairing code is damaged');
    }
    final relayUrl = data['relay'] as String? ?? RelayApi.defaultBaseUrl;
    final pairingId = data['pairingId'] as String?;
    final extPub = data['extPub'] as String?;
    final secret = data['secret'] as String?;
    if (pairingId == null || extPub == null || secret == null) {
      throw const FormatException('That pairing code is incomplete');
    }

    final keyPair = await PairingCrypto.generateKeyPair();
    final sessionKey = await PairingCrypto.deriveSessionKey(
      ourKeyPair: keyPair,
      theirPub: Uint8List.fromList(base64.decode(extPub)),
      pairingSecret: Uint8List.fromList(base64.decode(secret)),
    );

    final deviceName = await _deviceName();
    final nameBlob =
        await PairingCrypto.seal(sessionKey, {'name': deviceName});

    final api = RelayApi(baseUrl: relayUrl);
    final pub = await keyPair.extractPublicKey();
    // Send our push token now (if push is configured) so the relay can wake us
    // immediately — no need to wait for the next app start.
    final fcmToken = await PushService.token();
    final result = await api.completePairing(
      pairingId: pairingId,
      phonePubB64: base64.encode(pub.bytes),
      phoneNameBlobB64: nameBlob,
      fcmToken: fcmToken,
    );
    // Sanity: the extension pubkey the relay reports must match the QR —
    // if it doesn't, someone is playing games; abort.
    if (result.extPub != extPub) {
      throw const FormatException('The pairing looks tampered with');
    }

    final pairing = StoredPairing(
      pairingId: pairingId,
      phoneToken: result.phoneToken,
      sessionKeyB64: base64.encode(sessionKey),
      relayUrl: relayUrl,
      pairedAt: DateTime.now().toUtc(),
    );
    await _save(pairing);
    return pairing;
  }

  Future<void> unpair() async {
    final pairing = await current();
    if (pairing != null) {
      await RelayApi(baseUrl: pairing.relayUrl)
          .unpair(pairingId: pairing.pairingId, token: pairing.phoneToken)
          .catchError((_) {});
    }
    await _storage.delete(key: _key);
  }

  Future<String> _deviceName() async {
    // A friendly name without extra plugins; refine later with device_info.
    if (Platform.isAndroid) return 'Your Android phone';
    if (Platform.isIOS) return 'Your iPhone';
    return 'Your phone';
  }
}
