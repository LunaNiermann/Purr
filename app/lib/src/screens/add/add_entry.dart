import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/base32.dart';
import '../../core/migration.dart';
import '../../core/otpauth.dart';
import '../../core/totp.dart';
import '../../data/models.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../services/approval_service.dart';
import '../../state/providers.dart';

/// Entry point for adding accounts. The camera permission follows the design
/// rule: never ask cold, prime first (5a), never render a look-alike system
/// dialog, and denial never blocks adding an account (5c).
Future<void> startAddEntry(BuildContext context, WidgetRef ref,
    {bool scan = true}) async {
  if (!scan) {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ManualEntryScreen()));
    return;
  }

  // If the camera is already granted, there's no system prompt coming — so
  // the priming sheet (whose only job is to precede that prompt) is just noise.
  // Go straight to the scanner. (First-time / not-yet-granted still primes.)
  final alreadyGranted = await Permission.camera.status.isGranted;
  if (!context.mounted) return;
  if (alreadyGranted) {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ScanScreen()));
    return;
  }

  // Priming sheet (5a) as a bottom sheet over the vault.
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: TkColors.surface,
    barrierColor: const Color.fromRGBO(27, 26, 23, .32),
    isScrollControlled: true, // grow to fit content; don't clip the lower button
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
    builder: (context) {
      final l = AppLocalizations.of(context);
      return SafeArea(
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
              const _CameraGlyph(color: TkColors.green),
              const SizedBox(height: 20),
              Text(l.addCameraTitle, style: TkText.screenTitle),
              const SizedBox(height: 10),
              Text(
                l.addCameraBody,
                style: TkText.body.copyWith(fontSize: 15),
              ),
              const SizedBox(height: 22),
              TkPrimaryButton(
                label: l.addCameraOk,
                onPressed: () => Navigator.pop(context, 'scan'),
              ),
              const SizedBox(height: 10),
              TkSecondaryButton(
                label: l.addTypeByHand,
                onPressed: () => Navigator.pop(context, 'manual'),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (!context.mounted) return;
  if (choice == 'manual') {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ManualEntryScreen()));
  } else if (choice == 'scan') {
    // mobile_scanner triggers the real system permission dialog on first use.
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ScanScreen()));
  }
}

class _CameraGlyph extends StatelessWidget {
  const _CameraGlyph({required this.color, this.slashed = false});

  final Color color;
  final bool slashed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 2.5),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 2.5),
              shape: BoxShape.circle,
            ),
          ),
          if (slashed)
            Transform.rotate(
              angle: -.49,
              child: Container(width: 68, height: 2.5, color: color),
            ),
        ],
      ),
    );
  }
}

