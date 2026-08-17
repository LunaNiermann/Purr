import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../state/providers.dart';
import 'pairing_crypto.dart';
import 'pairing_service.dart';
import 'relay_api.dart';

/// A decrypted approval request waiting on this phone.
class PendingApproval {
  PendingApproval({
    required this.requestId,
    required this.pairing,
    required this.domain,
    required this.browser,
    required this.askedAt,
    required this.expiresAt,
  });

  final String requestId;

  /// The pairing this request arrived on. Carried explicitly because the phone
  /// serves several browsers: the answer must be sealed with *this* browser's
  /// session key, not whichever pairing happens to be first in the list.
  final StoredPairing pairing;

  final String domain;
  final String browser;
  final DateTime askedAt;
  final DateTime expiresAt;

  bool get expired => DateTime.now().isAfter(expiresAt);
}

final pairingServiceProvider = Provider<PairingService>(
  (ref) => PairingService(),
);

class PairingState {
  const PairingState({this.pairings = const [], this.loaded = false});

  /// Every paired browser, oldest first.
  final List<StoredPairing> pairings;
  final bool loaded;

  bool get isPaired => pairings.isNotEmpty;
}

class PairingController extends Notifier<PairingState> {
  @override
  PairingState build() {
    _load();
    return const PairingState();
  }

  Future<void> _load() async {
    final pairings = await ref.read(pairingServiceProvider).all();
    state = PairingState(pairings: pairings, loaded: true);
  }

  Future<void> refresh() => _load();

  /// Unpairs one browser; the rest keep working.
  Future<void> unpair(String pairingId) async {
    await ref.read(pairingServiceProvider).unpair(pairingId);
    await _load();
  }
}

final pairingProvider =
    NotifierProvider<PairingController, PairingState>(PairingController.new);

/// Foreground listener: while the vault is unlocked and a browser is paired,
/// long-poll the relay for pending requests. This is the no-push path that
/// always works ("Requests will be waiting here for a minute"); FCM, when
/// configured, merely wakes the app sooner.
class ApprovalController extends Notifier<PendingApproval?> {
  /// Pairing ids with a live poll loop, so re-entering [build] doesn't stack a
  /// second loop on a browser that already has one.
  final Set<String> _active = {};

  /// Bumped whenever the provider is torn down or recomputed. Loops carry the
  /// generation they started in and exit as soon as it moves on, which keeps a
  /// rebuild from leaving orphaned pollers behind.
  int _generation = 0;

  @override
  PendingApproval? build() {
    final vault = ref.watch(vaultProvider);
    final pairings = ref.watch(pairingProvider).pairings;
    ref.onDispose(() {
      _generation++;
      _active.clear();
    });
    if (vault.status == VaultStatus.unlocked) {
      for (final pairing in pairings) {
        _ensureLoop(pairing, _generation);
      }
    }
    return null;
  }

  void _ensureLoop(StoredPairing pairing, int generation) {
    if (!_active.add(pairing.pairingId)) return;
    unawaited(_loop(pairing, generation));
  }

