import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Key hierarchy (docs/ARCHITECTURE.md):
///
///   master password ─Argon2id─▶ KEK_pw ────┐
///   recovery entropy ──HKDF──▶ KEK_rec ────┼─ each wraps ─▶ DEK (32 B random)
///   secure-storage convenience copy ───────┘        │
///                                                   ▼
///                                     vault JSON, XChaCha20-Poly1305
///
/// Aegis-style slots: losing any single unlock method never loses data.
/// The envelope is self-contained JSON — the same bytes serve as the local
/// vault file and (re-encrypted under the backup key) the uploaded backup.
class VaultCrypto {
  VaultCrypto._();

  static final _aead = Xchacha20.poly1305Aead();
  static final _random = SecureRandom.fast;

  // OWASP-aligned Argon2id parameters; stored in the envelope so they can be
  // raised later without breaking old vaults (never 2FAS's frozen PBKDF2@10k).
  static const int argonMemoryKiB = 19456;
  static const int argonIterations = 2;
  static const int argonParallelism = 1;

  static Uint8List randomBytes(int n) {
    final b = Uint8List(n);
    for (var i = 0; i < n; i++) {
      b[i] = _random.nextInt(256);
    }
    return b;
  }

  static Uint8List newDek() => randomBytes(32);

  static Future<SecretKey> deriveKekFromPassword({
    required String password,
    required Uint8List salt,
    int memoryKiB = argonMemoryKiB,
    int iterations = argonIterations,
    int parallelism = argonParallelism,
  }) async {
    final argon2 = Argon2id(
      memory: memoryKiB,
      iterations: iterations,
      parallelism: parallelism,
      hashLength: 32,
    );
    return argon2.deriveKeyFromPassword(password: password, nonce: salt);
  }

  static Future<Map<String, dynamic>> _seal(
    List<int> plaintext,
    SecretKey key,
  ) async {
    final nonce = randomBytes(24);
    final box = await _aead.encrypt(plaintext, secretKey: key, nonce: nonce);
    return {
      'nonce': base64.encode(nonce),
      'ct': base64.encode([...box.cipherText, ...box.mac.bytes]),
    };
  }

  static Future<Uint8List> _open(
    Map<String, dynamic> sealed,
    SecretKey key,
  ) async {
    final nonce = base64.decode(sealed['nonce'] as String);
    final raw = base64.decode(sealed['ct'] as String);
    final box = SecretBox(
      raw.sublist(0, raw.length - 16),
      nonce: nonce,
      mac: Mac(raw.sublist(raw.length - 16)),
    );
    final clear = await _aead.decrypt(box, secretKey: key);
    return Uint8List.fromList(clear);
  }

  /// Builds the on-disk envelope: the vault sealed with the DEK, plus one
  /// wrapped copy of the DEK per unlock slot.
  static Future<Map<String, dynamic>> sealVault({
    required Uint8List dek,
    required Map<String, dynamic> vaultJson,
    required String password,
    SecretKey? recoveryKek,
  }) async {
    final dekKey = SecretKey(dek);
    final salt = randomBytes(16);
    final kekPw = await deriveKekFromPassword(password: password, salt: salt);

    final envelope = <String, dynamic>{
      'v': 1,
      'vault': await _seal(utf8.encode(json.encode(vaultJson)), dekKey),
      'slots': <String, dynamic>{
        'password': {
          'salt': base64.encode(salt),
          'm': argonMemoryKiB,
          't': argonIterations,
          'p': argonParallelism,
          ...await _seal(dek, kekPw),
        },
        if (recoveryKek != null) 'recovery': await _seal(dek, recoveryKek),
      },
    };
    return envelope;
  }

  /// Re-seals the vault content under an existing DEK without touching slots.
  static Future<Map<String, dynamic>> resealVaultContent({
    required Map<String, dynamic> envelope,
    required Uint8List dek,
    required Map<String, dynamic> vaultJson,
  }) async {
    final updated = Map<String, dynamic>.from(envelope);
    updated['vault'] =
        await _seal(utf8.encode(json.encode(vaultJson)), SecretKey(dek));
    return updated;
  }

  /// Replaces (or adds) the recovery slot — used when a kit is rotated.
  static Future<Map<String, dynamic>> replaceRecoverySlot({
    required Map<String, dynamic> envelope,
    required Uint8List dek,
    required SecretKey recoveryKek,
  }) async {
    final updated = Map<String, dynamic>.from(envelope);
    final slots = Map<String, dynamic>.from(updated['slots'] as Map);
    slots['recovery'] = await _seal(dek, recoveryKek);
    updated['slots'] = slots;
    return updated;
  }

  /// Replaces the password slot (password change / restore onto new phone).
  static Future<Map<String, dynamic>> replacePasswordSlot({
    required Map<String, dynamic> envelope,
    required Uint8List dek,
    required String newPassword,
  }) async {
    final updated = Map<String, dynamic>.from(envelope);
    final slots = Map<String, dynamic>.from(updated['slots'] as Map);
    final salt = randomBytes(16);
    final kek = await deriveKekFromPassword(password: newPassword, salt: salt);
    slots['password'] = {
      'salt': base64.encode(salt),
      'm': argonMemoryKiB,
      't': argonIterations,
      'p': argonParallelism,
      ...await _seal(dek, kek),
    };
    updated['slots'] = slots;
    return updated;
  }

  static Future<Uint8List> unwrapDekWithPassword({
    required Map<String, dynamic> envelope,
    required String password,
  }) async {
    final slot = (envelope['slots'] as Map)['password'] as Map<String, dynamic>?;
    if (slot == null) throw StateError('No password slot');
    final kek = await deriveKekFromPassword(
      password: password,
      salt: Uint8List.fromList(base64.decode(slot['salt'] as String)),
      memoryKiB: slot['m'] as int,
      iterations: slot['t'] as int,
      parallelism: slot['p'] as int,
    );
    return _open(slot, kek);
  }

  static Future<Uint8List> unwrapDekWithRecovery({
    required Map<String, dynamic> envelope,
    required SecretKey recoveryKek,
  }) async {
    final slot = (envelope['slots'] as Map)['recovery'] as Map<String, dynamic>?;
    if (slot == null) throw StateError('No recovery slot');
    return _open(slot, recoveryKek);
  }

  static Future<Map<String, dynamic>> openVault({
    required Map<String, dynamic> envelope,
    required Uint8List dek,
  }) async {
    final clear = await _open(
      envelope['vault'] as Map<String, dynamic>,
      SecretKey(dek),
    );
    return json.decode(utf8.decode(clear)) as Map<String, dynamic>;
  }

  /// Seals an already-built envelope for upload: the whole envelope is
  /// encrypted once more with the backup key, so the server learns nothing
  /// from structure or slot metadata.
  static Future<Uint8List> sealBackupBlob({
    required Map<String, dynamic> envelope,
    required SecretKey backupKey,
  }) async {
    final sealed = await _seal(utf8.encode(json.encode(envelope)), backupKey);
    return Uint8List.fromList(utf8.encode(json.encode({'v': 1, ...sealed})));
  }

  static Future<Map<String, dynamic>> openBackupBlob({
    required Uint8List blob,
    required SecretKey backupKey,
  }) async {
    final outer = json.decode(utf8.decode(blob)) as Map<String, dynamic>;
    final clear = await _open(outer, backupKey);
    return json.decode(utf8.decode(clear)) as Map<String, dynamic>;
  }
}
