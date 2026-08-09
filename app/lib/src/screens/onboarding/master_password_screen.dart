import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/tokens.dart';
import '../../design/widgets.dart';
import 'biometric_screen.dart';

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

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  /// Length-first strength: three unrelated words beat one word with symbols.
  (double, String, Color) get _strength {
    final text = _password.text;
    if (text.isEmpty) return (0, '', TkColors.ink16);
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
      return (.3, 'Too short — keep going', TkColors.danger);
    }
    if (score < 72) {
      return (.6, 'Nearly there — a little longer', const Color(0xFFB0682E));
    }
    return (.85, 'Strong — good', TkColors.green);
  }

  bool get _canContinue {
    final (fraction, _, _) = _strength;
    return fraction >= .85 &&
        _confirm.text == _password.text &&
        _password.text.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final (fraction, label, color) = _strength;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const TkStepPills(step: 1),
              const SizedBox(height: 22),
              const Text('Pick one password to lock this app',
                  style: TkText.screenTitle),
              const SizedBox(height: 10),
              Text(
                "This is the only password you'll ever type here. Make it "
                "long rather than clever — three unrelated words beat one "
                "word with symbols.",
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
                        hint: 'Your password',
                        focusBorder: true,
                        suffix: GestureDetector(
                          onTap: () => setState(() => _show = !_show),
                          child: Text(_show ? 'Hide' : 'Show',
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
                      _field(controller: _confirm, hint: 'Type it again'),
                      const SizedBox(height: 16),
                      const TkNote(
                          text:
                              "If you forget it, we can't reset it for you — "
                              "we never see it. Your recovery kit is the way "
                              "back."),
                    ],
                  ),
                ),
              ),
              TkPrimaryButton(
                label: 'Continue',
                enabled: _canContinue,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BiometricScreen(password: _password.text),
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
