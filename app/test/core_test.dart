import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:twofa/src/core/base32.dart';
import 'package:twofa/src/core/migration.dart';
import 'package:twofa/src/core/otpauth.dart';
import 'package:twofa/src/core/totp.dart';

Uint8List ascii(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('base32', () {
    test('round-trips', () {
      final bytes = Uint8List.fromList(List.generate(20, (i) => i * 7 % 256));
      expect(base32Decode(base32Encode(bytes)), bytes);
    });

    test('tolerates lowercase, spaces, dashes, missing padding', () {
      final canonical = base32Decode('JBSWY3DPEHPK3PXP');
      expect(base32Decode('jbsw y3dp ehpk 3pxp'), canonical);
      expect(base32Decode('JBSW-Y3DP-EHPK-3PXP'), canonical);
      expect(base32Decode('JBSWY3DPEHPK3PXP===='), canonical);
    });

    test('rejects junk with a readable message', () {
      expect(() => base32Decode('hello!world'), throwsFormatException);
    });
  });

  group('HOTP (RFC 4226 vectors)', () {
    final totp = Totp(secret: ascii('12345678901234567890'));
    const expected = [
      '755224', '287082', '359152', '969429', '338314',
      '254676', '287922', '162583', '399871', '520489',
    ];
    for (var i = 0; i < expected.length; i++) {
      test('counter $i', () => expect(totp.hotp(i), expected[i]));
    }
  });

  group('TOTP (RFC 6238 vectors, 8 digits)', () {
    // Note: per-algorithm secrets have different lengths — a classic
    // implementation trap (see docs/RESEARCH-technical.md §1).
    final sha1 = Totp(
        secret: ascii('12345678901234567890'),
        digits: 8);
    final sha256 = Totp(
        secret: ascii('12345678901234567890123456789012'),
        digits: 8,
        algorithm: TotpAlgorithm.sha256);
    final sha512 = Totp(
        secret: ascii(
            '1234567890123456789012345678901234567890123456789012345678901234'),
        digits: 8,
        algorithm: TotpAlgorithm.sha512);

    const cases = <(int, String, String, String)>[
      (59, '94287082', '46119246', '90693936'),
      (1111111109, '07081804', '68084774', '25091201'),
      (1111111111, '14050471', '67062674', '99943326'),
      (1234567890, '89005924', '91819424', '93441116'),
      (2000000000, '69279037', '90698825', '38618901'),
      (20000000000, '65353130', '77737706', '47863826'),
    ];

    for (final (t, e1, e256, e512) in cases) {
      final time = DateTime.fromMillisecondsSinceEpoch(t * 1000, isUtc: true);
      test('T=$t', () {
        expect(sha1.codeAt(time), e1);
        expect(sha256.codeAt(time), e256);
        expect(sha512.codeAt(time), e512);
      });
    }

    test('leading zeros survive', () {
      final time =
          DateTime.fromMillisecondsSinceEpoch(1111111109 * 1000, isUtc: true);
      expect(sha1.codeAt(time), startsWith('0'));
    });

    test('secondsRemaining is in (0, 30]', () {
      final t0 = DateTime.fromMillisecondsSinceEpoch(60 * 1000, isUtc: true);
      expect(sha1.secondsRemaining(t0), 30);
      final t29 = DateTime.fromMillisecondsSinceEpoch(89 * 1000, isUtc: true);
      expect(sha1.secondsRemaining(t29), 1);
    });

    test('next code differs and matches the following window', () {
      final time = DateTime.fromMillisecondsSinceEpoch(59 * 1000, isUtc: true);
      final next = DateTime.fromMillisecondsSinceEpoch(61 * 1000, isUtc: true);
      expect(sha1.nextCodeAt(time), sha1.codeAt(next));
    });
  });

  group('otpauth:// parsing', () {
    test('typical GitHub-style URI', () {
      final e = parseOtpauthUri(
          'otpauth://totp/GitHub:ada%40fastmail.com?secret=JBSWY3DPEHPK3PXP&issuer=GitHub');
      expect(e.issuer, 'GitHub');
      expect(e.accountName, 'ada@fastmail.com');
      expect(e.digits, 6);
      expect(e.period, 30);
      expect(e.algorithm, TotpAlgorithm.sha1);
    });

    test('issuer param wins over label prefix; no duplication', () {
      final e = parseOtpauthUri(
          'otpauth://totp/OldName:me?secret=JBSWY3DPEHPK3PXP&issuer=NewName');
      expect(e.issuer, 'NewName');
      expect(e.accountName, 'me');
    });

    test('label-only issuer is used as fallback', () {
      final e =
          parseOtpauthUri('otpauth://totp/Figma:ada?secret=JBSWY3DPEHPK3PXP');
      expect(e.issuer, 'Figma');
    });

    test('lowercase unpadded secret with spaces', () {
      final e = parseOtpauthUri(
          'otpauth://totp/X:y?secret=jbsw%20y3dp%20ehpk%203pxp');
      expect(e.secret, base32Decode('JBSWY3DPEHPK3PXP'));
    });

    test('SHA256 / 8 digits / 60s period honored', () {
      final e = parseOtpauthUri(
          'otpauth://totp/A:b?secret=JBSWY3DPEHPK3PXP&algorithm=SHA256&digits=8&period=60');
      expect(e.algorithm, TotpAlgorithm.sha256);
      expect(e.digits, 8);
      expect(e.period, 60);
    });

    test('unknown algorithm falls back to SHA1 instead of failing', () {
      final e = parseOtpauthUri(
          'otpauth://totp/A:b?secret=JBSWY3DPEHPK3PXP&algorithm=MD5');
      expect(e.algorithm, TotpAlgorithm.sha1);
    });

    test('hotp with counter', () {
      final e = parseOtpauthUri(
          'otpauth://hotp/A:b?secret=JBSWY3DPEHPK3PXP&counter=42');
      expect(e.type, 'hotp');
      expect(e.counter, 42);
    });

    test('missing secret is a readable error', () {
      expect(() => parseOtpauthUri('otpauth://totp/A:b?issuer=A'),
          throwsFormatException);
    });

    test('export round-trip preserves everything', () {
      final original = parseOtpauthUri(
          'otpauth://totp/GitHub:ada?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&algorithm=SHA512&digits=8&period=60');
      final rebuilt = parseOtpauthUri(buildOtpauthUri(original));
      expect(rebuilt.secret, original.secret);
      expect(rebuilt.issuer, original.issuer);
      expect(rebuilt.accountName, original.accountName);
      expect(rebuilt.algorithm, original.algorithm);
      expect(rebuilt.digits, original.digits);
      expect(rebuilt.period, original.period);
    });
  });

  group('otpauth-migration:// import', () {
    // Hand-built MigrationPayload with two entries:
    //   1) secret "12345678901234567890", name "GitHub:ada", issuer "GitHub",
    //      SHA1, six digits, TOTP
    //   2) secret bytes 0..15, name "solo", no issuer, defaults (UNSPECIFIED)
    // plus version=1, batch_size=1, batch_index=0, batch_id=7.
    Uint8List lenDelim(int field, List<int> content) =>
        Uint8List.fromList([(field << 3) | 2, content.length, ...content]);

    final entry1 = <int>[
      ...lenDelim(1, utf8.encode('12345678901234567890')),
      ...lenDelim(2, utf8.encode('GitHub:ada')),
      ...lenDelim(3, utf8.encode('GitHub')),
      (4 << 3), 1, // algorithm SHA1
      (5 << 3), 1, // digits six
      (6 << 3), 2, // type totp
    ];
    final entry2 = <int>[
      ...lenDelim(1, List.generate(16, (i) => i)),
      ...lenDelim(2, utf8.encode('solo')),
      (4 << 3), 0, // UNSPECIFIED
      (5 << 3), 0,
      (6 << 3), 0,
    ];
    final payload = Uint8List.fromList([
      ...lenDelim(1, entry1),
      ...lenDelim(1, entry2),
      (2 << 3), 1,
      (3 << 3), 1,
      (4 << 3), 0,
      (5 << 3), 7,
    ]);

    test('parses both entries with correct defaults', () {
      final uri =
          'otpauth-migration://offline?data=${Uri.encodeComponent(base64.encode(payload))}';
      final batch = parseMigrationUri(uri);
      expect(batch.entries, hasLength(2));
      expect(batch.batchId, 7);
      expect(batch.batchSize, 1);

      final first = batch.entries[0];
      expect(first.issuer, 'GitHub');
      expect(first.accountName, 'ada');
      expect(first.secret, ascii('12345678901234567890'));
      // Raw-bytes secret: generating a code must match the RFC vector secret.
      final t = Totp(secret: first.secret);
      expect(t.hotp(0), '755224');

      final second = batch.entries[1];
      expect(second.issuer, '');
      expect(second.accountName, 'solo');
      expect(second.digits, 6);
      expect(second.algorithm, TotpAlgorithm.sha1);
      expect(second.type, 'totp');
    });

    test("survives '+' mangled to space in the data param", () {
      // Find a payload variant whose base64 contains '+': tweak batch_id,
      // encoded as a proper varint.
      List<int> varint(int v) {
        final out = <int>[];
        while (v >= 0x80) {
          out.add((v & 0x7f) | 0x80);
          v >>= 7;
        }
        out.add(v);
        return out;
      }

      String? mangled;
      for (var id = 0; id < 4096 && mangled == null; id++) {
        final p = Uint8List.fromList([
          ...lenDelim(1, entry1),
          (5 << 3), ...varint(id),
        ]);
        final b64 = base64.encode(p);
        if (b64.contains('+')) mangled = b64.replaceAll('+', ' ');
      }
      expect(mangled, isNotNull, reason: 'no + found in any candidate payload');
      final batch =
          parseMigrationUri('otpauth-migration://offline?data=$mangled');
      expect(batch.entries, hasLength(1));
    });

    test('rejects non-migration URIs', () {
      expect(() => parseMigrationUri('otpauth://totp/x?secret=ABC'),
          throwsFormatException);
    });
  });

  group('display formatting', () {
    test('NNN NNN with a single space', () {
      expect(formatCodeForDisplay('418902'), '418 902');
      expect(formatCodeForDisplay('12345678'), '12345678');
    });
  });
}
