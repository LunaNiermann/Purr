import 'dart:convert';
import 'dart:typed_data';

import 'otpauth.dart';
import 'totp.dart';

/// Decoder for `otpauth-migration://offline?data=...` — the QR format Google
/// Authenticator uses for "export accounts", and the de-facto interchange
/// format between authenticators. The payload is a protobuf `MigrationPayload`
/// (reverse-engineered; no official schema), decoded here by hand to avoid a
/// protoc toolchain for one small message.
///
/// Field numbers:
///   1 repeated OtpParameters otp_parameters
///   2 int32 version · 3 int32 batch_size · 4 int32 batch_index · 5 int32 batch_id
/// OtpParameters:
///   1 bytes secret (RAW bytes, not base32!) · 2 string name · 3 string issuer
///   4 Algorithm · 5 DigitCount (1=six, 2=eight) · 6 OtpType (1=hotp, 2=totp)
///   7 int64 counter
class MigrationBatch {
  MigrationBatch({
    required this.entries,
    required this.batchSize,
    required this.batchIndex,
    required this.batchId,
  });

  final List<ParsedOtpEntry> entries;
  final int batchSize;
  final int batchIndex;
  final int batchId;
}

MigrationBatch parseMigrationUri(String raw) {
  final uri = Uri.parse(raw.trim());
  if (uri.scheme.toLowerCase() != 'otpauth-migration') {
    throw const FormatException('Not a Google Authenticator export code');
  }
  // Uri.queryParameters already URL-decodes; '+' in base64 survives because
  // queryParameters decodes application/x-www-form-urlencoded ('+' → space),
  // so undo that classic mangling before base64-decoding.
  final data = (uri.queryParameters['data'] ?? '').replaceAll(' ', '+');
  if (data.isEmpty) throw const FormatException('The export code is empty');
  final bytes = base64.decode(base64.normalize(data));
  return _parsePayload(bytes);
}

MigrationBatch _parsePayload(Uint8List bytes) {
  final entries = <ParsedOtpEntry>[];
  var batchSize = 1, batchIndex = 0, batchId = 0;
  final r = _Reader(bytes);
  while (!r.done) {
    final tag = r.varint();
    final field = tag >> 3;
    final wire = tag & 7;
    switch ((field, wire)) {
      case (1, 2):
        entries.add(_parseOtpParameters(r.bytes()));
      case (2, 0):
        r.varint(); // version — ignored
      case (3, 0):
        batchSize = r.varint();
      case (4, 0):
        batchIndex = r.varint();
      case (5, 0):
        batchId = r.varint();
      default:
        r.skip(wire);
    }
  }
  return MigrationBatch(
    entries: entries,
    batchSize: batchSize,
    batchIndex: batchIndex,
    batchId: batchId,
  );
}

ParsedOtpEntry _parseOtpParameters(Uint8List bytes) {
  Uint8List secret = Uint8List(0);
  var name = '', issuer = '';
  var algorithm = TotpAlgorithm.sha1;
  var digits = 6;
  var type = 'totp';
  var counter = 0;
  final r = _Reader(bytes);
  while (!r.done) {
    final tag = r.varint();
    final field = tag >> 3;
    final wire = tag & 7;
    switch ((field, wire)) {
      case (1, 2):
        secret = r.bytes();
      case (2, 2):
        name = utf8.decode(r.bytes(), allowMalformed: true);
      case (3, 2):
        issuer = utf8.decode(r.bytes(), allowMalformed: true);
      case (4, 0):
        algorithm = switch (r.varint()) {
          2 => TotpAlgorithm.sha256,
          3 => TotpAlgorithm.sha512,
          _ => TotpAlgorithm.sha1, // 0 = UNSPECIFIED, 1 = SHA1, 4 = MD5 (unsupported → SHA1)
        };
      case (5, 0):
        digits = r.varint() == 2 ? 8 : 6; // 0 = UNSPECIFIED → six
      case (6, 0):
        type = r.varint() == 1 ? 'hotp' : 'totp';
      case (7, 0):
        counter = r.varint();
      default:
        r.skip(wire);
    }
  }
  if (secret.isEmpty) {
    throw const FormatException('An exported account had no secret');
  }
  // Google puts "Issuer:account" or plain account in name; issuer field wins.
  var account = name;
  final colon = name.indexOf(':');
  if (colon >= 0 && issuer.isNotEmpty &&
      name.substring(0, colon).trim().toLowerCase() == issuer.toLowerCase()) {
    account = name.substring(colon + 1).trim();
  }
  return ParsedOtpEntry(
    secret: secret,
    issuer: issuer,
    accountName: account,
    digits: digits,
    algorithm: algorithm,
    type: type,
    counter: type == 'hotp' ? counter : null,
  );
}

class _Reader {
  _Reader(this._data);
  final Uint8List _data;
  int _pos = 0;

  bool get done => _pos >= _data.length;

  int varint() {
    var result = 0;
    var shift = 0;
    while (true) {
      if (_pos >= _data.length) throw const FormatException('Truncated data');
      final b = _data[_pos++];
      result |= (b & 0x7f) << shift;
      if (b & 0x80 == 0) return result;
      shift += 7;
      if (shift > 63) throw const FormatException('Varint too long');
    }
  }

  Uint8List bytes() {
    final len = varint();
    if (_pos + len > _data.length) throw const FormatException('Truncated data');
    final out = Uint8List.sublistView(_data, _pos, _pos + len);
    _pos += len;
    return out;
  }

  void skip(int wire) {
    switch (wire) {
      case 0:
        varint();
      case 1:
        _pos += 8;
      case 2:
        bytes();
      case 5:
        _pos += 4;
      default:
        throw const FormatException('Unsupported data');
    }
  }
}
