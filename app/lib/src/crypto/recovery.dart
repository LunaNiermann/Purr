import 'dart:convert' show base64, base64UrlEncode, utf8;
import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
// ignore: implementation_imports — the package doesn't export its wordlist
import 'package:bip39/src/wordlists/english.dart' as bip39_words;
import 'package:cryptography/cryptography.dart';

/// Everything a printed kit can do derives from 128 bits of entropy behind
/// twelve BIP39 words. Distinct HKDF info strings keep the derived keys
/// independent:
///
///   entropy ─HKDF("recovery-kek")─▶ wraps the DEK (a slot in the envelope)
///   entropy ─HKDF("backup-key")──▶ encrypts the uploaded backup blob
///   entropy ─HKDF("backup-id")───▶ public locator for the blob
///   entropy ─HKDF("backup-auth")─▶ proof-of-knowledge bearer for the store
///
/// The server sees only the last two — and can invert neither.
class RecoveryKit {
  RecoveryKit._(this.entropy, this.words);

  final Uint8List entropy;
  final List<String> words;

  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  static RecoveryKit generate() {
    final mnemonic = bip39.generateMnemonic(strength: 128);
    return RecoveryKit._(
      Uint8List.fromList(_hexToBytes(bip39.mnemonicToEntropy(mnemonic))),
      mnemonic.split(' '),
    );
  }

  /// Accepts user-typed words: case/whitespace-insensitive, checksum-checked.
  static RecoveryKit? fromWords(List<String> raw) {
    final mnemonic =
        raw.map((w) => w.trim().toLowerCase()).where((w) => w.isNotEmpty).join(' ');
    if (!bip39.validateMnemonic(mnemonic)) return null;
    return RecoveryKit._(
      Uint8List.fromList(_hexToBytes(bip39.mnemonicToEntropy(mnemonic))),
      mnemonic.split(' '),
    );
  }

  /// Rebuilds a kit from stored entropy (secure storage) for re-printing.
  static RecoveryKit fromEntropyB64(String entropyB64) {
    final entropy = Uint8List.fromList(base64.decode(entropyB64));
    final hex = entropy
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    final mnemonic = bip39.entropyToMnemonic(hex);
    return RecoveryKit._(entropy, mnemonic.split(' '));
  }

  /// True if [word] is in the BIP39 wordlist — used for per-word field
  /// validation while typing (beat 3b of the lost-phone storyboard).
  static bool isValidWord(String word) =>
      bip39_words.WORDLIST.contains(word.trim().toLowerCase());

  Future<SecretKey> _derive(String info) => _hkdf.deriveKey(
        secretKey: SecretKey(entropy),
        // Fixed salt: entropy is already full-strength random; the constant
        // just satisfies HKDF's structure and must never change (v1).
        nonce: utf8.encode('twokeys-hkdf-v1'),
        info: utf8.encode('twokeys/$info'),
      );

  Future<SecretKey> recoveryKek() => _derive('recovery-kek');
  Future<SecretKey> backupKey() => _derive('backup-key');

  Future<String> backupId() async {
    final key = await _derive('backup-id');
    return base64UrlEncode(await key.extractBytes())
        .replaceAll('=', '')
        .substring(0, 43);
  }

  Future<String> backupAuth() async {
    final key = await _derive('backup-auth');
    return base64UrlEncode(await key.extractBytes()).replaceAll('=', '');
  }

  /// Kit ID for the printed sheet: human-readable, NOT secret (it identifies
  /// the sheet, revealing nothing about the words). MOSS-TIDE-9417 style.
  Future<String> kitId() async {
    final key = await _derive('kit-id');
    final bytes = await key.extractBytes();
    const consonantWords = [
      'MOSS', 'TIDE', 'FERN', 'LARK', 'REED', 'WREN', 'CLAY', 'DUSK',
      'GLEN', 'HAWK', 'IRIS', 'KELP', 'LOAM', 'MIST', 'OWL', 'PINE',
      'QUAY', 'ROOK', 'SAGE', 'THAW', 'VALE', 'WOLF', 'YARN', 'ZEST',
      'BIRCH', 'CEDAR', 'DELL', 'EMBER', 'FROST', 'GROVE', 'HEATH', 'ISLE',
    ];
    final w1 = consonantWords[bytes[0] % consonantWords.length];
    final w2 = consonantWords[bytes[1] % consonantWords.length];
    final digits = ((bytes[2] << 8) | bytes[3]) % 10000;
    return '$w1-$w2-${digits.toString().padLeft(4, '0')}';
  }

  static List<int> _hexToBytes(String hex) => [
        for (var i = 0; i < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ];
}
