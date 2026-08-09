import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/design/tokens.dart';
import 'src/screens/home_shell.dart';
import 'src/screens/lock_screen.dart';
import 'src/screens/onboarding/first_launch_screen.dart';
import 'src/services/pairing_service.dart';
import 'src/services/push.dart';
import 'src/services/relay_api.dart';
import 'src/state/providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: TkColors.paper,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  runApp(const ProviderScope(child: TwoKeysApp()));
  // Fire-and-forget so startup isn't blocked. No-ops without a Firebase config.
  unawaited(_setUpPush());
}

/// Initialises push and keeps the relay's copy of this phone's FCM token
/// fresh, so the relay can wake us. Safe to run locked — the pairing lives in
/// secure storage and needs no unlock.
Future<void> _setUpPush() async {
  await PushService.init();
  if (!PushService.available) return;

  Future<void> register(String fcmToken) async {
    final pairing = await PairingService().current();
    if (pairing == null) return;
    await RelayApi(baseUrl: pairing.relayUrl)
        .updateFcmToken(
          pairingId: pairing.pairingId,
          phoneToken: pairing.phoneToken,
          fcmToken: fcmToken,
        )
        .catchError((_) {});
  }

  final token = await PushService.token();
  if (token != null) await register(token);
  PushService.onTokenRefresh((t) => unawaited(register(t)));
}

class TwoKeysApp extends ConsumerWidget {
  const TwoKeysApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Purr',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: TkFonts.sans,
        scaffoldBackgroundColor: TkColors.paper,
        colorScheme: ColorScheme.fromSeed(
          seedColor: TkColors.green,
          surface: TkColors.paper,
        ),
        splashFactory: InkSparkle.splashFactory,
      ),
      home: const _Root(),
    );
  }
}

class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vault = ref.watch(vaultProvider);
    return switch (vault.status) {
      VaultStatus.unknown => const Scaffold(
          body: Center(
            child: SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: TkColors.green),
            ),
          ),
        ),
      VaultStatus.needsOnboarding => const FirstLaunchScreen(),
      VaultStatus.locked => const LockScreen(),
      VaultStatus.unlocked => const HomeShell(),
    };
  }
}
