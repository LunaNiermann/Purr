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
    required this.domain,
    required this.browser,
    required this.askedAt,
    required this.expiresAt,
  });

  final String requestId;
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
  const PairingState({this.pairing, this.loaded = false});
  final StoredPairing? pairing;
  final bool loaded;
}

class PairingController extends Notifier<PairingState> {
  @override
  PairingState build() {
    _load();
    return const PairingState();
  }

  Future<void> _load() async {
    final pairing = await ref.read(pairingServiceProvider).current();
    state = PairingState(pairing: pairing, loaded: true);
  }

  Future<void> refresh() => _load();

  Future<void> unpair() async {
    await ref.read(pairingServiceProvider).unpair();
    state = const PairingState(pairing: null, loaded: true);
  }
}

final pairingProvider =
    NotifierProvider<PairingController, PairingState>(PairingController.new);

/// Foreground listener: while the vault is unlocked and a browser is paired,
/// long-poll the relay for pending requests. This is the no-push path that
/// always works ("Requests will be waiting here for a minute"); FCM, when
/// configured, merely wakes the app sooner.
class ApprovalController extends Notifier<PendingApproval?> {
  Timer? _restart;
  bool _running = false;

  @override
  PendingApproval? build() {
    final vault = ref.watch(vaultProvider);
    final pairing = ref.watch(pairingProvider);
    if (vault.status == VaultStatus.unlocked && pairing.pairing != null) {
      _ensureLoop(pairing.pairing!);
    }
    ref.onDispose(() {
      _running = false;
      _restart?.cancel();
    });
    return null;
  }

  void _ensureLoop(StoredPairing pairing) {
    if (_running) return;
    _running = true;
    unawaited(_loop(pairing));
  }

  Future<void> _loop(StoredPairing pairing) async {
    final api = RelayApi(baseUrl: pairing.relayUrl);
    // Request ids we've already shown or skipped. `wait-pending` keeps
    // returning a request until it's answered/expires, so without this we'd
    // re-fetch it in a tight spin every time it comes back.
    final handled = <String>{};
    while (_running) {
      // Stop when the vault locks or the pairing is removed.
      final vault = ref.read(vaultProvider);
      final currentPairing = ref.read(pairingProvider).pairing;
      if (vault.status != VaultStatus.unlocked || currentPairing == null) {
        _running = false;
        return;
      }
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
          handled.add(req.requestId);
          if (state != null) break;
          final payload = await PairingCrypto.open(
            pairing.sessionKey,
            req.requestBlobB64,
          );
          if (payload['kind'] != 'code') continue;
          final domain = (payload['domain'] as String? ?? '').toLowerCase();
          final data = ref.read(vaultProvider).data;
          if (data != null && data.isMutedToday(domain)) continue;
          state = PendingApproval(
            requestId: req.requestId,
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
  }

  /// Sends the six digits for [account], sealed for the paired browser.
  Future<bool> approve(PendingApproval request, Account account) async {
    final pairing = ref.read(pairingProvider).pairing;
    if (pairing == null) return false;
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
    final pairing = ref.read(pairingProvider).pairing;
    if (pairing != null) {
      final blob = await PairingCrypto.seal(
          pairing.sessionKey, {'verdict': 'denied'});
      await RelayApi(baseUrl: pairing.relayUrl)
          .answerRequest(
            requestId: request.requestId,
            phoneToken: pairing.phoneToken,
            answerBlobB64: blob,
          )
          .catchError((_) {});
    }
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
