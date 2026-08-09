import 'dart:typed_data';

import 'package:crypto/crypto.dart';

enum TotpAlgorithm { sha1, sha256, sha512 }

/// RFC 4226 HOTP + RFC 6238 TOTP. Verified against the RFC test vectors
/// (which use different secret lengths per algorithm — see totp_test.dart).
class Totp {
  const Totp({
    required this.secret,
    this.digits = 6,
    this.period = 30,
    this.algorithm = TotpAlgorithm.sha1,
  })  : assert(digits >= 6 && digits <= 8),
        assert(period > 0);

  final Uint8List secret;
  final int digits;
  final int period;
  final TotpAlgorithm algorithm;

  Hash get _hash => switch (algorithm) {
        TotpAlgorithm.sha1 => sha1,
        TotpAlgorithm.sha256 => sha256,
        TotpAlgorithm.sha512 => sha512,
      };

  /// HOTP for an explicit counter.
  String hotp(int counter) {
    final message = ByteData(8)..setUint64(0, counter);
    final digest =
        Hmac(_hash, secret).convert(message.buffer.asUint8List()).bytes;
    final offset = digest.last & 0x0f;
    final binary = ((digest[offset] & 0x7f) << 24) |
        (digest[offset + 1] << 16) |
        (digest[offset + 2] << 8) |
        digest[offset + 3];
    final code = binary % _pow10(digits);
    return code.toString().padLeft(digits, '0');
  }

  int counterFor(DateTime time) =>
      time.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ period;

  /// Code for [time] (defaults to now).
  String codeAt(DateTime time) => hotp(counterFor(time));

  /// The code after the current one — shown so a rollover never invalidates
  /// a half-typed code.
  String nextCodeAt(DateTime time) => hotp(counterFor(time) + 1);

  /// Seconds until the current code expires, in (0, period].
  int secondsRemaining(DateTime time) {
    final seconds = time.toUtc().millisecondsSinceEpoch ~/ 1000;
    return period - (seconds % period);
  }

  static int _pow10(int n) {
    var v = 1;
    for (var i = 0; i < n; i++) {
      v *= 10;
    }
    return v;
  }
}

/// `NNN NNN` for display; clipboard always gets the bare digits.
String formatCodeForDisplay(String code) {
  if (code.length != 6) return code;
  return '${code.substring(0, 3)} ${code.substring(3)}';
}
