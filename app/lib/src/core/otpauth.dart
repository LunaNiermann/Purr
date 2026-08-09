import 'dart:typed_data';

import 'base32.dart';
import 'totp.dart';

/// A parsed otpauth:// entry, before it becomes a saved account.
class ParsedOtpEntry {
  ParsedOtpEntry({
    required this.secret,
    required this.issuer,
    required this.accountName,
    this.digits = 6,
    this.period = 30,
    this.algorithm = TotpAlgorithm.sha1,
    this.type = 'totp',
    this.counter,
  });

  final Uint8List secret;
  final String issuer;
  final String accountName;
  final int digits;
  final int period;
  final TotpAlgorithm algorithm;
  final String type; // totp | hotp
  final int? counter;
}

/// Parses `otpauth://totp/...` per the de-facto Key URI format, tolerantly:
/// - secret: unpadded/lowercase/spaced base32 all accepted
/// - issuer: query param wins over label prefix; never duplicated into the name
/// - missing params fall back to SHA1 / 6 digits / 30 s
/// - unknown algorithm values fall back to SHA1 rather than rejecting
///
/// Throws [FormatException] with a human-readable message when unusable.
ParsedOtpEntry parseOtpauthUri(String raw) {
  final uri = Uri.parse(raw.trim());
  if (uri.scheme.toLowerCase() != 'otpauth') {
    throw const FormatException('Not a setup code link');
  }
  final type = uri.host.toLowerCase();
  if (type != 'totp' && type != 'hotp') {
    throw const FormatException('Unsupported code type');
  }

  final params = <String, String>{
    for (final e in uri.queryParameters.entries) e.key.toLowerCase(): e.value,
  };

  final secretParam = params['secret'];
  if (secretParam == null || secretParam.isEmpty) {
    throw const FormatException('The link is missing its secret');
  }
  final secret = base32Decode(secretParam);
  if (secret.isEmpty) throw const FormatException('The secret is empty');

  // Label: "Issuer:account" or just "account", URL-encoded.
  var label = uri.path;
  if (label.startsWith('/')) label = label.substring(1);
  label = Uri.decodeComponent(label).trim();
  String labelIssuer = '';
  String account = label;
  final colon = label.indexOf(':');
  if (colon >= 0) {
    labelIssuer = label.substring(0, colon).trim();
    account = label.substring(colon + 1).trim();
  }

  var issuer = (params['issuer'] ?? '').trim();
  if (issuer.isEmpty) issuer = labelIssuer;
  // Don't render "GitHub: GitHub".
  if (issuer.isNotEmpty && account.toLowerCase() == issuer.toLowerCase()) {
    account = '';
  }

  final algorithm = switch ((params['algorithm'] ?? 'SHA1').toUpperCase()) {
    'SHA256' => TotpAlgorithm.sha256,
    'SHA512' => TotpAlgorithm.sha512,
    _ => TotpAlgorithm.sha1,
  };

  final digits = int.tryParse(params['digits'] ?? '') ?? 6;
  final period = int.tryParse(params['period'] ?? '') ?? 30;

  return ParsedOtpEntry(
    secret: secret,
    issuer: issuer,
    accountName: account,
    digits: digits.clamp(6, 8),
    period: period < 5 ? 30 : period,
    algorithm: algorithm,
    type: type,
    counter: type == 'hotp' ? int.tryParse(params['counter'] ?? '0') ?? 0 : null,
  );
}

/// Builds a canonical otpauth:// URI — the export format (exit rights are
/// non-negotiable; see docs/RESEARCH-complaints.md commandment 1).
String buildOtpauthUri(ParsedOtpEntry e) {
  final label = e.issuer.isEmpty
      ? e.accountName
      : '${e.issuer}:${e.accountName.isEmpty ? e.issuer : e.accountName}';
  final params = <String, String>{
    'secret': base32Encode(e.secret),
    if (e.issuer.isNotEmpty) 'issuer': e.issuer,
    if (e.algorithm != TotpAlgorithm.sha1)
      'algorithm': e.algorithm.name.toUpperCase(),
    if (e.digits != 6) 'digits': '${e.digits}',
    if (e.period != 30) 'period': '${e.period}',
    if (e.type == 'hotp') 'counter': '${e.counter ?? 0}',
  };
  return Uri(
    scheme: 'otpauth',
    host: e.type,
    path: '/$label',
    queryParameters: params,
  ).toString();
}
