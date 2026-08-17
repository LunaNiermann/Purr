import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/otpauth.dart';
import '../../crypto/recovery.dart';
import '../../data/models.dart';
import '../../../l10n/app_localizations.dart';
import '../../l10n/languages.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../services/approval_service.dart';
import '../../services/backup_service.dart';
import '../../services/biometrics.dart';
import '../../services/kit_pdf.dart';
import '../../services/pairing_service.dart';
import '../../services/push.dart';
import '../../state/providers.dart';
import 'pair_computer_screen.dart';

/// A9: the Security tab — status card, recovery, layout pickers, hide codes,
/// on-this-phone toggles, and (research commandment 1) export.
class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});

  @override
  ConsumerState<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends ConsumerState<SecurityScreen> {
  bool _canAuth = true; // corrected in initState; hides the unlock toggle if false

  @override
  void initState() {
    super.initState();
    Biometrics.canAuthenticate().then((v) {
      if (mounted) setState(() => _canAuth = v);
    });
  }

  Future<void> _printKitAgain() async {
    final ok = await Biometrics.confirmOrBypass(
        AppLocalizations.of(context).secKitReason);
    if (!ok) return;
    final meta = await ref.read(vaultStoreProvider).kitMeta();
    if (meta == null || !mounted) return;
    final entropy = meta['entropyB64'] as String?;
    if (entropy == null) return;
    final kit = RecoveryKit.fromEntropyB64(entropy);
    final count = ref.read(vaultProvider).accounts.length;
    await printRecoveryKit(kit: kit, accountCount: count);
  }

  String _currentLanguageName(String tag) {
    if (tag == 'system') {
      return AppLocalizations.of(context).languageSystemDefault;
    }
    return kAppLanguages
        .firstWhere((l) => l.tag == tag,
            orElse: () => const AppLanguage('en', 'English'))
        .nativeName;
  }

  void _showLanguagePicker() {
    final l = AppLocalizations.of(context);
    final current = ref.read(prefsProvider).localeTag;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: TkColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (sheetCtx) {
        Widget tile(String tag, String name) {
          final selected = tag == current;
          return InkWell(
            onTap: () async {
              Navigator.pop(sheetCtx);
              await ref
                  .read(prefsProvider.notifier)
                  .update((p) => p.copyWith(localeTag: tag));
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(name,
                        style: TextStyle(
                            fontFamily: TkFonts.sans,
                            fontSize: 16.5,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected ? TkColors.green : TkColors.ink)),
                  ),
                  if (selected)
                    const Icon(Icons.check, color: TkColors.green, size: 20),
                ],
              ),
            ),
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 14),
              Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(27, 26, 23, .15),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 26),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(l.language, style: TkText.screenTitle),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    tile('system', l.languageSystemDefault),
                    for (final lang in kAppLanguages)
                      tile(lang.tag, lang.nativeName),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final prefs = ref.watch(prefsProvider);
    final kitDate = prefs.kitSavedAt;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 170),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text(l.securityTitle, style: TkText.pageHeading),
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: TkColors.green,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                            color: TkColors.mintPale,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(l.secCovered,
                            style: TkText.sectionLabel.copyWith(
                                fontSize: 12,
                                color: const Color.fromRGBO(
                                    247, 245, 241, .85))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(l.secCoveredTitle,
                        style: const TextStyle(
                            fontFamily: TkFonts.sans,
                            fontSize: 21,
                            fontWeight: FontWeight.w600,
                            height: 1.28,
                            letterSpacing: 21 * -.01,
                            color: TkColors.paper)),
                    const SizedBox(height: 10),
                    Text(l.secCoveredBody,
                        style: TkText.body.copyWith(
                            fontSize: 14,
                            height: 1.5,
                            color:
                                const Color.fromRGBO(247, 245, 241, .82))),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
              child: TkSectionLabel(l.secLoseSection),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: TkCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l.secRecoveryKit,
                            style: const TextStyle(
                                fontFamily: TkFonts.sans,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: TkColors.ink)),
                        if (kitDate != null)
                          Text(
                              l.secSavedOn(MaterialLocalizations.of(context)
                                  .formatShortMonthDay(kitDate)),
                              style: TkText.metadata.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: TkColors.green)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(l.secRecoveryBody, style: TkText.bodySecondary),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _SmallOutlineButton(
                            label: l.secPrintAgain, onTap: _printKitAgain),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: _ComputerCard(),
            ),
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
              child: TkSectionLabel(l.secHowCodesLook),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _LayoutPicker(
                          label: l.secOnePerRow,
                          selected: prefs.layout == 'list',
                          isList: true,
                          onTap: () => ref
                              .read(prefsProvider.notifier)
                              .update((p) => p.copyWith(layout: 'list')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _LayoutPicker(
                          label: l.secTwoUp,
                          selected: prefs.layout == 'cards',
                          isList: false,
                          onTap: () => ref
                              .read(prefsProvider.notifier)
                              .update((p) => p.copyWith(layout: 'cards')),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _ToggleRow(
                    title: l.secHideCodes,
                    subtitle: l.secHideCodesSub,
                    value: prefs.hideCodes,
                    onChanged: (v) => ref
                        .read(prefsProvider.notifier)
                        .update((p) => p.copyWith(hideCodes: v)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
              child: TkSectionLabel(l.language),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: TkCard(
                onTap: _showLanguagePicker,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_currentLanguageName(prefs.localeTag),
                              style: const TextStyle(
                                  fontFamily: TkFonts.sans,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w600,
                                  color: TkColors.ink)),
                          const SizedBox(height: 3),
                          Text(l.languageSubtitle, style: TkText.metadata),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: TkColors.ink50),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
              child: TkSectionLabel(l.secOnThisPhone),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                children: [
                  if (_canAuth) ...[
                    _ToggleRow(
                      title: l.secQuickUnlock,
                      subtitle: l.secQuickUnlockSub,
                      value: prefs.biometricsEnabled,
                      onChanged: (v) async {
                        if (v) {
                          final ok = await Biometrics.prompt(l.bioConfirmTry);
                          if (!ok) return;
                        }
                        await ref
                            .read(prefsProvider.notifier)
                            .update((p) => p.copyWith(biometricsEnabled: v));
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                  _ToggleRow(
                    title: l.secCloudBackup,
                    subtitle: l.secCloudBackupSub,
                    value: prefs.encryptedBackup,
                    onChanged: (v) async {
                      await ref
                          .read(prefsProvider.notifier)
                          .update((p) => p.copyWith(encryptedBackup: v));
                      if (v) await ref.read(backupProvider.notifier).uploadNow();
                    },
                  ),
                  const SizedBox(height: 8),
                  TkCard(
                    onTap: () {
                      // Export: exit rights are non-negotiable.
                      _showExportSheet(context);
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.secMoveApp,
                            style: const TextStyle(
                                fontFamily: TkFonts.sans,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w600,
                                color: TkColors.ink)),
                        const SizedBox(height: 3),
                        Text(l.secMoveAppSub, style: TkText.metadata),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            Center(
              child: InkWell(
                onTap: () => launchUrl(
                  Uri.parse('https://purr2fa.app/privacy'),
                  mode: LaunchMode.externalApplication,
                ),
                borderRadius: BorderRadius.circular(9),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(l.secPrivacyPolicy,
                      style: TkText.metadata.copyWith(
                          fontWeight: FontWeight.w600,
                          color: TkColors.green)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showExportSheet(BuildContext context) {
    final l = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: TkColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 14, 26, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(27, 26, 23, .15),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(l.secMoveApp, style: TkText.screenTitle),
              const SizedBox(height: 10),
              Text(l.secExportBody,
                  style: TkText.body.copyWith(fontSize: 14.5)),
              const SizedBox(height: 18),
              TkPrimaryButton(
                label: l.secShowExport,
                onPressed: () async {
                  // Close the sheet first, then gate and navigate on the
                  // screen's context — the sheet context is dead after pop.
                  Navigator.pop(sheetContext);
                  final ok =
                      await Biometrics.confirmOrBypass(l.secExportReason);
                  if (!ok || !context.mounted) return;
                  _showExportQrs(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showExportQrs(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const _ExportScreen()),
    );
  }
}

/// "Your computers" card: pair browsers, see which are paired, unpair one.
/// The vault never leaves this phone — pairing only ever adds a browser that
/// may *ask* this phone for a code.
class _ComputerCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final pairings = ref.watch(pairingProvider).pairings;
    final many = pairings.length > 1;
    return TkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(many ? l.secYourComputers : l.secYourComputer,
              style: const TextStyle(
                  fontFamily: TkFonts.sans,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: TkColors.ink)),
          const SizedBox(height: 6),
          Text(
              pairings.isEmpty
                  ? l.secComputerUnpaired
                  : many
                      ? l.secComputersPaired
                      : l.secComputerPaired,
              style: TkText.bodySecondary),
          const SizedBox(height: 12),
          for (final pairing in pairings) ...[
            _PairedBrowserRow(pairing: pairing),
            const SizedBox(height: 8),
          ],
          _SmallOutlineButton(
            label: pairings.isEmpty ? l.pairScreenTitle : l.secPairAnother,
            onTap: () async {
              final ok = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                      builder: (_) => const PairComputerScreen()));
              if (ok == true && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(l.pairedSnack),
                  backgroundColor: TkColors.green,
                ));
              }
            },
          ),
          if (pairings.isNotEmpty) ...[
            const SizedBox(height: 10),
            const _PushStatusLine(),
          ],
        ],
      ),
    );
  }
}

/// One paired browser: what it calls itself, when it was paired, and the
/// unpair control. Unpairing here only affects this row.
class _PairedBrowserRow extends ConsumerWidget {
  const _PairedBrowserRow({required this.pairing});

  final StoredPairing pairing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    // Older pairings predate the browser exchanging a name; they fall back to
    // the generic label rather than showing a blank row.
    final name = pairing.browserName ?? l.secYourBrowser;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: TkColors.paperSunk,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: TkColors.ink,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.laptop, size: 17, color: TkColors.paper),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: TkFonts.sans,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: TkColors.ink)),
                Text(
                    l.secPairedOn(MaterialLocalizations.of(context)
                        .formatShortMonthDay(pairing.pairedAt.toLocal())),
                    style: TkText.metadata),
              ],
            ),
          ),
          _SmallOutlineButton(
            label: l.secUnpair,
            onTap: () => ref
                .read(pairingProvider.notifier)
                .unpair(pairing.pairingId),
          ),
        ],
      ),
    );
  }
}

