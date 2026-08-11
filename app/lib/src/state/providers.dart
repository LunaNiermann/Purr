import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';
import '../data/vault_store.dart';
import '../services/replica_service.dart';

/// 1 Hz heartbeat driving every countdown. Recomputed from wall clock on each
/// tick so a backgrounded app snaps to the right remaining time on resume.
final tickProvider = StreamProvider<DateTime>((ref) {
  return Stream<DateTime>.periodic(
      const Duration(seconds: 1), (_) => DateTime.now())
    ..asBroadcastStream();
});

final vaultStoreProvider = Provider<VaultStore>((ref) => VaultStore());

enum VaultStatus { unknown, needsOnboarding, locked, unlocked }

class VaultState {
  const VaultState({required this.status, this.data});

  final VaultStatus status;
  final VaultData? data;

  List<Account> get accounts => data?.accounts ?? const [];

  VaultState copyWith({VaultStatus? status, VaultData? data}) =>
      VaultState(status: status ?? this.status, data: data ?? this.data);
}

class VaultController extends Notifier<VaultState> {
  @override
  VaultState build() {
    _init();
    return const VaultState(status: VaultStatus.unknown);
  }

  VaultStore get _store => ref.read(vaultStoreProvider);

  Future<void> _init() async {
    final exists = await _store.exists();
    state = VaultState(
      status: exists ? VaultStatus.locked : VaultStatus.needsOnboarding,
    );
  }

  void setUnlocked(VaultData data) {
    state = VaultState(status: VaultStatus.unlocked, data: data);
    _syncReplica();
  }

  void lock() {
    _store.lock();
    state = const VaultState(status: VaultStatus.locked);
  }

  Future<void> mutate(VaultData Function(VaultData) transform) async {
    final current = state.data;
    if (current == null) throw StateError('Vault is locked');
    final updated = transform(current);
    await _store.save(updated);
    state = state.copyWith(data: updated);
    _syncReplica();
  }

  /// Push the encrypted vault replica to the desktop key route, if enrolled.
  /// Fire-and-forget: a no-op unless a security key has been set up.
  void _syncReplica() {
    final data = state.data;
    if (data == null) return;
    unawaited(const ReplicaService().syncFromAccounts(data.accounts));
  }

  /// After onboarding created the vault.
  void setFreshlyCreated() {
    state = VaultState(
        status: VaultStatus.unlocked, data: VaultData(accounts: []));
  }
}

final vaultProvider =
    NotifierProvider<VaultController, VaultState>(VaultController.new);

/// Non-secret presentation preferences ("How your codes look").
class Prefs {
  const Prefs({
    this.layout = 'list',
    this.hideCodes = false,
    this.biometricsEnabled = false,
    this.encryptedBackup = true,
    this.notificationsChoice = 'unasked', // unasked | granted | declined
    this.kitSavedAt,
  });

  final String layout; // 'list' | 'cards'
  final bool hideCodes;
  final bool biometricsEnabled;
  final bool encryptedBackup;
  final String notificationsChoice;
  final DateTime? kitSavedAt;

  Prefs copyWith({
    String? layout,
    bool? hideCodes,
    bool? biometricsEnabled,
    bool? encryptedBackup,
    String? notificationsChoice,
    DateTime? kitSavedAt,
  }) =>
      Prefs(
        layout: layout ?? this.layout,
        hideCodes: hideCodes ?? this.hideCodes,
        biometricsEnabled: biometricsEnabled ?? this.biometricsEnabled,
        encryptedBackup: encryptedBackup ?? this.encryptedBackup,
        notificationsChoice: notificationsChoice ?? this.notificationsChoice,
        kitSavedAt: kitSavedAt ?? this.kitSavedAt,
      );
}

class PrefsController extends Notifier<Prefs> {
  @override
  Prefs build() {
    _load();
    return const Prefs();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    state = Prefs(
      layout: sp.getString('layout') ?? 'list',
      hideCodes: sp.getBool('hideCodes') ?? false,
      biometricsEnabled: sp.getBool('biometricsEnabled') ?? false,
      encryptedBackup: sp.getBool('encryptedBackup') ?? true,
      notificationsChoice: sp.getString('notificationsChoice') ?? 'unasked',
      kitSavedAt: DateTime.tryParse(sp.getString('kitSavedAt') ?? ''),
    );
  }

  Future<void> update(Prefs Function(Prefs) transform) async {
    state = transform(state);
    final sp = await SharedPreferences.getInstance();
    await sp.setString('layout', state.layout);
    await sp.setBool('hideCodes', state.hideCodes);
    await sp.setBool('biometricsEnabled', state.biometricsEnabled);
    await sp.setBool('encryptedBackup', state.encryptedBackup);
    await sp.setString('notificationsChoice', state.notificationsChoice);
    if (state.kitSavedAt != null) {
      await sp.setString(
          'kitSavedAt', state.kitSavedAt!.toUtc().toIso8601String());
    }
  }
}

final prefsProvider = NotifierProvider<PrefsController, Prefs>(
  PrefsController.new,
);

/// Which account row is showing the 2-second "Copied" state.
class CopiedIdController extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? id) => state = id;
}

final copiedIdProvider =
    NotifierProvider<CopiedIdController, String?>(CopiedIdController.new);
