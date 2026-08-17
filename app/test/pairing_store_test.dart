import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:twofa/src/services/pairing_service.dart';

/// In-memory stand-in for secure storage, so the migration can be driven
/// without the platform plugin.
class _MemStorage implements PairingStorage {
  _MemStorage([Map<String, String>? initial]) : map = {...?initial};

  final Map<String, String> map;

  @override
  Future<String?> read(String key) async => map[key];

  @override
  Future<void> write(String key, String value) async {
    map[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    map.remove(key);
  }
}

const _legacyKey = 'twokeys.pairing';
const _listKey = 'twokeys.pairings';
const _sessionKey = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';

String _legacyBlob() => json.encode({
      'pairingId': 'p1',
      'phoneToken': 'tok1',
      'sessionKeyB64': _sessionKey,
      'relayUrl': 'https://relay.example',
      'pairedAt': '2026-01-02T03:04:05.000Z',
    });

StoredPairing _pairing(String id) => StoredPairing(
      pairingId: id,
      phoneToken: 'tok-$id',
      sessionKeyB64: _sessionKey,
      relayUrl: 'https://relay.example',
      pairedAt: DateTime.utc(2026, 1, 1),
      browserName: 'Chrome · Mac',
    );

void main() {
  group('legacy migration', () {
    test('folds a pre-multi-browser pairing into the list', () async {
      final storage = _MemStorage({_legacyKey: _legacyBlob()});
      final all = await PairingService(storage: storage).all();

      expect(all, hasLength(1));
      expect(all.single.pairingId, 'p1');
      expect(all.single.phoneToken, 'tok1');
      // A pairing made before names were exchanged has none, and must not be
      // dropped for the lack of one.
      expect(all.single.browserName, isNull);
    });

    test('retires the old key only after the list is written', () async {
      final storage = _MemStorage({_legacyKey: _legacyBlob()});
      await PairingService(storage: storage).all();

      expect(storage.map.containsKey(_listKey), isTrue);
      expect(storage.map.containsKey(_legacyKey), isFalse);
    });

    test('is idempotent — a second read comes from the list', () async {
      final storage = _MemStorage({_legacyKey: _legacyBlob()});
      final service = PairingService(storage: storage);

      expect(await service.all(), hasLength(1));
      expect(await service.all(), hasLength(1));
      expect((await service.all()).single.pairingId, 'p1');
    });

    test('an existing list wins over a stale legacy key', () async {
      // Belt and braces: if both keys somehow exist, the list is the truth and
      // the legacy single pairing must not silently replace it.
      final storage = _MemStorage({
        _legacyKey: _legacyBlob(),
        _listKey: json.encode([_pairing('p2').toJson()]),
      });

      final all = await PairingService(storage: storage).all();
      expect(all.map((p) => p.pairingId), ['p2']);
    });

    test('a fresh install has no pairings', () async {
      expect(await PairingService(storage: _MemStorage()).all(), isEmpty);
    });
  });

  group('multiple browsers', () {
    test('round-trips every field, in order', () async {
      final storage = _MemStorage({
        _listKey: json.encode(
            [_pairing('a').toJson(), _pairing('b').toJson()]),
      });

      final all = await PairingService(storage: storage).all();
      expect(all.map((p) => p.pairingId), ['a', 'b']);
      expect(all.first.browserName, 'Chrome · Mac');
      expect(all.first.phoneToken, 'tok-a');
      expect(all.first.relayUrl, 'https://relay.example');
      expect(all.first.pairedAt, DateTime.utc(2026, 1, 1));
    });

    test('byId finds one and returns null for a stranger', () async {
      final storage = _MemStorage({
        _listKey: json.encode(
            [_pairing('a').toJson(), _pairing('b').toJson()]),
      });
      final service = PairingService(storage: storage);

      expect((await service.byId('b'))!.phoneToken, 'tok-b');
      expect(await service.byId('nope'), isNull);
    });

    test('unpairing one browser leaves the others paired', () async {
      final storage = _MemStorage({
        _listKey: json.encode([
          _pairing('a').toJson(),
          _pairing('b').toJson(),
          _pairing('c').toJson(),
        ]),
      });
      final service = PairingService(storage: storage);

      // The relay call is best-effort; in tests it fails and is swallowed,
      // which is exactly the offline-unpair path.
      await service.unpair('b');

      expect((await service.all()).map((p) => p.pairingId), ['a', 'c']);
    });

    test('unpairing the last browser empties the list', () async {
      final storage = _MemStorage({
        _listKey: json.encode([_pairing('a').toJson()]),
      });
      final service = PairingService(storage: storage);

      await service.unpair('a');
      expect(await service.all(), isEmpty);
    });
  });
}