/// A17 (4f): the dark scan screen with mint corner brackets.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _controller = MobileScannerController(
    formats: [BarcodeFormat.qrCode],
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    // Someone pointed the "add account" scanner at a computer-pairing code.
    // Don't fail silently — offer to pair instead.
    if (raw.startsWith('purr-pair:')) {
      _handled = true;
      await _handlePairingCode(raw);
      return;
    }

    if (raw.startsWith('otpauth-migration://')) {
      _handled = true;
      try {
        final batch = parseMigrationUri(raw);
        if (!mounted) return;
        await Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => ImportReviewScreen(batch: batch)));
      } on FormatException catch (e) {
        _showError(e.message);
      }
      return;
    }
    if (raw.startsWith('otpauth://')) {
      _handled = true;
      try {
        final parsed = parseOtpauthUri(raw);
        if (!mounted) return;
        await Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => ManualEntryScreen(prefill: parsed)));
      } on FormatException catch (e) {
        _showError(e.message);
      }
    }
  }

  void _showError(String message) {
    _handled = false;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(AppLocalizations.of(context).scanCodeError(message)),
      backgroundColor: TkColors.ink,
    ));
  }

  /// A pairing QR scanned in the account scanner: confirm, then pair.
  Future<void> _handlePairingCode(String raw) async {
    final l = AppLocalizations.of(context);
    final pair = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: TkColors.paper,
        title: Text(l.pairTitle,
            style: const TextStyle(
                fontFamily: TkFonts.sans,
                fontSize: 19,
                fontWeight: FontWeight.w600)),
        content: Text(
          l.pairBody,
          style: TkText.body.copyWith(fontSize: 14.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.notNow, style: const TextStyle(color: TkColors.ink50)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.pairAction, style: const TextStyle(color: TkColors.green)),
          ),
        ],
      ),
    );
    if (pair != true) {
      _handled = false; // let them keep scanning for an account code
      return;
    }
    try {
      await ref.read(pairingServiceProvider).completeFromQr(raw);
      await ref.read(pairingProvider.notifier).refresh();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.pairedSnack),
        backgroundColor: TkColors.green,
      ));
    } on FormatException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError(l.pairServiceUnreachable);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: TkColors.inkDarkest,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Text(l.cancel,
                        style: TkText.secondaryButton.copyWith(
                            fontSize: 15,
                            color:
                                const Color.fromRGBO(247, 245, 241, .6))),
                  ),
                  Expanded(
                    child: Text(l.addAccountTitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontFamily: TkFonts.sans,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: TkColors.paper)),
                  ),
                  const SizedBox(width: 52),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: SizedBox(
                  width: 244,
                  height: 244,
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: MobileScanner(
                          controller: _controller,
                          onDetect: _onDetect,
                          errorBuilder: (context, error) =>
                              _CameraDenied(error: error),
                        ),
                      ),
                      ..._corners(),
                    ],
                  ),
                ),
              ),
            ),
            Text(l.scanHoldInside,
                style: const TextStyle(
                    fontFamily: TkFonts.sans,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: TkColors.paper)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 38),
              child: Text(
                l.scanWhereHint,
                textAlign: TextAlign.center,
                style: TkText.bodySecondary.copyWith(
                    color: const Color.fromRGBO(247, 245, 241, .55)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
              child: TkSecondaryButton(
                label: l.scanTypeInstead,
                borderColor: TkColors.paper20,
                foreground: TkColors.paper,
                onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                        builder: (_) => const ManualEntryScreen())),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _corners() {
    Widget corner({required Alignment alignment}) {
      final isTop = alignment.y < 0;
      final isLeft = alignment.x < 0;
      return Align(
        alignment: alignment,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            border: Border(
              top: isTop
                  ? const BorderSide(color: TkColors.mint, width: 3)
                  : BorderSide.none,
              bottom: !isTop
                  ? const BorderSide(color: TkColors.mint, width: 3)
                  : BorderSide.none,
              left: isLeft
                  ? const BorderSide(color: TkColors.mint, width: 3)
                  : BorderSide.none,
              right: !isLeft
                  ? const BorderSide(color: TkColors.mint, width: 3)
                  : BorderSide.none,
            ),
            borderRadius: BorderRadius.only(
              topLeft: isTop && isLeft
                  ? const Radius.circular(20)
                  : Radius.zero,
              topRight: isTop && !isLeft
                  ? const Radius.circular(20)
                  : Radius.zero,
              bottomLeft: !isTop && isLeft
                  ? const Radius.circular(20)
                  : Radius.zero,
              bottomRight: !isTop && !isLeft
                  ? const Radius.circular(20)
                  : Radius.zero,
            ),
          ),
        ),
      );
    }

    return [
      corner(alignment: Alignment.topLeft),
      corner(alignment: Alignment.topRight),
      corner(alignment: Alignment.bottomLeft),
      corner(alignment: Alignment.bottomRight),
    ];
  }
}

/// 5c: camera denied — the job is still finishable.
class _CameraDenied extends StatelessWidget {
  const _CameraDenied({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (error.errorCode != MobileScannerErrorCode.permissionDenied) {
      return ColoredBox(
        color: TkColors.inkDarkest,
        child: Center(
          child: Text(l.cameraUnavailable,
              textAlign: TextAlign.center,
              style: TkText.bodySecondary.copyWith(
                  color: const Color.fromRGBO(247, 245, 241, .55))),
        ),
      );
    }
    return ColoredBox(
      color: TkColors.inkDarkest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const _CameraGlyph(
                color: Color.fromRGBO(247, 245, 241, .5), slashed: true),
            const SizedBox(height: 14),
            Text(
              l.cameraDeniedBody,
              textAlign: TextAlign.center,
              style: TkText.bodySecondary.copyWith(
                  color: const Color.fromRGBO(247, 245, 241, .65)),
            ),
          ],
        ),
      ),
    );
  }
}

/// A18 (4g): manual entry with live "That code works" confirmation.
class ManualEntryScreen extends ConsumerStatefulWidget {
  const ManualEntryScreen({super.key, this.prefill});