/// A one-line readout of whether this phone can be woken by a push. When
/// something's off it also shows the technical reason — enough to diagnose a
/// silent failure from a single screenshot.
class _PushStatusLine extends StatefulWidget {
  const _PushStatusLine();

  @override
  State<_PushStatusLine> createState() => _PushStatusLineState();
}

class _PushStatusLineState extends State<_PushStatusLine> {
  PushDiag? _diag;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final d = await PushService.diagnose();
    if (mounted) setState(() => _diag = d);
  }

  Future<void> _enable() async {
    await PushService.requestPermission();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final d = _diag;
    final registered = d != null && d.available && d.hasToken;
    final ok = registered && d.notificationsAllowed;
    final needsPermission = registered && !d.notificationsAllowed;
    final l = AppLocalizations.of(context);
    final label = d == null
        ? l.secPushChecking
        : ok
            ? l.secPushReady
            : needsPermission
                ? l.secPushTurnOn
                : d.available
                    ? l.secPushCantRegister
                    : l.secPushUnavailable;
    final color = d == null
        ? TkColors.ink55
        : ok
            ? TkColors.green
            : const Color(0xFFB4462F);
    return GestureDetector(
      onTap: needsPermission ? _enable : _refresh,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: TkColors.paperSunk,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontFamily: TkFonts.sans,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: color)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallOutlineButton extends StatelessWidget {
  const _SmallOutlineButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          border: Border.all(color: TkColors.ink16, width: 1.5),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(label,
            style: const TextStyle(
                fontFamily: TkFonts.sans,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: TkColors.ink)),
      ),
    );
  }
}

