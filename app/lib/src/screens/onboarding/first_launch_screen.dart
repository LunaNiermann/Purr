import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../recovery/restore_flow.dart';
import 'master_password_screen.dart';

/// A1 (4a): cold-start explainer.
class FirstLaunchScreen extends StatelessWidget {
  const FirstLaunchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
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
                        Text(l.onbHeroTitle, style: TkText.heroTitle),
                        const SizedBox(height: 16),
                        Text(
                          l.onbHeroBody,
                          style: TkText.body.copyWith(fontSize: 16),
                        ),
                        const SizedBox(height: 22),
                        _Tick(l.onbTick1),
                        const SizedBox(height: 11),
                        _Tick(l.onbTick2),
                        const SizedBox(height: 11),
                        _Tick(l.onbTick3),
                      ],
                    ),
                  ),
                ),
              ),
              TkPrimaryButton(
                label: l.onbSetUp,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const MasterPasswordScreen()),
                ),
              ),
              const SizedBox(height: 10),
              TkSecondaryButton(
                label: l.onbHaveKit,
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
