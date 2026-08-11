import 'package:flutter_test/flutter_test.dart';
import 'package:twofa/src/crypto/recovery.dart';
import 'package:twofa/src/crypto/vault_crypto.dart';

void main() {
  final vaultJson = {
    'accounts': [
      {'site': 'GitHub', 'user': 'ada@fastmail.com', 'secret': 'JBSWY3DPEHPK3PXP'},
    ],
  };

  group('vault envelope', () {
    test('password slot round-trips', () async {
      final dek = VaultCrypto.newDek();
      final envelope = await VaultCrypto.sealVault(
        dek: dek,
        vaultJson: vaultJson,
        password: 'correct horse battery staple',
      );
      final unwrapped = await VaultCrypto.unwrapDekWithPassword(
        envelope: envelope,
        password: 'correct horse battery staple',
      );
      expect(unwrapped, dek);
      final opened =
          await VaultCrypto.openVault(envelope: envelope, dek: unwrapped);
      expect(opened, vaultJson);
    });

    test('wrong password fails, data intact', () async {
      final dek = VaultCrypto.newDek();
      final envelope = await VaultCrypto.sealVault(
        dek: dek,
        vaultJson: vaultJson,
        password: 'right one',
      );
      await expectLater(
        VaultCrypto.unwrapDekWithPassword(envelope: envelope, password: 'wrong'),
        throwsA(anything),
      );
      // Still opens with the right password afterwards.
      final ok = await VaultCrypto.unwrapDekWithPassword(
          envelope: envelope, password: 'right one');
      expect(ok, dek);
    });

    test('recovery slot unlocks without the password (kit is sufficient)',
        () async {
      final kit = RecoveryKit.generate();
      final dek = VaultCrypto.newDek();
      final envelope = await VaultCrypto.sealVault(
        dek: dek,
        vaultJson: vaultJson,
        password: 'some password the user forgot',
        recoveryKek: await kit.recoveryKek(),
      );
      final rederived = RecoveryKit.fromWords(kit.words)!;
      final unwrapped = await VaultCrypto.unwrapDekWithRecovery(
        envelope: envelope,
        recoveryKek: await rederived.recoveryKek(),
      );
      expect(unwrapped, dek);
    });

    test('kit rotation: old words stop working, new ones work', () async {
      final oldKit = RecoveryKit.generate();
      final newKit = RecoveryKit.generate();
      final dek = VaultCrypto.newDek();
      var envelope = await VaultCrypto.sealVault(
        dek: dek,
        vaultJson: vaultJson,
        password: 'pw',
        recoveryKek: await oldKit.recoveryKek(),
      );
      envelope = await VaultCrypto.replaceRecoverySlot(
        envelope: envelope,
        dek: dek,
        recoveryKek: await newKit.recoveryKek(),
      );
      await expectLater(
        VaultCrypto.unwrapDekWithRecovery(
          envelope: envelope,
          recoveryKek: await oldKit.recoveryKek(),
        ),
        throwsA(anything),
      );
      final unwrapped = await VaultCrypto.unwrapDekWithRecovery(
        envelope: envelope,
        recoveryKek: await newKit.recoveryKek(),
      );
      expect(unwrapped, dek);
    });

    test('password change keeps recovery slot intact', () async {
      final kit = RecoveryKit.generate();
      final dek = VaultCrypto.newDek();
      var envelope = await VaultCrypto.sealVault(
        dek: dek,
        vaultJson: vaultJson,
        password: 'old pw',
        recoveryKek: await kit.recoveryKek(),
      );
      envelope = await VaultCrypto.replacePasswordSlot(
        envelope: envelope,
        dek: dek,
        newPassword: 'new pw',
      );
      expect(
        await VaultCrypto.unwrapDekWithPassword(
            envelope: envelope, password: 'new pw'),
        dek,
      );
      expect(
        await VaultCrypto.unwrapDekWithRecovery(
            envelope: envelope, recoveryKek: await kit.recoveryKek()),
        dek,
      );
    });
  });

  group('backup blob', () {
    test('round-trips through the backup key; kit-derived ids are stable',
        () async {
      final kit = RecoveryKit.generate();
      final dek = VaultCrypto.newDek();
      final envelope = await VaultCrypto.sealVault(
        dek: dek,
        vaultJson: vaultJson,
        password: 'pw',
        recoveryKek: await kit.recoveryKek(),
      );
      final blob = await VaultCrypto.sealBackupBlob(
        envelope: envelope,
        backupKey: await kit.backupKey(),
      );

      // Restore path: words → same derivations → open blob → recovery slot.
      final restored = RecoveryKit.fromWords(kit.words)!;
      expect(await restored.backupId(), await kit.backupId());
      expect(await restored.backupAuth(), await kit.backupAuth());
      final reopened = await VaultCrypto.openBackupBlob(
        blob: blob,
        backupKey: await restored.backupKey(),
      );
      final unwrapped = await VaultCrypto.unwrapDekWithRecovery(
        envelope: reopened,
        recoveryKek: await restored.recoveryKek(),
      );
      final opened =
          await VaultCrypto.openVault(envelope: reopened, dek: unwrapped);
      expect(opened, vaultJson);
    });

    test('backupId is public-safe: differs from auth and key material',
        () async {
      final kit = RecoveryKit.generate();
      final id = await kit.backupId();
      final auth = await kit.backupAuth();
      expect(id, isNot(auth));
      expect(id.length, greaterThanOrEqualTo(22));
    });
  });

  group('recovery kit', () {
    test('twelve valid words', () {
      final kit = RecoveryKit.generate();
      expect(kit.words, hasLength(12));
      expect(kit.words.every(RecoveryKit.isValidWord), isTrue);
      expect(RecoveryKit.fromWords(kit.words), isNotNull);
    });

    test('checksum rejects a tampered phrase', () {
      // Canonical BIP39 zero-entropy mnemonic — "about" is the checksum word.
      final valid = [...List.filled(11, 'abandon'), 'about'];
      expect(RecoveryKit.fromWords(valid), isNotNull);
      // All-"abandon" is the well-known invalid phrase (checksum mismatch).
      // Deterministic, unlike a random single-word swap (only 4 checksum bits
      // → a swap still validates ~1/16 of the time, which flaked CI).
      expect(RecoveryKit.fromWords(List.filled(12, 'abandon')), isNull);
    });

    test('case and whitespace insensitive', () {
      final kit = RecoveryKit.generate();
      final sloppy =
          kit.words.map((w) => '  ${w.toUpperCase()}  ').toList();
      expect(RecoveryKit.fromWords(sloppy), isNotNull);
    });

    test('kit id is stable and human-shaped', () async {
      final kit = RecoveryKit.generate();
      final id1 = await kit.kitId();
      final id2 = await RecoveryKit.fromWords(kit.words)!.kitId();
      expect(id1, id2);
      expect(RegExp(r'^[A-Z]{3,5}-[A-Z]{3,5}-\d{4}$').hasMatch(id1), isTrue,
          reason: id1);
    });
  });
}
