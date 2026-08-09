import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/design/tokens.dart';
import 'src/screens/home_shell.dart';
import 'src/screens/lock_screen.dart';
import 'src/screens/onboarding/first_launch_screen.dart';
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
}

class TwoKeysApp extends ConsumerWidget {
  const TwoKeysApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Two Keys',
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
