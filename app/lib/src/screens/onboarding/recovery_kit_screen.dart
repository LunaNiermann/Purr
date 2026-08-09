import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../crypto/recovery.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../services/kit_pdf.dart';
import '../../state/providers.dart';

/// A4 (4d): step 3 of 3 — create the vault and show the twelve words.
/// FLAG_SECURE is on app-wide, so this screen can't be screenshotted.
class RecoveryKitScreen extends ConsumerStatefulWidget {
  const RecoveryKitScreen({
    super.key,
    required this.password,
    this.stepNumber = 3,
    this.totalSteps = 3,
  });

  final String password;
  final int stepNumber;
  final int totalSteps;

  @override
  ConsumerState<RecoveryKitScreen> createState() => _RecoveryKitScreenState();
}

class _RecoveryKitScreenState extends ConsumerState<RecoveryKitScreen> {
  RecoveryKit? _kit;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _create();
  }

  Future<void> _create() async {
    final store = ref.read(vaultStoreProvider);
    final kit = await store.create(password: widget.password);
    if (mounted) setState(() => _kit = kit);
  }

  Future<void> _finish({required bool printed}) async {
    if (_finishing || _kit == null) return;
    setState(() => _finishing = true);
    if (printed) {
      await printRecoveryKit(kit: _kit!, accountCount: 0);
    }
    await ref
        .read(prefsProvider.notifier)
        .update((p) => p.copyWith(kitSavedAt: DateTime.now()));
    ref.read(vaultProvider.notifier).setFreshlyCreated();
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final kit = _kit;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: TkStepPills(
                    step: widget.stepNumber, total: widget.totalSteps),
              ),
              const SizedBox(height: 20),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child:
                    Text('Your way back in, on paper', style: TkText.screenTitle),
              ),
              const SizedBox(height: 9),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Twelve words that can restore everything onto a new '
                  "phone. Print them now — it's the one step people skip "
                  'and regret.',
                  style: TkText.body.copyWith(fontSize: 14.5, height: 1.55),
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: kit == null
                    ? const Center(
                        child: SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: TkColors.green),
                        ),
                      )
                    : SingleChildScrollView(
                        child: Column(
                          children: [
                            TkCard(
                              padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                              borderColor: TkColors.ink10,
                              child: GridView.count(
                                crossAxisCount: 2,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                                childAspectRatio: 4.6,
                                children: [
                                  for (var i = 0; i < kit.words.length; i++)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 9),
                                      decoration: BoxDecoration(
                                        color: TkColors.paper,
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 15,
                                            child: Text('${i + 1}',
                                                style: const TextStyle(
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.w600,
                                                    color: TkColors.ink35)),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(kit.words[i],
                                              style: const TextStyle(
                                                  fontFamily: TkFonts.mono,
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w500,
                                                  color: TkColors.ink)),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            const TkNote(
                                text:
                                    "Don't screenshot these. A photo in your "
                                    'camera roll is a copy anyone who unlocks '
                                    'your phone can read.'),
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              TkPrimaryButton(
                label: 'Print my kit',
                enabled: kit != null && !_finishing,
                onPressed: () => _finish(printed: true),
              ),
              const SizedBox(height: 9),
              TkSecondaryButton(
                label: 'I wrote them down by hand',
                onPressed:
                    kit == null || _finishing ? null : () => _finish(printed: false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