class _LayoutPicker extends StatelessWidget {
  const _LayoutPicker({
    required this.label,
    required this.selected,
    required this.isList,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool isList;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = selected ? TkColors.green : TkColors.ink;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: TkMotion.feedback,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(
          color: TkColors.surface,
          border: Border.all(
            color: selected ? TkColors.green : const Color.fromRGBO(27, 26, 23, .08),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(TkRadius.card),
        ),
        foregroundDecoration: selected
            ? BoxDecoration(
                border: Border.all(color: TkColors.green),
                borderRadius: BorderRadius.circular(TkRadius.card),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isList)
              Column(
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    Container(
                      height: 11,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: .22),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    if (i < 2) const SizedBox(height: 5),
                  ],
                ],
              )
            else
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 5,
                crossAxisSpacing: 5,
                childAspectRatio: 3.4,
                children: [
                  for (var i = 0; i < 4; i++)
                    Container(
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: .22),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 12),
            Text(label,
                style: TextStyle(
                    fontFamily: TkFonts.sans,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: selected ? TkColors.green : TkColors.ink)),
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return TkCard(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontFamily: TkFonts.sans,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        color: TkColors.ink)),
                const SizedBox(height: 2),
                Text(subtitle, style: TkText.metadata),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: TkColors.green,
            activeThumbColor: TkColors.surface,
            inactiveTrackColor: TkColors.ink16,
            inactiveThumbColor: TkColors.surface,
          ),
        ],
      ),
    );
  }
}

/// Export screen: one QR per account (otpauth:// URI). FLAG_SECURE blocks
/// screenshots; the QRs are for another device's camera.
class _ExportScreen extends ConsumerWidget {
  const _ExportScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final accounts = ref.watch(vaultProvider).accounts;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: TkColors.paper,
        elevation: 0,
        leading: const BackButton(color: TkColors.ink),
        title: Text(l.secExportScreenTitle,
            style: const TextStyle(
                fontFamily: TkFonts.sans,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: TkColors.ink)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 40),
        children: [
          Text(l.secExportScanEach,
              style: TkText.body.copyWith(fontSize: 14.5)),
          const SizedBox(height: 18),
          for (final account in accounts) ...[
            _ExportCard(account: account),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _ExportCard extends StatelessWidget {
  const _ExportCard({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final uri = buildOtpauthUri(ParsedOtpEntry(
      secret: account.secret,
      issuer: account.siteName,
      accountName: account.username,
      digits: account.digits,
      period: account.period,
      algorithm: account.algorithm,
      type: account.type,
      counter: account.counter,
    ));
    return TkCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(account.siteName,
                    style: const TextStyle(
                        fontFamily: TkFonts.sans,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: TkColors.ink)),
                if (account.username.isNotEmpty)
                  Text(account.username, style: TkText.metadata),
              ],
            ),
          ),
          const SizedBox(width: 14),
          QrImageView(
            data: uri,
            size: 120,
            backgroundColor: TkColors.surface,
            eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square, color: TkColors.ink),
            dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: TkColors.ink),
          ),
        ],
      ),
    );
  }
}
