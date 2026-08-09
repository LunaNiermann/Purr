import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../crypto/recovery.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../services/kit_pdf.dart';
import '../../services/relay_api.dart';
import '../../state/providers.dart';

/// C1–C5 (3a–3f): the lost-phone storyboard. The person is stressed and on a
/// brand-new device — every screen answers one question and offers exactly
/// one way forward. Nothing here asks for a password.
class RestoreFlow extends StatelessWidget {
  const RestoreFlow({super.key});

  @override
  Widget build(BuildContext context) {
    return const _RestoreIntro();
  }
}

/// Beat 1 (3a): reassure first.
class _RestoreIntro extends StatelessWidget {
  const _RestoreIntro();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: TkColors.paper,
        elevation: 0,
        leading: const BackButton(color: TkColors.ink),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 8, 26, TkSpace.bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const TkBrandTile(size: 46),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Lost the phone with your codes on it?',
                          style: TkText.heroTitle),
                      const SizedBox(height: 16),
                      Text(
                        'You can get everything back. It takes a few minutes '
                        "and you'll need the sheet of paper you kept "
                        'somewhere safe.',
                        style: TkText.body.copyWith(fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
              TkPrimaryButton(
                label: 'Bring my codes back',
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const _WordsEntry())),
              ),
              const SizedBox(height: 10),
              TkSecondaryButton(
                label: 'Set up as a new phone',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Beat 3, paper route (3d): twelve word fields, live-validated.
class _WordsEntry extends ConsumerStatefulWidget {
  const _WordsEntry();

  @override
  ConsumerState<_WordsEntry> createState() => _WordsEntryState();
}

class _WordsEntryState extends ConsumerState<_WordsEntry> {
  final _controllers = List.generate(12, (_) => TextEditingController());
  final _focusNodes = List.generate(12, (_) => FocusNode());
  String? _error;

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  int get _remaining =>
      _controllers.where((c) => c.text.trim().isEmpty).length;

  bool get _allFilled => _remaining == 0;

  Future<void> _restore() async {
    final words = [for (final c in _controllers) c.text.trim().toLowerCase()];
    final kit = RecoveryKit.fromWords(words);
    if (kit == null) {
      setState(() => _error =
          "Those words don't quite line up — check each one against the "
          'sheet. Order matters.');
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => _Restoring(kit: kit)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: TkColors.paper,
        elevation: 0,
        leading: const BackButton(color: TkColors.ink),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text('Type the twelve words from your kit',
                    style: TkText.screenTitle),
              ),
              const SizedBox(height: 9),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text("In order, one per box. Don't worry about capitals.",
                    style: TkText.bodySecondary.copyWith(fontSize: 14)),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 9,
                        crossAxisSpacing: 9,
                        childAspectRatio: 3.6,
                        children: [
                          for (var i = 0; i < 12; i++) _wordField(i),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Text(_error!,
                            style: TkText.bodySecondary
                                .copyWith(color: TkColors.danger)),
                      ],
                      const SizedBox(height: 16),
                      const TkNote(
                          text:
                              'Lost the sheet too? If your old phone still '
                              'works, its Security tab can print a new one.'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TkPrimaryButton(
                label: _allFilled
                    ? 'Bring my codes back'
                    : '$_remaining word${_remaining == 1 ? '' : 's'} to go',
                enabled: _allFilled,
                onPressed: _restore,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _wordField(int i) {
    final controller = _controllers[i];
    final filled = controller.text.trim().isNotEmpty;
    final valid = !filled || RecoveryKit.isValidWord(controller.text);
    return Container(
      decoration: BoxDecoration(
        color: TkColors.surface,
        border: Border.all(
          color: !valid
              ? TkColors.danger
              : _focusNodes[i].hasFocus
                  ? TkColors.green
                  : TkColors.ink10,
          width: !valid || _focusNodes[i].hasFocus ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          SizedBox(
            width: 15,
            child: Text('${i + 1}',
                style: const TextStyle(fontSize: 11, color: TkColors.ink35)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: _focusNodes[i],
              autocorrect: false,
              enableSuggestions: false,
              textInputAction:
                  i < 11 ? TextInputAction.next : TextInputAction.done,
              onChanged: (text) {
                setState(() => _error = null);
                // Paste support: typing/pasting multiple words distributes.
                final words = text.trim().split(RegExp(r'\s+'));
                if (words.length > 1) {
                  for (var j = 0; j < words.length && i + j < 12; j++) {
                    _controllers[i + j].text = words[j];
                  }
                  final last = (i + words.length - 1).clamp(0, 11);
                  _focusNodes[last].requestFocus();
                }
              },
              onSubmitted: (_) {
                if (i < 11) _focusNodes[i + 1].requestFocus();
              },
              style: const TextStyle(
                  fontFamily: TkFonts.mono,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Beat 4 (3e): restoring, with plain checkpoints — never a bare spinner.
class _Restoring extends ConsumerStatefulWidget {
  const _Restoring({required this.kit});

  final RecoveryKit kit;

  @override
  ConsumerState<_Restoring> createState() => _RestoringState();
}

class _RestoringState extends ConsumerState<_Restoring> {
  int _step = 0; // 0 finding, 1 unlocking, 2 restoring
  String? _error;
  int _accountCount = 0;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final api = RelayApi();
      final backupId = await widget.kit.backupId();
      final backupAuth = await widget.kit.backupAuth();
      final fetched =
          await api.fetchBackup(backupId: backupId, backupAuth: backupAuth);
      if (fetched == null) {
        setState(() => _error =
            "We couldn't find a backup for those words. If backups were "
            'off on your old phone, the paper kit alone can\'t bring '
            'accounts back — but you can set up fresh.');
        return;
      }
      setState(() => _step = 1);
      final store = ref.read(vaultStoreProvider);
      final data = await store.restoreFromBackup(
        blob: fetched.$1,
        kit: widget.kit,
      );
      setState(() {
        _step = 2;
        _accountCount = data.accounts.length;
      });
      // Retire the used kit: rotate to fresh words + backup id (C5's
      // "the old sheet is retired on use").
      final newKit = await store.rotateKit();
      final (newId, newAuth, blob, digest) = await store.buildBackupBlob();
      try {
        await api.uploadBackup(
            backupId: newId, backupAuth: newAuth, blob: blob, digest: digest);
        await api.deleteBackup(backupId: backupId, backupAuth: backupAuth);
      } catch (_) {
        // Offline is fine; upload retries later. The local vault is safe.
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) =>
              _RestoreDone(count: _accountCount, newKit: newKit)));
    } on Exception {
      if (mounted) {
        setState(() => _error =
            "Something got in the way — check the connection and try again. "
            'Nothing was lost.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 30, 26, TkSpace.bottom),
          child: _error != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Spacer(),
                    const Text("That didn't work — but nothing is lost",
                        style: TkText.screenTitle),
                    const SizedBox(height: 12),
                    Text(_error!, style: TkText.body),
                    const Spacer(),
                    TkPrimaryButton(
                        label: 'Try the words again',
                        onPressed: () => Navigator.of(context)
                            .pushReplacement(MaterialPageRoute(
                                builder: (_) => const _WordsEntry()))),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),
                    const Text('Unscrambling your codes…',
                        style: TkText.heroTitle),
                    const SizedBox(height: 22),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: SizedBox(
                        height: 5,
                        child: Stack(children: [
                          Container(color: TkColors.ink10),
                          AnimatedFractionallySizedBox(
                            duration: const Duration(milliseconds: 500),
                            alignment: Alignment.centerLeft,
                            widthFactor: (_step + 1) / 3,
                            child: Container(color: TkColors.green),
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 22),
                    _check('Found your encrypted backup', _step >= 1),
                    const SizedBox(height: 11),
                    _check('Your words unlocked it', _step >= 2),
                    const SizedBox(height: 11),
                    _check(
                        _accountCount > 0
                            ? 'Putting $_accountCount account${_accountCount == 1 ? '' : 's'} back'
                            : 'Putting your accounts back',
                        false),
                    const SizedBox(height: 22),
                    Text(
                        'This all happens on this phone. We only ever stored '
                        "a scrambled copy we can't read.",
                        style: TkText.bodySecondary
                            .copyWith(color: TkColors.ink50)),
                    const Spacer(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _check(String label, bool done) {
    return Row(
      children: [
        AnimatedContainer(
          duration: TkMotion.feedback,
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: done ? TkColors.green : null,
            border: done
                ? null
                : Border.all(
                    color: const Color.fromRGBO(27, 26, 23, .18), width: 2),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: done
              ? const Text('✓',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: TkColors.paper))
              : null,
        ),
        const SizedBox(width: 11),
        Text(label,
            style: TkText.body.copyWith(
                fontSize: 14.5,
                color: done ? TkColors.ink70 : TkColors.ink45)),
      ],
    );
  }
}

/// Beat 5 (3f): back, with one job left.
class _RestoreDone extends ConsumerWidget {
  const _RestoreDone({required this.count, required this.newKit});

  final int count;
  final RecoveryKit newKit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: TkColors.green,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 30, 26, TkSpace.bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 62,
                        height: 62,
                        decoration: const BoxDecoration(
                            color: TkColors.mintPale, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: const Text('✓',
                            style: TextStyle(
                                fontSize: 29,
                                fontWeight: FontWeight.w700,
                                color: TkColors.greenDeep)),
                      ),
                      const SizedBox(height: 18),
                      Text(
                          count == 1
                              ? 'Your account is back.'
                              : 'All $count accounts are back.',
                          style: TkText.heroTitle
                              .copyWith(color: TkColors.paper)),
                      const SizedBox(height: 12),
                      Text(
                          'Your old phone has been cut off — if someone finds '
                          'it, its codes no longer work.',
                          style: TkText.body.copyWith(
                              fontSize: 16,
                              color: const Color.fromRGBO(
                                  247, 245, 241, .85))),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(17),
                        decoration: BoxDecoration(
                          color: const Color.fromRGBO(247, 245, 241, .12),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('One thing left: print a fresh kit',
                                style: TextStyle(
                                    fontFamily: TkFonts.sans,
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w700,
                                    color: TkColors.paper)),
                            const SizedBox(height: 7),
                            Text(
                                'The old sheet is retired now. A new one '
                                'takes ten seconds and covers you next time.',
                                style: TkText.bodySecondary.copyWith(
                                    color: const Color.fromRGBO(
                                        247, 245, 241, .85))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              TkPrimaryButton(
                label: 'Print my new kit',
                background: TkColors.paper,
                foreground: TkColors.greenDeep,
                onPressed: () async {
                  await printRecoveryKit(kit: newKit, accountCount: count);
                  if (context.mounted) _finish(context, ref);
                },
              ),
              const SizedBox(height: 10),
              TkSecondaryButton(
                label: 'Remind me tonight',
                borderColor: const Color.fromRGBO(247, 245, 241, .28),
                foreground: TkColors.paper,
                onPressed: () => _finish(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _finish(BuildContext context, WidgetRef ref) {
    unawaited(ref
        .read(prefsProvider.notifier)
        .update((p) => p.copyWith(kitSavedAt: DateTime.now())));
    // The restored vault is unlocked in the store; surface it.
    () async {
      final store = ref.read(vaultStoreProvider);
      final data = await store.unlockWithStoredDek();
      if (data != null) {
        ref.read(vaultProvider.notifier).setUnlocked(data);
      }
      if (context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }();
  }
}
