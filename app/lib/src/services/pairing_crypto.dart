import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Mirror of extension/src/lib/crypto.ts — the two sides must produce
/// byte-identical session keys and interoperable sealed blobs:
///
///   shared  = X25519(ourPriv, theirPub)
///   session = HKDF-SHA256(ikm=shared, salt=pairingSecret, info="twokeys/pairing-v1")
///   blob    = base64(nonce24 || XChaCha20-Poly1305(session, nonce24, plaintext))
class PairingCrypto {
  PairingCrypto._();

  static final _x25519 = X25519();
  static final _aead = Xchacha20.poly1305Aead();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  static Future<SimpleKeyPair> generateKeyPair() => _x25519.newKeyPair();

  static Future<Uint8List> deriveSessionKey({
    required SimpleKeyPair ourKeyPair,
    required Uint8List theirPub,
    required Uint8List pairingSecret,
  }) async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: ourKeyPair,
      remotePublicKey:
          SimplePublicKey(theirPub, type: KeyPairType.x25519),
    );
    final session = await _hkdf.deriveKey(
      secretKey: shared,
      nonce: pairingSecret,
      info: utf8.encode('twokeys/pairing-v1'),
    );
    return Uint8List.fromList(await session.extractBytes());
  }

  static Future<String> seal(
    Uint8List sessionKey,
    Map<String, dynamic> payload,
  ) async {
    final nonce = _randomBytes(24);
    final box = await _aead.encrypt(
      utf8.encode(json.encode(payload)),
      secretKey: SecretKey(sessionKey),
      nonce: nonce,
    );
    return base64.encode([...nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  static Future<Map<String, dynamic>> open(
    Uint8List sessionKey,
    String blobB64,
  ) async {
    final raw = base64.decode(blobB64);
    final box = SecretBox(
      raw.sublist(24, raw.length - 16),
      nonce: raw.sublist(0, 24),
      mac: Mac(raw.sublist(raw.length - 16)),
    );
    final clear =
        await _aead.decrypt(box, secretKey: SecretKey(sessionKey));
    return json.decode(utf8.decode(clear)) as Map<String, dynamic>;
  }

  static Uint8List _randomBytes(int n) {
    final random = SecureRandom.fast;
    final bytes = Uint8List(n);
    for (var i = 0; i < n; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }
}
