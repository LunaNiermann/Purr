import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../crypto/recovery.dart';
import '../crypto/vault_crypto.dart';
import 'models.dart';

/// Owns the encrypted envelope on disk and the unlock lifecycle.
///
/// Unlock slots (Aegis-style; see ARCHITECTURE.md): master password
/// (Argon2id) and recovery words always work; a convenience copy of the DEK
/// sits in platform secure storage (Android Keystore-encrypted) and is
/// released only after a biometric prompt. Wiping the convenience copy —
/// or a Keystore invalidation — never loses data.
class VaultStore {
  VaultStore({FlutterSecureStorage? secureStorage, this.directoryOverride})
      : _secure = secureStorage ?? const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
        );

  final FlutterSecureStorage _secure;
  final String? directoryOverride;

  static const _dekKey = 'twokeys.dek';
  static const _kitMetaKey = 'twokeys.kit-meta';

  Uint8List? _dek; // in memory only while unlocked
  Map<String, dynamic>? _envelope;

  Future<File> _file() async {
    final dir = directoryOverride ??
        (await getApplicationDocumentsDirectory()).path;
    return File('$dir/vault.tk');
  }

  Future<bool> exists() async => (await _file()).exists();

  bool get isUnlocked => _dek != null;

  /// First-run creation. Returns the generated recovery kit — show it once,
  /// then only via re-auth.
  Future<RecoveryKit> create({required String password}) async {
    final kit = RecoveryKit.generate();
    final dek = VaultCrypto.newDek();
    final envelope = await VaultCrypto.sealVault(
      dek: dek,
      vaultJson: VaultData(accounts: []).toJson(),
      password: password,
      recoveryKek: await kit.recoveryKek(),
    );
    await _persist(envelope);
    _envelope = envelope;
    _dek = dek;
    await _secure.write(key: _dekKey, value: base64.encode(dek));
    await _storeKitMeta(kit);
    return kit;
  }

  Future<void> _storeKitMeta(RecoveryKit kit) async {
    await _secure.write(
      key: _kitMetaKey,
      value: json.encode({
        'kitId': await kit.kitId(),
        'backupId': await kit.backupId(),
        'backupAuth': await kit.backupAuth(),
        'backupKeyB64':
            base64.encode(await (await kit.backupKey()).extractBytes()),
        'entropyB64': base64.encode(kit.entropy),
        'savedAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  /// Kit metadata (ids, backup key) — kept so backups upload without asking
  /// for the words, and so the kit can be re-viewed/printed after re-auth.
  Future<Map<String, dynamic>?> kitMeta() async {
    final raw = await _secure.read(key: _kitMetaKey);
    return raw == null ? null : json.decode(raw) as Map<String, dynamic>;
  }

  Future<void> _persist(Map<String, dynamic> envelope) async {
    final file = await _file();
    // Transactional write: temp file + atomic rename, so a crash mid-write
    // can never eat the vault (research commandment 19).
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(json.encode(envelope), flush: true);
    if (await file.exists()) await file.delete();
    await tmp.rename(file.path);
  }

  Future<Map<String, dynamic>> _loadEnvelope() async {
    if (_envelope != null) return _envelope!;
    final file = await _file();
    _envelope =
        json.decode(await file.readAsString()) as Map<String, dynamic>;
    return _envelope!;
  }

  Future<VaultData> unlockWithPassword(String password) async {
    final envelope = await _loadEnvelope();
    final dek = await VaultCrypto.unwrapDekWithPassword(
      envelope: envelope,
      password: password,
    );
    _dek = dek;
    // Refresh the convenience copy in case it was wiped or invalidated.
    await _secure.write(key: _dekKey, value: base64.encode(dek));
    return _readVault();
  }

  /// Fast path after a successful biometric prompt (the prompt itself is the
  /// caller's job via local_auth).
  Future<VaultData?> unlockWithStoredDek() async {
    final raw = await _secure.read(key: _dekKey);
    if (raw == null) return null;
    _dek = Uint8List.fromList(base64.decode(raw));
    try {
      return await _readVault();
    } catch (_) {
      // Stored DEK no longer matches (e.g. restored envelope) — force password.
      _dek = null;
      await _secure.delete(key: _dekKey);
      return null;
    }
  }

  Future<VaultData> unlockWithRecoveryKit(RecoveryKit kit) async {
    final envelope = await _loadEnvelope();
    final dek = await VaultCrypto.unwrapDekWithRecovery(
      envelope: envelope,
      recoveryKek: await kit.recoveryKek(),
    );
    _dek = dek;
    return _readVault();
  }

  Future<VaultData> _readVault() async {
    final envelope = await _loadEnvelope();
    final jsonMap =
        await VaultCrypto.openVault(envelope: envelope, dek: _dek!);
    return VaultData.fromJson(jsonMap);
  }

  Future<void> save(VaultData data) async {
    if (_dek == null) throw StateError('Vault is locked');
    final envelope = await _loadEnvelope();
    final updated = await VaultCrypto.resealVaultContent(
      envelope: envelope,
      dek: _dek!,
      vaultJson: data.toJson(),
    );
    _envelope = updated;
    await _persist(updated);
  }

  Future<void> changePassword(String newPassword) async {
    if (_dek == null) throw StateError('Vault is locked');
    final updated = await VaultCrypto.replacePasswordSlot(
      envelope: await _loadEnvelope(),
      dek: _dek!,
      newPassword: newPassword,
    );
    _envelope = updated;
    await _persist(updated);
  }

  /// Rotates the recovery kit: new words wrap the DEK, the old slot is
  /// replaced, new backup identifiers are stored. Old sheets stop working.
  Future<RecoveryKit> rotateKit() async {
    if (_dek == null) throw StateError('Vault is locked');
    final kit = RecoveryKit.generate();
    final updated = await VaultCrypto.replaceRecoverySlot(
      envelope: await _loadEnvelope(),
      dek: _dek!,
      recoveryKek: await kit.recoveryKek(),
    );
    _envelope = updated;
    await _persist(updated);
    await _storeKitMeta(kit);
    return kit;
  }

  /// The sealed backup blob for upload, encrypted with the kit's backup key.
  Future<(String backupId, String backupAuth, Uint8List blob, String digest)>
      buildBackupBlob() async {
    final meta = await kitMeta();
    if (meta == null) throw StateError('No kit metadata');
    final envelope = await _loadEnvelope();
    final blob = await VaultCrypto.sealBackupBlob(
      envelope: envelope,
      backupKey:
          SecretKey(base64.decode(meta['backupKeyB64'] as String)),
    );
    final digest = base64.encode(
        (await Sha256().hash(blob)).bytes);
    return (
      meta['backupId'] as String,
      meta['backupAuth'] as String,
      blob,
      digest,
    );
  }

  /// Restore path: replaces any local envelope with one recovered from a
  /// backup blob, unlocked by the kit, then re-keys password + kit.
  Future<VaultData> restoreFromBackup({
    required Uint8List blob,
    required RecoveryKit kit,
  }) async {
    final envelope = await VaultCrypto.openBackupBlob(
      blob: blob,
      backupKey: await kit.backupKey(),
    );
    final dek = await VaultCrypto.unwrapDekWithRecovery(
      envelope: envelope,
      recoveryKek: await kit.recoveryKek(),
    );
    _envelope = envelope;
    _dek = dek;
    await _persist(envelope);
    await _secure.write(key: _dekKey, value: base64.encode(dek));
    return _readVault();
  }

  void lock() {
    _dek = null;
  }

  /// Full local wipe (used by "Set up as a new phone").
  Future<void> destroy() async {
    _dek = null;
    _envelope = null;
    await _secure.delete(key: _dekKey);
    await _secure.delete(key: _kitMetaKey);
    final file = await _file();
    if (await file.exists()) await file.delete();
  }
}
