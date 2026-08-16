import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../l10n/app_localizations.dart';
import '../../design/tokens.dart';
import '../../services/approval_service.dart';

/// Security → Pair a computer: scan the QR the extension shows (B1 step 2).
class PairComputerScreen extends ConsumerStatefulWidget {
  const PairComputerScreen({super.key});

  @override
  ConsumerState<PairComputerScreen> createState() =>
      _PairComputerScreenState();
}

class _PairComputerScreenState extends ConsumerState<PairComputerScreen> {
  final _controller =
      MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool _handled = false;
  String? _status;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The QR is text; pasting it works from anywhere the person can copy it
  /// (remote desktops, a second monitor photo, accessibility tools).
  Future<void> _pasteInstead() async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController();
    final pasted = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: TkColors.paper,
        title: Text(l.pairPasteTitle,
            style: const TextStyle(
                fontFamily: TkFonts.sans,
                fontSize: 19,
                fontWeight: FontWeight.w600)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          style: const TextStyle(fontFamily: TkFonts.mono, fontSize: 12),
          decoration: const InputDecoration(hintText: 'purr-pair:…'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel, style: const TextStyle(color: TkColors.ink50)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l.pairAction, style: const TextStyle(color: TkColors.green)),
          ),
        ],
      ),
    );
    if (pasted == null || pasted.isEmpty) return;
    await _complete(pasted);
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || !raw.startsWith('purr-pair:')) return;
    _handled = true;
    await _complete(raw);
  }

  Future<void> _complete(String qrPayload) async {
    setState(() => _status = AppLocalizations.of(context).pairLinking);
    try {
      await ref.read(pairingServiceProvider).completeFromQr(qrPayload);
      await ref.read(pairingProvider.notifier).refresh();
      // Notifications priming (5d) belongs at "first account AND paired" —
      // the moment a push has something to say. Handled by the caller.
      if (mounted) Navigator.of(context).pop(true);
    } on FormatException catch (e) {
      setState(() {
        _handled = false;
        _status = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _handled = false;
        _status = AppLocalizations.of(context).pairUnreachable;
      });
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
                    onTap: () => Navigator.of(context).pop(false),
                    child: Text(l.cancel,
                        style: TkText.secondaryButton.copyWith(
                            fontSize: 15,
                            color:
                                const Color.fromRGBO(247, 245, 241, .6))),
                  ),
                  Expanded(
                    child: Text(l.pairScreenTitle,
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
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: MobileScanner(
                        controller: _controller, onDetect: _onDetect),
                  ),
                ),
              ),
            ),
            Text(l.pairHoldSquare,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: TkFonts.sans,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: TkColors.paper)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 38),
              child: Text(
                  _status ?? l.pairWhereHint,
                  textAlign: TextAlign.center,
                  style: TkText.bodySecondary.copyWith(
                      color: const Color.fromRGBO(247, 245, 241, .55))),
            ),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: _pasteInstead,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(l.pairCantScan,
                    style: TkText.secondaryButton.copyWith(
                        fontSize: 14.5,
                        color: const Color.fromRGBO(247, 245, 241, .7))),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
