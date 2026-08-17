import 'dart:convert';
import 'dart:typed_data';

import '../data/models.dart';
import 'pairing_crypto.dart';
import 'pairing_service.dart';
import 'relay_api.dart';

/// Keeps the desktop "touch your key" route's encrypted vault replica current.
///
/// The extension publishes a random replica master key `K`, sealed to us with
/// the pairing session key. We open it, then push the vault — encrypted under
/// `K` — whenever it changes. We never see the security key or its PRF output,
/// only `K`; the relay sees only ciphertext.
///
/// Cross-language contract:
///   replica-key blob = seal(sessionKey, { "k": base64(K) })
///   replica blob     = seal(K, { "v": 1, "accounts": [ { site, user, secret,
///                        digits, period, algorithm, type, counter? } ] })
/// where seal/open are the shared XChaCha20-Poly1305 format (nonce‖ct‖mac).
class ReplicaService {
  const ReplicaService();

  Map<String, dynamic> _payload(List<Account> accounts) => {
        'v': 1,
        'accounts': [
          for (final a in accounts)
            {
              'site': a.siteName,
              'user': a.username,
              'secret': a.secretB32,
              'digits': a.digits,
              'period': a.period,
              'algorithm': a.algorithm.name,
              'type': a.type,
              if (a.counter != null) 'counter': a.counter,
            },
        ],
      };

  /// Sync using whatever pairing is stored. No-op when unpaired or when the key
  /// route hasn't been enrolled. Safe to call fire-and-forget on every change.
  Future<void> syncFromAccounts(List<Account> accounts) async {
    // Each browser keeps its own replica under its own key, so every pairing
    // that has enrolled the key route needs its own push.
    for (final pairing in await PairingService().all()) {
      await sync(pairing, accounts);
    }
  }

  Future<void> sync(StoredPairing pairing, List<Account> accounts) async {
    final api = RelayApi(baseUrl: pairing.relayUrl);

    // The extension seals K for us; absent → key route not enrolled → nothing.
    final String? keyBlob;
    try {
      keyBlob = await api.getReplicaKey(
        pairingId: pairing.pairingId,
        phoneToken: pairing.phoneToken,
      );
    } catch (_) {
      return;
    }
    if (keyBlob == null) return;

    final Uint8List k;
    try {
      final opened = await PairingCrypto.open(pairing.sessionKey, keyBlob);
      final kB64 = opened['k'] as String?;
      if (kB64 == null) return;
      k = Uint8List.fromList(base64.decode(kB64));
    } catch (_) {
      // Session-key mismatch or malformed — nothing we can do.
      return;
    }

    final replicaBlob = await PairingCrypto.seal(k, _payload(accounts));
    try {
      await api.putReplica(
        pairingId: pairing.pairingId,
        phoneToken: pairing.phoneToken,
        replicaBlobB64: replicaBlob,
      );
    } catch (_) {
      // Transient — the next vault change (or app open) retries.
    }
  }
}