  /// One long-poll loop per paired browser. They run concurrently and compete
  /// for the single on-screen slot; whichever request arrives while the screen
  /// is free is the one shown, and the others stay pending on the relay.
  Future<void> _loop(StoredPairing pairing, int generation) async {
    final api = RelayApi(baseUrl: pairing.relayUrl);
    // Request ids we've already shown or deliberately skipped. `wait-pending`
    // keeps returning a request until it's answered/expires, so without this
    // we'd re-fetch it in a tight spin every time it comes back.
    final handled = <String>{};
    try {
      while (generation == _generation) {
        // Stop when the vault locks or this browser is unpaired.
        final vault = ref.read(vaultProvider);
        final stillPaired = ref
            .read(pairingProvider)
            .pairings
            .any((p) => p.pairingId == pairing.pairingId);
        if (vault.status != VaultStatus.unlocked || !stillPaired) return;
        // While a request is already on screen, don't poll — wait for the user
        // to act (approve/deny/dismiss clears `state`).
        if (state != null) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          continue;
        }
        try {
          final pending = await api.pendingRequests(
            pairingId: pairing.pairingId,
            phoneToken: pairing.phoneToken,
            wait: true,
          );
          if (state != null) continue;
          // Only act on requests we haven't handled yet.
          final fresh =
              pending.where((r) => !handled.contains(r.requestId)).toList();
          if (fresh.isEmpty) {
            // Everything pending is already shown/muted — back off so we don't
            // spin (the endpoint returns muted/handled requests instantly).
            if (pending.isNotEmpty) {
              await Future<void>.delayed(const Duration(seconds: 3));
            }
            continue;
          }
          for (final req in fresh) {
            // Another browser's request is on screen. Leave this one unhandled
            // so we offer it again once the slot frees, rather than burning it.
            if (state != null) break;
            // Decrypt is per-request: an undecryptable blob is marked handled
            // and skipped, so one bad request can't abort the batch or (via the
            // outer catch) masquerade as a network error.
            final Map<String, dynamic> payload;
            try {
              payload = await PairingCrypto.open(
                pairing.sessionKey,
                req.requestBlobB64,
              );
            } catch (_) {
              handled.add(req.requestId);
              continue;
            }
            if (payload['kind'] != 'code') {
              handled.add(req.requestId);
              continue;
            }
            final domain = (payload['domain'] as String? ?? '').toLowerCase();
            final data = ref.read(vaultProvider).data;
            if (data != null && data.isMutedToday(domain)) {
              handled.add(req.requestId);
              continue;
            }
            // Re-check after the awaits above: another loop may have taken the
            // slot while this request was being decrypted.
            if (state != null) break;
            handled.add(req.requestId);
            state = PendingApproval(
              requestId: req.requestId,
              pairing: pairing,
              domain: domain,
              browser: payload['browser'] as String? ?? 'A browser',
              askedAt: req.createdAt,
              expiresAt: req.expiresAt,
            );
          }
        } catch (_) {
          // Network hiccup: back off briefly, keep listening.
          await Future<void>.delayed(const Duration(seconds: 4));
        }
      }
    } finally {
      if (generation == _generation) _active.remove(pairing.pairingId);
    }
  }

  /// Sends the six digits for [account], sealed for the browser that asked.
  Future<bool> approve(PendingApproval request, Account account) async {
    final pairing = request.pairing;
    final code = account.totp.codeAt(DateTime.now());
    final blob = await PairingCrypto.seal(pairing.sessionKey, {
      'verdict': 'approved',
      'code': code,
      'site': account.siteName,
      'username': account.username,
    });
    try {
      await RelayApi(baseUrl: pairing.relayUrl).answerRequest(
        requestId: request.requestId,
        phoneToken: pairing.phoneToken,
        answerBlobB64: blob,
      );
      return true;
    } on RelayExpiredException {
      return false;
    } catch (_) {
      return false;
    } finally {
      state = null;
    }
  }

  /// "I didn't ask for this" — no code is generated or sent.
  Future<void> deny(PendingApproval request) async {
    final pairing = request.pairing;
    final blob =
        await PairingCrypto.seal(pairing.sessionKey, {'verdict': 'denied'});
    await RelayApi(baseUrl: pairing.relayUrl)
        .answerRequest(
          requestId: request.requestId,
          phoneToken: pairing.phoneToken,
          answerBlobB64: blob,
        )
        .catchError((_) {});
    // Record the incident for the aftermath screen.
    await ref.read(vaultProvider.notifier).mutate((data) {
      final existing = data.incidents.where(
        (i) => i.domain == request.domain && !i.seen,
      );
      final merged = existing.isEmpty
          ? Incident(
              domain: request.domain,
              browser: request.browser,
              at: DateTime.now().toUtc(),
            )
          : existing.first.copyWith(
              attempts: existing.first.attempts + 1,
              at: DateTime.now().toUtc(),
            );
      return VaultData(
        accounts: data.accounts,
        mutedSites: data.mutedSites,
        incidents: [
          for (final i in data.incidents)
            if (!(i.domain == request.domain && !i.seen)) i,
          merged,
        ],
      );
    });
    state = null;
  }

  /// "Just show me the code" — the extension is told nothing; it expires.
  void dismissSilently() {
    state = null;
  }
}

final approvalProvider =
    NotifierProvider<ApprovalController, PendingApproval?>(
        ApprovalController.new);
