import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'pairing_crypto.dart';
import 'push.dart';
import 'relay_api.dart';

/// A stored browser pairing (phone side). One phone holds many of these — the
/// vault stays on this device (that is the product), but it can serve any
/// number of browsers, each with its own session key and relay row.
class StoredPairing {
  StoredPairing({
    required this.pairingId,
    required this.phoneToken,
    required this.sessionKeyB64,
    required this.relayUrl,
    required this.pairedAt,
    this.browserName,
  });

  final String pairingId;
  final String phoneToken;
  final String sessionKeyB64;
  final String relayUrl;
  final DateTime pairedAt;

  /// What the browser called itself at pairing time ("Chrome · Mac"), or null
  /// for pairings made before names were exchanged. Cosmetic only.
  final String? browserName;

  Uint8List get sessionKey =>
      Uint8List.fromList(base64.decode(sessionKeyB64));

  Map<String, dynamic> toJson() => {
        'pairingId': pairingId,
        'phoneToken': phoneToken,
        'sessionKeyB64': sessionKeyB64,
        'relayUrl': relayUrl,
        'pairedAt': pairedAt.toUtc().toIso8601String(),
        if (browserName != null) 'browserName': browserName,
      };

  static StoredPairing fromJson(Map<String, dynamic> json) => StoredPairing(
        pairingId: json['pairingId'] as String,
        phoneToken: json['phoneToken'] as String,
        sessionKeyB64: json['sessionKeyB64'] as String,
        relayUrl: json['relayUrl'] as String,
        pairedAt: DateTime.parse(json['pairedAt'] as String),
        browserName: json['browserName'] as String?,
      );
}

/// The handful of secure-storage operations the pairing store needs, behind a
/// seam so the legacy-to-list migration can be exercised in tests without the
/// platform plugin. Losing a pairing on upgrade is the worst failure here, so
/// that path is worth being able to test directly.
abstract class PairingStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecurePairingStorage implements PairingStorage {
  const SecurePairingStorage([
    this._storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ),
  ]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class PairingService {
  PairingService({PairingStorage? storage})
      : _storage = storage ?? const SecurePairingStorage();

  final PairingStorage _storage;

  /// The list of pairings. [_legacyKey] held a single pairing object before
  /// multi-browser support and is migrated into the list on first read.
  static const _key = 'twokeys.pairings';
  static const _legacyKey = 'twokeys.pairing';

  /// Every paired browser, oldest first. Migrates a pre-list install in place.
  Future<List<StoredPairing>> all() async {
    final raw = await _storage.read(_key);
    if (raw != null) {
      return [
        for (final e in json.decode(raw) as List)
          StoredPairing.fromJson(e as Map<String, dynamic>),
      ];
    }
    // Migration: fold a single stored pairing into the new list. Write the
    // list before deleting the old key, so an interrupted migration leaves the
    // pairing readable under one key or the other — never neither.
    final legacy = await _storage.read(_legacyKey);
    if (legacy == null) return const [];
    final pairing =
        StoredPairing.fromJson(json.decode(legacy) as Map<String, dynamic>);
    await _saveAll([pairing]);
    await _storage.delete(_legacyKey);
    return [pairing];
  }

  /// The pairing with [pairingId], or null if it is no longer paired.
  Future<StoredPairing?> byId(String pairingId) async {
    for (final p in await all()) {
      if (p.pairingId == pairingId) return p;
    }
    return null;
  }

  Future<void> _saveAll(List<StoredPairing> pairings) => _storage.write(
        _key,
        json.encode([for (final p in pairings) p.toJson()]),
      );

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
    final secretBytes = Uint8List.fromList(base64.decode(secret));
    final sessionKey = await PairingCrypto.deriveSessionKey(
      ourKeyPair: keyPair,
      theirPub: Uint8List.fromList(base64.decode(extPub)),
      pairingSecret: secretBytes,
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
      browserName: await _browserName(
        api: api,
        pairingId: pairingId,
        phoneToken: result.phoneToken,
        pairingSecret: secretBytes,
      ),
    );
    // Re-pairing the same browser replaces its entry rather than duplicating.
    final next = [
      for (final p in await all())
        if (p.pairingId != pairingId) p,
      pairing,
    ];
    await _saveAll(next);
    return pairing;
  }

  /// The browser's self-chosen label, or null when it did not leave one (an
  /// older extension) or the relay is unreachable. Purely cosmetic, so every
  /// failure here degrades to an unnamed entry instead of failing the pairing.
  Future<String?> _browserName({
    required RelayApi api,
    required String pairingId,
    required String phoneToken,
    required Uint8List pairingSecret,
  }) async {
    try {
      final blob = await api.pairingInfo(
        pairingId: pairingId,
        phoneToken: phoneToken,
      );
      if (blob == null) return null;
      final opened = await PairingCrypto.open(
        await PairingCrypto.deriveNameKey(pairingSecret),
        blob,
      );
      final name = opened['name'] as String?;
      if (name == null || name.trim().isEmpty) return null;
      // Bound it: this string is chosen by the browser and rendered in a list.
      return name.length > 40 ? name.substring(0, 40) : name;
    } catch (_) {
      return null;
    }
  }

  /// Unpairs one browser. "Unpairing only affects this browser" — the other
  /// pairings and the vault are untouched.
  Future<void> unpair(String pairingId) async {
    final remaining = <StoredPairing>[];
    for (final p in await all()) {
      if (p.pairingId == pairingId) {
        await RelayApi(baseUrl: p.relayUrl)
            .unpair(pairingId: p.pairingId, token: p.phoneToken)
            .catchError((_) {});
      } else {
        remaining.add(p);
      }
    }
    await _saveAll(remaining);
  }

  Future<String> _deviceName() async {
    // A friendly name without extra plugins; refine later with device_info.
    if (Platform.isAndroid) return 'Your Android phone';
    if (Platform.isIOS) return 'Your iPhone';
    return 'Your phone';
  }
}
