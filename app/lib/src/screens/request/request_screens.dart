import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/totp.dart';
import '../../data/models.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../services/approval_service.dart';
import '../../services/biometrics.dart';
import '../../services/platform.dart';
import '../../state/providers.dart';

/// A11–A15: the full-screen approval flow. Triggered by the extension, so
/// the language is about the browser wanting something.
class ApprovalFlowScreen extends ConsumerStatefulWidget {
  const ApprovalFlowScreen({super.key, required this.request});

  final PendingApproval request;

  @override
  ConsumerState<ApprovalFlowScreen> createState() =>
      _ApprovalFlowScreenState();
}

enum _Phase { request, bio, done, denied, codeOnly }

class _ApprovalFlowScreenState extends ConsumerState<ApprovalFlowScreen> {
  _Phase _phase = _Phase.request;
  Account? _account;
  Timer? _expiry;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _account = _matchAccount();
    final remaining =
        widget.request.expiresAt.difference(DateTime.now());
    _expiry = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      // Request timed out: the design says the phone's screen dismisses.
      if (mounted && (_phase == _Phase.request || _phase == _Phase.bio)) {
        ref.read(approvalProvider.notifier).dismissSilently();
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }

  String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  Account? _matchAccount() {
    final accounts = ref.read(vaultProvider).accounts;
    final domain = widget.request.domain;
    final base = _norm(domain.split('.').length > 1
        ? domain.split('.')[domain.split('.').length - 2]
        : domain);
    for (final account in accounts) {
      final site = _norm(account.siteName);
      if (site.isNotEmpty && (site == base || base.contains(site) || site.contains(base))) {
        return account;
      }
    }
    return null;
  }

  Future<void> _approve() async {
    final account = _account;
    if (account == null) return;
    setState(() => _phase = _Phase.bio);
    // confirmOrBypass, not prompt: on a device with no lock enrolled there is
    // nothing to authenticate against, and prompt() returns false there — which
    // would silently bounce back to the request screen and make "Send the code"
    // look dead. With a lock, it still prompts.
    final ok = await Biometrics.confirmOrBypass(
        AppLocalizations.of(context).confirmingItsYou);
    if (!ok) {
      if (mounted) setState(() => _phase = _Phase.request);
      return;
    }
    final sent = await ref
        .read(approvalProvider.notifier)
        .approve(widget.request, account);
    if (!mounted) return;
    if (sent) {
      setState(() => _phase = _Phase.done);
    } else {
      // Expired under us — the desktop shows its own expired popup.
      Navigator.of(context).pop();
    }
  }

  Future<void> _deny() async {
    await ref.read(approvalProvider.notifier).deny(widget.request);
    if (mounted) setState(() => _phase = _Phase.denied);
  }

