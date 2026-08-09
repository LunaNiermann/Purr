import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'relay_api.dart';

/// Uploads the encrypted backup blob to the relay whenever the vault changes,
/// if the user has "Encrypted backup" on. The blob is sealed with the kit's
/// backup key (VaultStore.buildBackupBlob) — the relay only ever stores
/// ciphertext, addressed by a kit-derived id. Upload is verified at write
/// time (the relay echoes the digest) so corruption surfaces immediately,
/// not at restore (the Authy lesson).
class BackupStatus {
  const BackupStatus({this.uploading = false, this.lastError, this.lastAt});
  final bool uploading;
  final String? lastError;
  final DateTime? lastAt;
}

class BackupController extends Notifier<BackupStatus> {
  Timer? _debounce;
  int _generation = 0;

  @override
  BackupStatus build() {
    // React to vault changes while unlocked and backups enabled.
    final vault = ref.watch(vaultProvider);
    final enabled = ref.watch(
        prefsProvider.select((p) => p.encryptedBackup));
    if (vault.status == VaultStatus.unlocked && enabled) {
      _schedule();
    }
    ref.onDispose(() => _debounce?.cancel());
    return const BackupStatus();
  }

  void _schedule() {
    _debounce?.cancel();
    final gen = ++_generation;
    // Coalesce bursts of edits into one upload.
    _debounce = Timer(const Duration(seconds: 2), () {
      if (gen == _generation) unawaited(uploadNow());
    });
  }

  /// Uploads immediately (also used right after enabling the toggle).
  Future<void> uploadNow() async {
    if (ref.read(vaultProvider).status != VaultStatus.unlocked) return;
    state = const BackupStatus(uploading: true);
    try {
      final store = ref.read(vaultStoreProvider);
      final (backupId, backupAuth, blob, digest) =
          await store.buildBackupBlob();
      final pairing = ref.read(pairingRelayUrlProvider);
      await RelayApi(baseUrl: pairing).uploadBackup(
        backupId: backupId,
        backupAuth: backupAuth,
        blob: blob,
        digest: digest,
      );
      state = BackupStatus(lastAt: DateTime.now());
    } on RelayCorruptionException {
      state = const BackupStatus(
          lastError: 'The backup arrived scrambled — we did not keep it. '
              'It will try again.');
    } catch (e) {
      // Offline is fine; the next change (or app open) retries.
      state = BackupStatus(lastError: 'offline', lastAt: state.lastAt);
    }
  }
}

/// The relay base url to use for backups — the paired relay if any, else the
/// default. Backups don't require a pairing (a fresh phone restoring has
/// none), so this falls back cleanly.
final pairingRelayUrlProvider = Provider<String>((ref) {
  return RelayApi.defaultBaseUrl;
});

final backupProvider =
    NotifierProvider<BackupController, BackupStatus>(BackupController.new);
