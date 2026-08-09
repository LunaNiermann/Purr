import 'dart:typed_data';

import '../core/base32.dart';
import '../core/otpauth.dart';
import '../core/totp.dart';

/// A saved account. Secrets live only inside the encrypted vault JSON; this
/// object exists in memory while the vault is unlocked.
class Account {
  Account({
    required this.id,
    required this.siteName,
    required this.username,
    required this.secretB32,
    this.digits = 6,
    this.period = 30,
    this.algorithm = TotpAlgorithm.sha1,
    this.type = 'totp',
    this.counter,
    this.pinned = false,
    required this.createdAt,
  });

  final String id;
  final String siteName;
  final String username;
  final String secretB32;
  final int digits;
  final int period;
  final TotpAlgorithm algorithm;
  final String type;
  final int? counter;
  final bool pinned;
  final DateTime createdAt;

  Uint8List get secret => base32Decode(secretB32);

  Totp get totp => Totp(
        secret: secret,
        digits: digits,
        period: period,
        algorithm: algorithm,
      );

  Account copyWith({
    String? siteName,
    String? username,
    bool? pinned,
    int? counter,
  }) =>
      Account(
        id: id,
        siteName: siteName ?? this.siteName,
        username: username ?? this.username,
        secretB32: secretB32,
        digits: digits,
        period: period,
        algorithm: algorithm,
        type: type,
        counter: counter ?? this.counter,
        pinned: pinned ?? this.pinned,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'site': siteName,
        'user': username,
        'secret': secretB32,
        'digits': digits,
        'period': period,
        'algorithm': algorithm.name,
        'type': type,
        if (counter != null) 'counter': counter,
        if (pinned) 'pinned': true,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  static Account fromJson(Map<String, dynamic> json) => Account(
        id: json['id'] as String,
        siteName: json['site'] as String,
        username: json['user'] as String? ?? '',
        secretB32: json['secret'] as String,
        digits: json['digits'] as int? ?? 6,
        period: json['period'] as int? ?? 30,
        algorithm: TotpAlgorithm.values.firstWhere(
          (a) => a.name == (json['algorithm'] as String? ?? 'sha1'),
          orElse: () => TotpAlgorithm.sha1,
        ),
        type: json['type'] as String? ?? 'totp',
        counter: json['counter'] as int?,
        pinned: json['pinned'] as bool? ?? false,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now().toUtc(),
      );

  static Account fromParsed(ParsedOtpEntry e, {required String id}) => Account(
        id: id,
        siteName: e.issuer.isNotEmpty ? e.issuer : e.accountName,
        username: e.issuer.isNotEmpty ? e.accountName : '',
        secretB32: base32Encode(e.secret),
        digits: e.digits,
        period: e.period,
        algorithm: e.algorithm,
        type: e.type,
        counter: e.counter,
        createdAt: DateTime.now().toUtc(),
      );
}

/// The decrypted vault content (the JSON inside the envelope).
class VaultData {
  VaultData({required this.accounts, Map<String, String>? mutedSites})
      : mutedSites = mutedSites ?? {};

  final List<Account> accounts;

  /// site → local calendar date (yyyy-mm-dd) for "Mute requests for this
  /// site today" — today resets at local midnight, not a rolling 24 h.
  final Map<String, String> mutedSites;

  Map<String, dynamic> toJson() => {
        'accounts': accounts.map((a) => a.toJson()).toList(),
        if (mutedSites.isNotEmpty) 'muted': mutedSites,
      };

  static VaultData fromJson(Map<String, dynamic> json) => VaultData(
        accounts: [
          for (final a in (json['accounts'] as List? ?? []))
            Account.fromJson(a as Map<String, dynamic>),
        ],
        mutedSites: {
          for (final e in ((json['muted'] as Map?) ?? {}).entries)
            e.key as String: e.value as String,
        },
      );

  bool isMutedToday(String site) {
    final today = DateTime.now();
    final key =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    return mutedSites[site.toLowerCase()] == key;
  }
}
