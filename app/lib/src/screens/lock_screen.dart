import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/tokens.dart';
import '../design/widgets.dart';
import '../services/biometrics.dart';
import '../state/providers.dart';

/// A10 (4h): dark gradient lock screen. Biometric primary (when enabled),
/// password always available underneath.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _password = TextEditingController();
  bool _showPassword = false;
  bool _busy = false;
  String? _error;
  bool _autoTried = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _tryBiometric() async {
    final prefs = ref.read(prefsProvider);
    if (!prefs.biometricsEnabled || _autoTried) return;
    _autoTried = true;
    await _unlockWithBiometric();
  }

  Future<void> _unlockWithBiometric() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await Biometrics.prompt('Unlock your codes');
    if (ok) {
      final data = await ref.read(vaultStoreProvider).unlockWithStoredDek();
      if (data != null && mounted) {
        ref.read(vaultProvider.notifier).setUnlocked(data);
        return;
      }
      if (mounted) {
        setState(() {
          _showPassword = true;
          _error = 'Please type your password this time.';
        });
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _unlockWithPassword() async {
    if (_busy || _password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await ref
          .read(vaultStoreProvider)
          .unlockWithPassword(_password.text);
      if (mounted) ref.read(vaultProvider.notifier).setUnlocked(data);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = "That's not it — check for typos and try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(prefsProvider);
    final biometricsOn = prefs.biometricsEnabled;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: TkColors.inkGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 30, 26, TkSpace.bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const TkBrandTile(
                    size: 44,
                    background: TkColors.paper,
                    foreground: TkColors.ink),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 52,
                            height: 66,
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: const Color.fromRGBO(
                                      247, 245, 241, .75),
                                  width: 2.5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text('Locked',
                              style: TextStyle(
                                  fontFamily: TkFonts.sans,
                                  fontSize: 23,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 23 * -.015,
                                  color: TkColors.paper)),
                          const SizedBox(height: 12),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 18),
                            child: Text(
                              biometricsOn && !_showPassword
                                  ? 'Your codes are here and safe. '
                                      'Unlock to open up.'
                                  : 'Your codes are here and safe. '
                                      'Type your password to open up.',
                              textAlign: TextAlign.center,
                              style: TkText.body.copyWith(
                                  fontSize: 14.5, color: TkColors.paper55),
                            ),
                          ),
                          if (_showPassword || !biometricsOn) ...[
                            const SizedBox(height: 24),
                            Container(
                              decoration: BoxDecoration(
                                color: const Color.fromRGBO(
                                    247, 245, 241, .08),
                                border: Border.all(color: TkColors.paper20),
                                borderRadius:
                                    BorderRadius.circular(TkRadius.panel),
                              ),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16),
                              child: TextField(
                                controller: _password,
                                obscureText: true,
                                autofocus: true,
                                autocorrect: false,
                                enableSuggestions: false,
                                onSubmitted: (_) => _unlockWithPassword(),
                                style: const TextStyle(
                                  fontFamily: TkFonts.mono,
                                  fontSize: 17,
                                  color: TkColors.paper,
                                  letterSpacing: 17 * .06,
                                ),
                                decoration: const InputDecoration(
                                  hintText: 'Your password',
                                  hintStyle: TextStyle(
                                    fontFamily: TkFonts.sans,
                                    fontSize: 15,
                                    color: TkColors.paper55,
                                    letterSpacing: 0,
                                  ),
                                  border: InputBorder.none,
                                  contentPadding:
                                      EdgeInsets.symmetric(vertical: 15),
                                ),
                              ),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Text(_error!,
                                  textAlign: TextAlign.center,
                                  style: TkText.bodySecondary.copyWith(
                                      color: const Color(0xFFE8A79A))),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (_showPassword || !biometricsOn)
                  TkPrimaryButton(
                    label: _busy ? 'Unlocking…' : 'Unlock',
                    background: TkColors.greenBright,
                    foreground: TkColors.onGreenBrightText,
                    enabled: !_busy,
                    onPressed: _unlockWithPassword,
                  )
                else ...[
                  TkPrimaryButton(
                    label: 'Unlock',
                    background: TkColors.greenBright,
                    foreground: TkColors.onGreenBrightText,
                    enabled: !_busy,
                    onPressed: _unlockWithBiometric,
                  ),
                  const SizedBox(height: 10),
                  TkTextButton(
                    label: 'Use my password',
                    color: const Color.fromRGBO(247, 245, 241, .6),
                    onPressed: () => setState(() => _showPassword = true),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
