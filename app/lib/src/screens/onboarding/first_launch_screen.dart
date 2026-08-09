import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../recovery/restore_flow.dart';
import 'master_password_screen.dart';

/// A1 (4a): cold-start explainer.
class FirstLaunchScreen extends StatelessWidget {
  const FirstLaunchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 30, 26, TkSpace.bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const TkBrandTile(size: 48),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text("A password isn't enough on its own.",
                            style: TkText.heroTitle),
                        const SizedBox(height: 16),
                        Text(
                          "This app is the second thing — the part a thief on "
                          "the other side of the world can't get hold of, "
                          "because it's in your pocket.",
                          style: TkText.body.copyWith(fontSize: 16),
                        ),
                        const SizedBox(height: 22),
                        const _Tick('Nothing leaves this phone but six digits'),
                        const SizedBox(height: 11),
                        const _Tick('Works on a plane, with no signal'),
                        const SizedBox(height: 11),
                        const _Tick('No account to make, no email to give'),
                      ],
                    ),
                  ),
                ),
              ),
              TkPrimaryButton(
                label: 'Set it up — about two minutes',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const MasterPasswordScreen()),
                ),
              ),
              const SizedBox(height: 10),
              TkSecondaryButton(
                label: 'I already have a recovery kit',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RestoreFlow()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tick extends StatelessWidget {
  const _Tick(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 21,
          height: 21,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: TkColors.greenPale,
            borderRadius: BorderRadius.circular(7),
          ),
          alignment: Alignment.center,
          child: const Text('✓',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: TkColors.green)),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(text,
              style: TkText.body.copyWith(
                  fontSize: 14.5, height: 1.5, color: TkColors.ink70)),
        ),
      ],
    );
  }
}
