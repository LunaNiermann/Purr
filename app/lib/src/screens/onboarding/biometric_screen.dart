import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../services/biometrics.dart';
import '../../state/providers.dart';
import 'recovery_kit_screen.dart';

/// A3 (4c): biometric opt-in. Declining is a first-class path. The design's
/// Face ID copy is adapted to the device's actual biometric.
class BiometricScreen extends ConsumerStatefulWidget {
  const BiometricScreen({super.key, required this.password});

  final String password;

  @override
  ConsumerState<BiometricScreen> createState() => _BiometricScreenState();
}

class _BiometricScreenState extends ConsumerState<BiometricScreen> {
  String _label = 'screen lock';
  bool _available = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    () async {
      final available = await Biometrics.available();
      final label = await Biometrics.label();
      if (mounted) {
        setState(() {
          _available = available;
          _label = label;
        });
      }
    }();
  }

  bool get _isFace => _label == 'face unlock';

  Future<void> _finish({required bool enable}) async {
    if (_busy) return;
    setState(() => _busy = true);
    if (enable) {
      final ok =
          await Biometrics.prompt(AppLocalizations.of(context).bioConfirmTry);
      if (!ok) {
        setState(() => _busy = false);
        return;
      }
    }
    await ref
        .read(prefsProvider.notifier)
        .update((p) => p.copyWith(biometricsEnabled: enable));
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecoveryKitScreen(password: widget.password),
      ),
    );
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final (title, body, turnOn) = _isFace
        ? (l.bioTitleFace, l.bioBodyFace, l.bioTurnOnFace)
        : _label == 'fingerprint'
            ? (l.bioTitleFingerprint, l.bioBodyFingerprint, l.bioTurnOnFingerprint)
            : (l.bioTitleScreenLock, l.bioBodyScreenLock, l.bioTurnOnScreenLock);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 24, 26, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const TkStepPills(step: 2),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 82,
                        height: 82,
                        decoration: BoxDecoration(
                          border:
                              Border.all(color: TkColors.green, width: 2.5),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Icon(
                          _isFace
                              ? Icons.face_outlined
                              : Icons.fingerprint,
                          size: 44,
                          color: TkColors.green,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(title,
                          style: TkText.screenTitle.copyWith(fontSize: 29)),
                      const SizedBox(height: 12),
                      Text(body, style: TkText.body),
                    ],
                  ),
                ),
              ),
              TkPrimaryButton(
                label: turnOn,
                enabled: _available && !_busy,
                onPressed: () => _finish(enable: true),
              ),
              const SizedBox(height: 10),
              TkSecondaryButton(
                label: l.bioTypeInstead,
                onPressed: _busy ? null : () => _finish(enable: false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
