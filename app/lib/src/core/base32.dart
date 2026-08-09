import 'dart:typed_data';

/// RFC 4648 base32, tolerant on decode: case-insensitive, ignores spaces and
/// dashes, accepts missing padding. Real-world setup codes arrive lowercase,
/// spaced in groups of four, and unpadded — all must work ("Spaces and
/// capitals don't matter.").
const String _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

final List<int> _reverse = () {
  final table = List<int>.filled(256, -1);
  for (var i = 0; i < _alphabet.length; i++) {
    table[_alphabet.codeUnitAt(i)] = i;
    table[_alphabet.toLowerCase().codeUnitAt(i)] = i;
  }
  return table;
}();

Uint8List base32Decode(String input) {
  final cleaned = input.replaceAll(RegExp(r'[\s\-=]'), '');
  if (cleaned.isEmpty) return Uint8List(0);
  final out = BytesBuilder();
  var buffer = 0;
  var bits = 0;
  for (final unit in cleaned.codeUnits) {
    final value = unit < 256 ? _reverse[unit] : -1;
    if (value < 0) {
      throw FormatException('Not a valid setup code character: '
          '"${String.fromCharCode(unit)}"');
    }
    buffer = (buffer << 5) | value;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.addByte((buffer >> bits) & 0xff);
    }
  }
  return out.toBytes();
}

String base32Encode(List<int> bytes, {bool pad = false}) {
  final sb = StringBuffer();
  var buffer = 0;
  var bits = 0;
  for (final byte in bytes) {
    buffer = (buffer << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      sb.write(_alphabet[(buffer >> bits) & 0x1f]);
    }
  }
  if (bits > 0) sb.write(_alphabet[(buffer << (5 - bits)) & 0x1f]);
  if (pad) {
    while (sb.length % 8 != 0) {
      sb.write('=');
    }
  }
  return sb.toString();
}

/// Whether [input] cleans up to a plausible base32 secret (≥ 10 bytes decoded
/// is the practical floor for real TOTP seeds; RFC 4226 recommends ≥ 16).
bool looksLikeBase32Secret(String input) {
  try {
    return base32Decode(input).length >= 10;
  } on FormatException {
    return false;
  }
}
