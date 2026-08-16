import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../services/biometrics.dart';
import 'biometric_screen.dart';
import 'recovery_kit_screen.dart';

/// A2 (4b): pick the master password. Continue is disabled until both fields
/// match and strength is at least "Strong".
class MasterPasswordScreen extends ConsumerStatefulWidget {
  const MasterPasswordScreen({super.key});

  @override
  ConsumerState<MasterPasswordScreen> createState() =>
      _MasterPasswordScreenState();
}

class _MasterPasswordScreenState extends ConsumerState<MasterPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _show = false;
  // Whether the device can unlock without typing (biometric or PIN). Until we
  // know, assume yes so the step count doesn't flicker; corrected in initState.
  bool _bioAvailable = true;

  int get _totalSteps => _bioAvailable ? 3 : 2;

  @override
  void initState() {
    super.initState();
    Biometrics.canAuthenticate().then((v) {
      if (mounted) setState(() => _bioAvailable = v);
    });
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  /// Length-first strength: three unrelated words beat one word with symbols.
  /// The int is a level (0 empty, 1 too short, 2 nearly, 3 strong) resolved to
  /// a localized label in [build].
  (double, int, Color) get _strength {
    final text = _password.text;
    if (text.isEmpty) return (0, 0, TkColors.ink16);
    final length = text.length;
    final words = text.trim().split(RegExp(r'\s+')).length;
    final classes = [
      RegExp(r'[a-z]'),
      RegExp(r'[A-Z]'),
      RegExp(r'[0-9]'),
      RegExp(r'[^A-Za-z0-9]'),
    ].where((re) => re.hasMatch(text)).length;
    final score = length * 4 + words * 6 + classes * 4;
    if (length < 8 || score < 48) {
      return (.3, 1, TkColors.danger);
    }
    if (score < 72) {
      return (.6, 2, const Color(0xFFB0682E));
    }
    return (.85, 3, TkColors.green);
  }

  bool get _canContinue {
    final (fraction, _, _) = _strength;
    return fraction >= .85 &&
        _confirm.text == _password.text &&
        _password.text.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final (fraction, level, color) = _strength;
    final label = [
      '',
      l.strengthTooShort,
      l.strengthNearly,
      l.strengthStrong,
    ][level];
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TkStepPills(step: 1, total: _totalSteps),
              const SizedBox(height: 22),
              Text(l.mpTitle, style: TkText.screenTitle),
              const SizedBox(height: 10),
              Text(
                l.mpBody,
                style: TkText.body.copyWith(fontSize: 14.5, height: 1.55),
              ),
              const SizedBox(height: 22),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _field(
                        controller: _password,
                        hint: l.passwordHint,
                        focusBorder: true,
                        suffix: GestureDetector(
                          onTap: () => setState(() => _show = !_show),
                          child: Text(_show ? l.hide : l.show,
                              style: TkText.metadata.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: TkColors.ink45)),
                        ),
                      ),
                      if (_password.text.isNotEmpty) ...[
                        const SizedBox(height: 11),
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: SizedBox(
                                  height: 5,
                                  child: Stack(children: [
                                    Container(color: TkColors.ink10),
                                    AnimatedFractionallySizedBox(
                                      duration: TkMotion.feedback,
                                      alignment: Alignment.centerLeft,
                                      widthFactor: fraction,
                                      child: Container(color: color),
                                    ),
                                  ]),
                                ),
                              ),
                            ),
                            const SizedBox(width: 9),
                            Text(label,
                                style: TkText.metadata.copyWith(
                                    fontWeight: FontWeight.w600, color: color)),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      _field(controller: _confirm, hint: l.typeItAgain),
                      const SizedBox(height: 16),
                      TkNote(text: l.mpForgotNote),
                    ],
                  ),
                ),
              ),
              TkPrimaryButton(
                label: l.continueLabel,
                enabled: _canContinue,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _bioAvailable
                        // Step 2: offer biometric/PIN unlock.
                        ? BiometricScreen(password: _password.text)
                        // No lock method on this device — skip straight to the
                        // recovery kit as step 2 of 2.
                        : RecoveryKitScreen(
                            password: _password.text,
                            stepNumber: 2,
                            totalSteps: 2,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    bool focusBorder = false,
    Widget? suffix,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: TkColors.surface,
        border: Border.all(
          color: focusBorder && controller.text.isNotEmpty
              ? TkColors.green
              : TkColors.ink10,
          width: focusBorder && controller.text.isNotEmpty ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(TkRadius.panel),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: !_show,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(
                fontFamily: TkFonts.mono,
                fontSize: 17,
                letterSpacing: 17 * .06,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(
                  fontFamily: TkFonts.sans,
                  fontSize: 15,
                  color: TkColors.ink35,
                  letterSpacing: 0,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ),
          ?suffix,
        ],
      ),
    );
  }
}