  final ParsedOtpEntry? prefill;

  @override
  ConsumerState<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends ConsumerState<ManualEntryScreen> {
  late final TextEditingController _site;
  late final TextEditingController _username;
  late final TextEditingController _secret;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.prefill;
    _site = TextEditingController(text: p?.issuer ?? '');
    _username = TextEditingController(text: p?.accountName ?? '');
    _secret = TextEditingController(
        text: p == null ? '' : base32Encode(p.secret));
  }

  @override
  void dispose() {
    _site.dispose();
    _username.dispose();
    _secret.dispose();
    super.dispose();
  }

  Totp? get _preview {
    final cleaned = _secret.text;
    if (!looksLikeBase32Secret(cleaned)) return null;
    try {
      final p = widget.prefill;
      return Totp(
        secret: base32Decode(cleaned),
        digits: p?.digits ?? 6,
        period: p?.period ?? 30,
        algorithm: p?.algorithm ?? TotpAlgorithm.sha1,
      );
    } on FormatException {
      return null;
    }
  }

  Future<void> _save() async {
    final totp = _preview;
    if (totp == null || _saving) return;
    setState(() => _saving = true);
    final p = widget.prefill;
    final siteRaw = _site.text.trim();
    final site = siteRaw.isEmpty
        ? AppLocalizations.of(context).defaultAccountName
        : siteRaw;
    final username = _username.text.trim();

    // Never silently overwrite on collision (the Microsoft lesson): an
    // identical site+username gets a numbered name instead.
    final existing = ref.read(vaultProvider).accounts;
    var finalSite = site;
    var n = 2;
    while (existing.any((a) =>
        a.siteName.toLowerCase() == finalSite.toLowerCase() &&
        a.username.toLowerCase() == username.toLowerCase())) {
      finalSite = '$site ($n)';
      n++;
    }

    final account = Account(
      id: UniqueKey().toString() +
          DateTime.now().microsecondsSinceEpoch.toString(),
      siteName: finalSite,
      username: username,
      secretB32: base32Encode(base32Decode(_secret.text)),
      digits: p?.digits ?? 6,
      period: p?.period ?? 30,
      algorithm: p?.algorithm ?? TotpAlgorithm.sha1,
      type: p?.type ?? 'totp',
      counter: p?.counter,
      createdAt: DateTime.now().toUtc(),
    );
    await ref.read(vaultProvider.notifier).mutate((data) => VaultData(
          accounts: [...data.accounts, account],
          mutedSites: data.mutedSites,
        ));
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final preview = _preview;
    final site = _site.text.trim();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: TkColors.paper,
        elevation: 0,
        leading: const BackButton(color: TkColors.ink),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(l.manualTitle, style: TkText.screenTitle),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: ListView(
                  children: [
                    _LabeledField(
                        label: l.manualSite,
                        controller: _site,
                        onChanged: () => setState(() {})),
                    const SizedBox(height: 12),
                    _LabeledField(
                        label: l.manualUsername,
                        controller: _username,
                        onChanged: () => setState(() {})),
                    const SizedBox(height: 12),
                    _LabeledField(
                      label: l.manualSecret,
                      controller: _secret,
                      mono: true,
                      active: true,
                      helper: l.manualSecretHelper,
                      onChanged: () => setState(() {}),
                    ),
                    const SizedBox(height: 18),
                    AnimatedSwitcher(
                      duration: TkMotion.feedback,
                      child: preview == null
                          ? const SizedBox.shrink()
                          : Container(
                              key: const ValueKey('works'),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 15),
                              decoration: BoxDecoration(
                                color: TkColors.greenPale,
                                borderRadius: BorderRadius.circular(
                                    TkRadius.panel),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 26,
                                    height: 26,
                                    decoration: const BoxDecoration(
                                      color: TkColors.green,
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: const Text('✓',
                                        style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: TkColors.paper)),
                                  ),
                                  const SizedBox(width: 13),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(l.codeWorks,
                                            style: const TextStyle(
                                                fontFamily: TkFonts.sans,
                                                fontSize: 14.5,
                                                fontWeight: FontWeight.w600,
                                                color: TkColors.greenDeep)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              TkPrimaryButton(
                label: site.isEmpty ? l.saveLabel : l.saveNamed(site),
                enabled: preview != null && !_saving,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.mono = false,
    this.active = false,
    this.helper,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final bool mono;
  final bool active;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: TkSectionLabel(label),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: TkColors.surface,
            border: Border.all(
              color: active && controller.text.isNotEmpty
                  ? TkColors.green
                  : TkColors.ink10,
              width: active && controller.text.isNotEmpty ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(TkRadius.field),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: TextField(
            controller: controller,
            onChanged: (_) => onChanged(),
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: mono
                ? TextCapitalization.characters
                : TextCapitalization.none,
            style: mono
                ? const TextStyle(
                    fontFamily: TkFonts.mono,
                    fontSize: 15,
                    letterSpacing: 15 * .08,
                    height: 1.5)
                : const TextStyle(fontFamily: TkFonts.sans, fontSize: 16),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        if (helper != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(helper!, style: TkText.metadata),
          ),
        ],
      ],
    );
  }
}

/// Import review for otpauth-migration batches: every row reported, nothing
/// silently dropped (research commandment 4).
class ImportReviewScreen extends ConsumerStatefulWidget {
  const ImportReviewScreen({super.key, required this.batch});

  final MigrationBatch batch;

  @override
  ConsumerState<ImportReviewScreen> createState() =>
      _ImportReviewScreenState();
}

class _ImportReviewScreenState extends ConsumerState<ImportReviewScreen> {
  bool _saving = false;

  Future<void> _import() async {
    if (_saving) return;
    setState(() => _saving = true);
    final existing = ref.read(vaultProvider).accounts;
    final added = <Account>[];
    for (final entry in widget.batch.entries) {
      var site = entry.issuer.isNotEmpty ? entry.issuer : entry.accountName;
      if (site.isEmpty) site = AppLocalizations.of(context).importedAccountName;
      final username = entry.issuer.isNotEmpty ? entry.accountName : '';
      var finalSite = site;
      var n = 2;
      bool clashes(String name) =>
          existing.any((a) =>
              a.siteName.toLowerCase() == name.toLowerCase() &&
              a.username.toLowerCase() == username.toLowerCase()) ||
          added.any((a) =>
              a.siteName.toLowerCase() == name.toLowerCase() &&
              a.username.toLowerCase() == username.toLowerCase());
      while (clashes(finalSite)) {
        finalSite = '$site ($n)';
        n++;
      }
      added.add(Account(
        id: UniqueKey().toString() +
            DateTime.now().microsecondsSinceEpoch.toString() +
            added.length.toString(),
        siteName: finalSite,
        username: username,
        secretB32: base32Encode(entry.secret),
        digits: entry.digits,
        period: entry.period,
        algorithm: entry.algorithm,
        type: entry.type,
        counter: entry.counter,
        createdAt: DateTime.now().toUtc(),
      ));
    }
    await ref.read(vaultProvider.notifier).mutate((data) => VaultData(
          accounts: [...data.accounts, ...added],
          mutedSites: data.mutedSites,
        ));
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final entries = widget.batch.entries;
    final multi = widget.batch.batchSize > 1;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: TkColors.paper,
        elevation: 0,
        leading: const BackButton(color: TkColors.ink),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.importReadyCount(entries.length),
                  style: TkText.screenTitle),
              const SizedBox(height: 10),
              Text(
                  multi
                      ? l.importPartOf(widget.batch.batchIndex + 1,
                          widget.batch.batchSize)
                      : l.importAllComeAcross,
                  style: TkText.body.copyWith(fontSize: 14.5)),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    final site =
                        e.issuer.isNotEmpty ? e.issuer : e.accountName;
                    return TkCard(
                      child: Row(
                        children: [
                          TkAvatarTile(
                              letter: site.isEmpty
                                  ? '?'
                                  : site[0].toUpperCase(),
                              color: brandColorFor(site)),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(site.isEmpty ? l.unnamedAccount : site,
                                    style: const TextStyle(
                                        fontFamily: TkFonts.sans,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: TkColors.ink)),
                                if (e.accountName.isNotEmpty &&
                                    e.issuer.isNotEmpty)
                                  Text(e.accountName,
                                      style: TkText.metadata),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              TkPrimaryButton(
                label: entries.length == 1
                    ? l.importBringOne
                    : l.importBringAll(entries.length),
                enabled: !_saving,
                onPressed: _import,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