  void _showCode() {
    ref.read(approvalProvider.notifier).dismissSilently();
    setState(() => _phase = _Phase.codeOnly);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: switch (_phase) {
        _Phase.request => _buildRequest(),
        _Phase.bio => _buildBio(),
        _Phase.done => _buildDone(),
        _Phase.denied => _buildDenied(),
        _Phase.codeOnly => _buildCodeOnly(),
      },
    );
  }

  // ---- A11 ----------------------------------------------------------------

  Widget _buildRequest() {
    final l = AppLocalizations.of(context);
    final request = widget.request;
    final account = _account;
    final secondsAgo =
        DateTime.now().difference(request.askedAt).inSeconds.clamp(0, 599);
    return Scaffold(
      body: TkRiseIn(
        child: Container(
          decoration: const BoxDecoration(gradient: TkColors.inkGradient),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, TkSpace.bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                TkAvatarTile(
                                  letter: request.domain.isEmpty
                                      ? '?'
                                      : request.domain[0].toUpperCase(),
                                  color: TkColors.paper,
                                  size: 56,
                                ),
                                const SizedBox(width: 14),
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(l.approvalWaiting,
                                        style: TkText.bodySecondary.copyWith(
                                            fontSize: 13,
                                            color: TkColors.paper55)),
                                    Text(request.domain,
                                        style: const TextStyle(
                                            fontFamily: TkFonts.sans,
                                            fontSize: 22,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 22 * -.01,
                                            color: TkColors.paper)),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 26),
                            Text(l.approvalAsk,
                                style: const TextStyle(
                                    fontFamily: TkFonts.sans,
                                    fontSize: 30,
                                    fontWeight: FontWeight.w600,
                                    height: 1.2,
                                    letterSpacing: 30 * -.025,
                                    color: TkColors.paper)),
                            const SizedBox(height: 26),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 16),
                              decoration: BoxDecoration(
                                color:
                                    const Color.fromRGBO(247, 245, 241, .06),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Column(
                                children: [
                                  _detailRow(
                                      l.detailAccount,
                                      account == null
                                          ? l.approvalPickBelow
                                          : (account.username.isEmpty
                                              ? account.siteName
                                              : account.username)),
                                  const SizedBox(height: 10),
                                  _detailRow(l.detailBrowser, request.browser),
                                  const SizedBox(height: 10),
                                  _detailRow(
                                      l.detailAsked,
                                      secondsAgo < 5
                                          ? l.justNow
                                          : l.secondsAgo(secondsAgo)),
                                ],
                              ),
                            ),
                            if (account == null) ...[
                              const SizedBox(height: 16),
                              Text(
                                  l.approvalWhichAccount(request.domain),
                                  style: TkText.bodySecondary.copyWith(
                                      color: TkColors.paper55)),
                              const SizedBox(height: 10),
                              for (final a
                                  in ref.watch(vaultProvider).accounts) ...[
                                _accountPick(a),
                                const SizedBox(height: 8),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TkPrimaryButton(
                    label: l.sendTheCode,
                    background: TkColors.greenBright,
                    foreground: TkColors.onGreenBrightText,
                    enabled: account != null,
                    onPressed: _approve,
                  ),
                  const SizedBox(height: 10),
                  TkSecondaryButton(
                    label: l.didntAskForThis,
                    borderColor: TkColors.paper20,
                    foreground: const Color.fromRGBO(247, 245, 241, .8),
                    onPressed: _deny,
                  ),
                  TkTextButton(
                    label: l.justShowCode,
                    color: const Color.fromRGBO(247, 245, 241, .7),
                    onPressed: account == null ? null : _showCode,
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                        l.onlySixDigitsTravel,
                        textAlign: TextAlign.center,
                        style: TkText.metadata.copyWith(
                            fontSize: 12.5,
                            color:
                                const Color.fromRGBO(247, 245, 241, .45))),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _accountPick(Account account) {
    final selected = _account?.id == account.id;
    return GestureDetector(
      onTap: () => setState(() => _account = account),
      child: AnimatedContainer(
        duration: TkMotion.feedback,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: selected
              ? const Color.fromRGBO(127, 209, 172, .14)
              : const Color.fromRGBO(247, 245, 241, .05),
          border: Border.all(
              color: selected ? TkColors.mint : TkColors.paper20,
              width: selected ? 1.5 : 1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            TkAvatarTile(
                letter: account.siteName.isEmpty
                    ? '?'
                    : account.siteName[0].toUpperCase(),
                color: brandColorFor(account.siteName),
                size: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(account.siteName,
                      style: const TextStyle(
                          fontFamily: TkFonts.sans,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: TkColors.paper)),
                  if (account.username.isNotEmpty)
                    Text(account.username,
                        style: TkText.metadata
                            .copyWith(color: TkColors.paper55)),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle,
                  size: 18, color: TkColors.mint),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TkText.body.copyWith(
                fontSize: 14,
                color: const Color.fromRGBO(247, 245, 241, .47))),
        const SizedBox(width: 12),
        Flexible(
          child: Text(value,
              textAlign: TextAlign.right,
              style: TkText.body.copyWith(
                  fontSize: 14, height: 1.5, color: TkColors.paper)),
        ),
      ],
    );
  }

  // ---- A13 ----------------------------------------------------------------

  Widget _buildBio() {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: TkColors.inkGradient),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            color: const Color.fromRGBO(20, 19, 17, .55),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TkPulseRing(
                    size: 96,
                    borderRadius: BorderRadius.circular(28),
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        border: Border.all(
                            color:
                                const Color.fromRGBO(127, 209, 172, .55),
                            width: 2),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: const Icon(Icons.fingerprint,
                          size: 42, color: TkColors.mint),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(AppLocalizations.of(context).proveItsYou,
                      style: const TextStyle(
                          fontFamily: TkFonts.sans,
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                          color: TkColors.paper)),
                  const SizedBox(height: 6),
                  Text(AppLocalizations.of(context).confirmingItsYou,
                      style: TkText.body.copyWith(
                          fontSize: 14, color: TkColors.paper55)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---- A14 ----------------------------------------------------------------

  Widget _buildDone() {
    return Scaffold(
      backgroundColor: TkColors.green,
      body: TkRiseIn(
        duration: TkMotion.riseInFast,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 24, 26, TkSpace.bottom),
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
                          width: 64,
                          height: 64,
                          decoration: const BoxDecoration(
                              color: TkColors.mintPale,
                              shape: BoxShape.circle),
                          alignment: Alignment.center,
                          child: const Text('✓',
                              style: TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w700,
                                  color: TkColors.greenDeep)),
                        ),
                        const SizedBox(height: 20),
                        Text(AppLocalizations.of(context).youreIn,
                            style: TkText.heroTitle
                                .copyWith(fontSize: 32, color: TkColors.paper)),
                        const SizedBox(height: 12),
                        Text(
                            AppLocalizations.of(context)
                                .signingYouIn(widget.request.domain),
                            style: TkText.body.copyWith(
                                fontSize: 16,
                                color: const Color.fromRGBO(
                                    247, 245, 241, .85))),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 17, vertical: 15),
                          decoration: BoxDecoration(
                            color: const Color.fromRGBO(247, 245, 241, .1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                              AppLocalizations.of(context).codeExpiresNote,
                              style: TkText.bodySecondary.copyWith(
                                  color: const Color.fromRGBO(
                                      247, 245, 241, .85))),
                        ),
                      ],
                    ),
                  ),
                ),
                TkPrimaryButton(
                  label: AppLocalizations.of(context).done,
                  background: TkColors.paper,
                  foreground: TkColors.greenDeep,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- A15 ----------------------------------------------------------------

  Widget _buildDenied() {
    return Scaffold(
      backgroundColor: TkColors.dangerBg,
      body: TkRiseIn(
        duration: TkMotion.riseInFast,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 24, 26, TkSpace.bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(AppLocalizations.of(context).blockedNothingSent,
                            style: const TextStyle(
                                fontFamily: TkFonts.sans,
                                fontSize: 30,
                                fontWeight: FontWeight.w600,
                                height: 1.2,
                                letterSpacing: 30 * -.025,
                                color: TkColors.paper)),
                        const SizedBox(height: 18),
                        Text(
                            AppLocalizations.of(context).deniedBody,
                            style: TkText.body.copyWith(
                                fontSize: 15.5,
                                color: const Color.fromRGBO(
                                    247, 245, 241, .85))),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color.fromRGBO(247, 245, 241, .12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                              AppLocalizations.of(context)
                                  .deniedChangePassword(widget.request.domain),
                              style: TkText.body.copyWith(
                                  fontSize: 14, color: TkColors.paper)),
                        ),
                      ],
                    ),
                  ),
                ),
                TkPrimaryButton(
                  label: AppLocalizations.of(context).gotIt,
                  background: TkColors.paper,
                  foreground: TkColors.dangerBg,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- A12 ----------------------------------------------------------------

  Widget _buildCodeOnly() {
    final l = AppLocalizations.of(context);
    final account = _account!;
    final now = ref.watch(tickProvider).maybeWhen(
          data: (t) => t,
          orElse: DateTime.now,
        );
    final code = account.totp.codeAt(now);
    final secondsLeft = account.totp.secondsRemaining(now);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: TkColors.inkGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 24, 26, TkSpace.bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    TkAvatarTile(
                        letter: widget.request.domain.isEmpty
                            ? '?'
                            : widget.request.domain[0].toUpperCase(),
                        color: TkColors.paper,
                        size: 46),
                    const SizedBox(width: 13),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.typeThisInto,
                            style: TkText.metadata.copyWith(
                                fontSize: 12.5, color: TkColors.paper55)),
                        Text(widget.request.domain,
                            style: const TextStyle(
                                fontFamily: TkFonts.sans,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: TkColors.paper)),
                      ],
                    ),
                  ],
                ),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(formatCodeForDisplay(code),
                            style: TkText.codeHero
                                .copyWith(color: TkColors.paper)),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Text(l.newCodeInSeconds(secondsLeft),
                                style: TkText.metadata.copyWith(
                                    fontSize: 12.5,
                                    color: TkColors.paper55)),
                            const SizedBox(width: 11),
                            Expanded(
                              child: TkCountdownBar(
                                fraction: secondsLeft / account.period,
                                background: const Color.fromRGBO(
                                    247, 245, 241, .14),
                                fill: TkColors.greenBright,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                            l.codeOnlyNote,
                            textAlign: TextAlign.center,
                            style: TkText.bodySecondary
                                .copyWith(color: TkColors.paper55)),
                      ],
                    ),
                  ),
                ),
                TkPrimaryButton(
                  label: _copied ? l.copied : l.copyCode,
                  background:
                      _copied ? TkColors.greenBrightHover : TkColors.greenBright,
                  foreground: TkColors.onGreenBrightText,
                  onPressed: () async {
                    await PlatformServices.copyCode(code);
                    setState(() => _copied = true);
                    Future.delayed(TkMotion.copiedHold, () {
                      if (mounted) setState(() => _copied = false);
                    });
                  },
                ),
                const SizedBox(height: 10),
                TkSecondaryButton(
                  label: l.done,
                  borderColor: TkColors.paper20,
                  foreground: const Color.fromRGBO(247, 245, 241, .8),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A16 (4k): the intrusion aftermath, shown when the app is opened after a
/// deny the person may have half-forgotten.
class IntrusionScreen extends ConsumerWidget {
  const IntrusionScreen({super.key, required this.incident});

  final Incident incident;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final minutesAgo =
        DateTime.now().toUtc().difference(incident.at).inMinutes;
    final agoLabel = minutesAgo < 1
        ? l.relativeJustNow
        : minutesAgo < 60
            ? l.relativeMinutesAgo(minutesAgo)
            : l.relativeHoursAgo(minutesAgo ~/ 60);
    return Scaffold(
      backgroundColor: TkColors.dangerBg,
      body: TkRiseIn(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 24, 26, TkSpace.bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.intrusionBadge(agoLabel),
                    style: TkText.sectionLabel.copyWith(
                        fontSize: 12,
                        color: const Color.fromRGBO(247, 245, 241, .7))),
                const SizedBox(height: 14),
                Text(l.intrusionTitle(incident.domain),
                    style: const TextStyle(
                        fontFamily: TkFonts.sans,
                        fontSize: 29,
                        fontWeight: FontWeight.w600,
                        height: 1.18,
                        letterSpacing: 29 * -.025,
                        color: TkColors.paper)),
                const SizedBox(height: 12),
                Text(
                    l.intrusionBody,
                    style: TkText.body.copyWith(
                        fontSize: 15.5,
                        color: const Color.fromRGBO(247, 245, 241, .85))),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(247, 245, 241, .12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      _row(l.detailBrowser, incident.browser),
                      const SizedBox(height: 9),
                      _row(l.intrusionTried, l.triedTimes(incident.attempts)),
                    ],
                  ),
                ),
                const Spacer(),
                TkPrimaryButton(
                  label: l.okay,
                  background: TkColors.paper,
                  foreground: TkColors.dangerBg,
                  onPressed: () => _dismiss(context, ref, mute: false),
                ),
                const SizedBox(height: 10),
                TkSecondaryButton(
                  label: l.muteToday,
                  borderColor: const Color.fromRGBO(247, 245, 241, .28),
                  foreground: const Color.fromRGBO(247, 245, 241, .9),
                  onPressed: () => _dismiss(context, ref, mute: true),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TkText.body.copyWith(
                fontSize: 14,
                color: const Color.fromRGBO(247, 245, 241, .7))),
        Text(value,
            style: TkText.body
                .copyWith(fontSize: 14, color: TkColors.paper)),
      ],
    );
  }

  Future<void> _dismiss(BuildContext context, WidgetRef ref,
      {required bool mute}) async {
    await ref.read(vaultProvider.notifier).mutate((data) => VaultData(
          accounts: data.accounts,
          mutedSites: {
            ...data.mutedSites,
            if (mute) incident.domain.toLowerCase(): VaultData.todayKey(),
          },
          incidents: [
            for (final i in data.incidents)
              if (i.domain == incident.domain) i.copyWith(seen: true) else i,
          ],
        ));
    if (context.mounted) Navigator.of(context).pop();
  }
}
