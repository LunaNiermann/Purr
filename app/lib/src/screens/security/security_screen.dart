import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/otpauth.dart';
import '../../crypto/recovery.dart';
import '../../data/models.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../services/approval_service.dart';
import '../../services/backup_service.dart';
import '../../services/biometrics.dart';
import '../../services/kit_pdf.dart';
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
    final ok = await Biometrics.confirmOrBypass('Confirm to view your recovery kit');
    if (!ok) return;
    final meta = await ref.read(vaultStoreProvider).kitMeta();
    if (meta == null || !mounted) return;
    final entropy = meta['entropyB64'] as String?;
    if (entropy == null) return;
    final kit = RecoveryKit.fromEntropyB64(entropy);
    final count = ref.read(vaultProvider).accounts.length;
    await printRecoveryKit(kit: kit, accountCount: count);
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(prefsProvider);
    final kitDate = prefs.kitSavedAt;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 170),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 22),
              child: Text('Security', style: TkText.pageHeading),
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
                        Text("YOU'RE COVERED",
                            style: TkText.sectionLabel.copyWith(
                                fontSize: 12,
                                color: const Color.fromRGBO(
                                    247, 245, 241, .85))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('Your two factors live on two separate devices.',
                        style: TextStyle(
                            fontFamily: TkFonts.sans,
                            fontSize: 21,
                            fontWeight: FontWeight.w600,
                            height: 1.28,
                            letterSpacing: 21 * -.01,
                            color: TkColors.paper)),
                    const SizedBox(height: 10),
                    Text(
                        "If someone steals your laptop, they still can't get "
                        "in. They'd need this phone too.",
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
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 0, 22, 8),
              child: TkSectionLabel('If you lose this phone'),
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
                        const Text('Recovery kit',
                            style: TextStyle(
                                fontFamily: TkFonts.sans,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: TkColors.ink)),
                        if (kitDate != null)
                          Text('Saved ${_shortDate(kitDate)}',
                              style: TkText.metadata.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: TkColors.green)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                        'One sheet of paper that can bring everything back, '
                        'even if you lose every device. Print another copy '
                        'any time.',
                        style: TkText.bodySecondary),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _SmallOutlineButton(
                            label: 'Print again', onTap: _printKitAgain),
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
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 0, 22, 8),
              child: TkSectionLabel('How your codes look'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _LayoutPicker(
                          label: 'One per row',
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
                          label: 'Two-up cards',
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
                    title: 'Hide codes until tapped',
                    subtitle: 'Good for cafés and open offices',
                    value: prefs.hideCodes,
                    onChanged: (v) => ref
                        .read(prefsProvider.notifier)
                        .update((p) => p.copyWith(hideCodes: v)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 0, 22, 8),
              child: TkSectionLabel('On this phone'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                children: [
                  if (_canAuth) ...[
                    _ToggleRow(
                      title: 'Quick unlock',
                      subtitle: 'Open Purr with your fingerprint, face, or '
                          "screen lock — it's not your second factor",
                      value: prefs.biometricsEnabled,
                      onChanged: (v) async {
                        if (v) {
                          final ok = await Biometrics.prompt(
                              'Confirm it works — one try now');
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
                    title: 'Cloud backup',
                    subtitle: 'An encrypted copy only your recovery kit can '
                        'open — how a new phone gets your codes back',
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
                        const Text('Move to another app',
                            style: TextStyle(
                                fontFamily: TkFonts.sans,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w600,
                                color: TkColors.ink)),
                        const SizedBox(height: 3),
                        Text(
                            'Your codes are yours. Take them anywhere, '
                            'any time.',
                            style: TkText.metadata),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showExportSheet(BuildContext context) {
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
              const Text('Move to another app',
                  style: TkText.screenTitle),
              const SizedBox(height: 10),
              Text(
                  'This shows every account as a QR code the other app can '
                  'scan — the same kind you scanned to get them in here. '
                  "You'll confirm it's you first.",
                  style: TkText.body.copyWith(fontSize: 14.5)),
              const SizedBox(height: 18),
              TkPrimaryButton(
                label: 'Show my export codes',
                onPressed: () async {
                  // Close the sheet first, then gate and navigate on the
                  // screen's context — the sheet context is dead after pop.
                  Navigator.pop(sheetContext);
                  final ok = await Biometrics.confirmOrBypass(
                      'Confirm to export your accounts');
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

  static String _shortDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }
}

/// "Your computer" card: pair, show, or unpair the browser extension.
class _ComputerCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pairing = ref.watch(pairingProvider);
    final paired = pairing.pairing;
    return TkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Your computer',
              style: TextStyle(
                  fontFamily: TkFonts.sans,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: TkColors.ink)),
          const SizedBox(height: 6),
          Text(
              paired == null
                  ? 'Pair the browser extension and signing in on your '
                      'computer becomes one tap here.'
                  : 'When a site asks your browser for a code, this phone '
                      'gets the request.',
              style: TkText.bodySecondary),
          const SizedBox(height: 12),
          if (paired == null)
            _SmallOutlineButton(
              label: 'Pair a computer',
              onTap: () async {
                final ok = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                        builder: (_) => const PairComputerScreen()));
                if (ok == true && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Paired. Try a sign-in on your computer.'),
                    backgroundColor: TkColors.green,
                  ));
                }
              },
            )
          else
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                    child: const Icon(Icons.laptop,
                        size: 17, color: TkColors.paper),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Your browser',
                            style: TextStyle(
                                fontFamily: TkFonts.sans,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: TkColors.ink)),
                        Text('Paired ${_shortDate(paired.pairedAt.toLocal())}',
                            style: TkText.metadata),
                      ],
                    ),
                  ),
                  _SmallOutlineButton(
                    label: 'Unpair',
                    onTap: () =>
                        ref.read(pairingProvider.notifier).unpair(),
                  ),
                ],
              ),
            ),
          if (paired != null) ...[
            const SizedBox(height: 10),
            const _PushStatusLine(),
          ],
        ],
      ),
    );
  }

  static String _shortDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
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
    final label = d == null
        ? 'Checking notifications…'
        : ok
            ? 'Notifications ready'
            : needsPermission
                ? 'Turn on notifications to be alerted'
                : d.available
                    ? "Notifications on, but this phone couldn't register"
                    : 'Notifications unavailable on this device';
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
    final accounts = ref.watch(vaultProvider).accounts;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: TkColors.paper,
        elevation: 0,
        leading: const BackButton(color: TkColors.ink),
        title: const Text('Your export codes',
            style: TextStyle(
                fontFamily: TkFonts.sans,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: TkColors.ink)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 40),
        children: [
          Text(
              'Scan each square with your new app. Every account moves over '
              'with nothing lost.',
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
