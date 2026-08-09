import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/totp.dart';
import '../../data/models.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../services/platform.dart';
import '../../state/providers.dart';
import '../add/add_entry.dart';
import 'account_detail_screen.dart';

/// A5/A6/A7: the vault. One-per-row or two-up cards, search with highlight,
/// tap-anywhere-to-copy with the 2 s green feedback, shared 30 s countdown.
class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key});

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen> {
  final _search = TextEditingController();
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _copy(Account account, String code) {
    HapticFeedback.lightImpact();
    PlatformServices.copyCode(code);
    ref.read(copiedIdProvider.notifier).set(account.id);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(TkMotion.copiedHold, () {
      if (mounted) ref.read(copiedIdProvider.notifier).set(null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final vault = ref.watch(vaultProvider);
    final prefs = ref.watch(prefsProvider);
    final copiedId = ref.watch(copiedIdProvider);
    final now =
        ref.watch(tickProvider).maybeWhen(data: (t) => t, orElse: DateTime.now);

    final accounts = vault.accounts;
    final query = _search.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? accounts
        : accounts
            .where((a) =>
                a.siteName.toLowerCase().contains(query) ||
                a.username.toLowerCase().contains(query))
            .toList();
    final sorted = [...filtered]..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return a.siteName.toLowerCase().compareTo(b.siteName.toLowerCase());
      });

    final secondsLeft = 30 - (now.millisecondsSinceEpoch ~/ 1000 % 30);

    if (accounts.isEmpty) return _EmptyVault(onChanged: () => setState(() {}));

    return Scaffold(
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 64),
        child: FloatingActionButton(
          backgroundColor: TkColors.green,
          foregroundColor: TkColors.paper,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          onPressed: () => startAddEntry(context, ref),
          child: const Icon(Icons.add, size: 28),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 170),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Expanded(
                          child: Text('Codes', style: TkText.pageHeading)),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                            '${accounts.length} account${accounts.length == 1 ? '' : 's'}',
                            style: TkText.metadata),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: TkColors.paperField,
                      borderRadius: BorderRadius.circular(TkRadius.field),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        const Icon(Icons.search,
                            size: 18, color: TkColors.ink45),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _search,
                            onChanged: (_) => setState(() {}),
                            style: const TextStyle(
                                fontFamily: TkFonts.sans, fontSize: 15.5),
                            decoration: const InputDecoration(
                              hintText: 'Search accounts',
                              hintStyle: TextStyle(
                                  fontSize: 15, color: TkColors.ink45),
                              border: InputBorder.none,
                              contentPadding:
                                  EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        if (query.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              _search.clear();
                              setState(() {});
                            },
                            child: Text('Cancel',
                                style: TkText.metadata.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (query.isEmpty)
                    Row(
                      children: [
                        Text('TAP TO COPY · ${secondsLeft}S',
                            style: TkText.sectionLabel
                                .copyWith(letterSpacing: 11.5 * .06)),
                        const SizedBox(width: 10),
                        Expanded(
                            child:
                                TkCountdownBar(fraction: secondsLeft / 30)),
                      ],
                    )
                  else
                    Text(
                        '${filtered.length} of ${accounts.length} account${accounts.length == 1 ? '' : 's'}',
                        style: TkText.metadata),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: prefs.layout == 'cards'
                  ? _CardsLayout(
                      accounts: sorted,
                      now: now,
                      copiedId: copiedId,
                      hideCodes: prefs.hideCodes,
                      query: query,
                      onCopy: _copy,
                      onOpen: _open,
                    )
                  : Column(
                      children: [
                        for (final account in sorted) ...[
                          _AccountRow(
                            account: account,
                            now: now,
                            copied: copiedId == account.id,
                            hideCodes: prefs.hideCodes,
                            query: query,
                            onCopy: _copy,
                            onOpen: _open,
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
            ),
            if (query.isNotEmpty) ...[
              const SizedBox(height: 26),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 26),
                child: Text(
                  'Searching looks at the site name and your username — not '
                  'the codes themselves.',
                  textAlign: TextAlign.center,
                  style: TkText.bodySecondary.copyWith(color: TkColors.ink45),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _open(Account account) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AccountDetailScreen(accountId: account.id)));
  }
}

/// Highlights the matched substring in green-pale (A7).
Widget highlightedText(String text, String query, TextStyle style) {
  if (query.isEmpty) return Text(text, style: style, overflow: TextOverflow.ellipsis);
  final lower = text.toLowerCase();
  final index = lower.indexOf(query);
  if (index < 0) return Text(text, style: style, overflow: TextOverflow.ellipsis);
  return RichText(
    overflow: TextOverflow.ellipsis,
    text: TextSpan(style: style, children: [
      TextSpan(text: text.substring(0, index)),
      TextSpan(
        text: text.substring(index, index + query.length),
        style: style.copyWith(backgroundColor: TkColors.greenPale),
      ),
      TextSpan(text: text.substring(index + query.length)),
    ]),
  );
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.account,
    required this.now,
    required this.copied,
    required this.hideCodes,
    required this.query,
    required this.onCopy,
    required this.onOpen,
  });

  final Account account;
  final DateTime now;
  final bool copied;
  final bool hideCodes;
  final String query;
  final void Function(Account, String) onCopy;
  final void Function(Account) onOpen;

  @override
  Widget build(BuildContext context) {
    final code = account.totp.codeAt(now);
    final display =
        hideCodes && !copied ? '••• •••' : formatCodeForDisplay(code);
    return GestureDetector(
      onTap: () => onCopy(account, code),
      onLongPress: () => onOpen(account),
      child: AnimatedContainer(
        duration: TkMotion.feedback,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: copied ? TkColors.greenTint : TkColors.surface,
          border:
              Border.all(color: copied ? TkColors.green : TkColors.ink06),
          borderRadius: BorderRadius.circular(TkRadius.card),
        ),
        child: Row(
          children: [
            TkAvatarTile(
                letter: account.siteName.isEmpty
                    ? '?'
                    : account.siteName[0].toUpperCase(),
                color: brandColorFor(account.siteName)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  highlightedText(
                      account.siteName,
                      query,
                      const TextStyle(
                        fontFamily: TkFonts.sans,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 16 * -.01,
                        color: TkColors.ink,
                      )),
                  const SizedBox(height: 1),
                  copied
                      ? const Text('Copied',
                          style: TextStyle(
                              fontFamily: TkFonts.sans,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: TkColors.green))
                      : highlightedText(
                          account.username, query, TkText.metadata),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(display, style: TkText.codeRow),
            const SizedBox(width: 12),
            AnimatedContainer(
              duration: TkMotion.feedback,
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: copied ? TkColors.green : TkColors.paperSunk,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: TkCopyGlyph(
                color: copied ? TkColors.paper : TkColors.ink55,
                fill: copied ? TkColors.green : TkColors.paperSunk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardsLayout extends StatelessWidget {
  const _CardsLayout({
    required this.accounts,
    required this.now,
    required this.copiedId,
    required this.hideCodes,
    required this.query,
    required this.onCopy,
    required this.onOpen,
  });

  final List<Account> accounts;
  final DateTime now;
  final String? copiedId;
  final bool hideCodes;
  final String query;
  final void Function(Account, String) onCopy;
  final void Function(Account) onOpen;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 118,
      ),
      itemCount: accounts.length,
      itemBuilder: (context, i) {
        final account = accounts[i];
        final copied = copiedId == account.id;
        final code = account.totp.codeAt(now);
        final display =
            hideCodes && !copied ? '••• •••' : formatCodeForDisplay(code);
        return GestureDetector(
          onTap: () => onCopy(account, code),
          onLongPress: () => onOpen(account),
          child: AnimatedContainer(
            duration: TkMotion.feedback,
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
            decoration: BoxDecoration(
              color: copied ? TkColors.greenTint : TkColors.surface,
              border: Border.all(
                  color: copied ? TkColors.green : TkColors.ink06),
              borderRadius: BorderRadius.circular(TkRadius.largeCard),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: brandColorFor(account.siteName),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: highlightedText(
                          account.siteName,
                          query,
                          const TextStyle(
                            fontFamily: TkFonts.sans,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: TkColors.ink,
                          )),
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                        child: Text(display, style: TkText.codeCard)),
                    AnimatedContainer(
                      duration: TkMotion.feedback,
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: copied ? TkColors.green : TkColors.paperSunk,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Transform.scale(
                        scale: .82,
                        child: TkCopyGlyph(
                          color: copied ? TkColors.paper : TkColors.ink55,
                          fill:
                              copied ? TkColors.green : TkColors.paperSunk,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                copied
                    ? const Text('Copied',
                        style: TextStyle(
                            fontFamily: TkFonts.sans,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: TkColors.green))
                    : Text(account.username,
                        overflow: TextOverflow.ellipsis,
                        style: TkText.metadata),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A5 (4e): empty vault.
class _EmptyVault extends ConsumerWidget {
  const _EmptyVault({required this.onChanged});

  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 8, 26, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Codes', style: TkText.pageHeading),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 66,
                        height: 66,
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: const Color.fromRGBO(27, 26, 23, .22),
                              width: 2,
                              style: BorderStyle.solid),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        alignment: Alignment.center,
                        child: const Text('•••',
                            style: TextStyle(
                                fontFamily: TkFonts.mono,
                                fontSize: 16,
                                color: Color.fromRGBO(27, 26, 23, .3))),
                      ),
                      const SizedBox(height: 16),
                      const Text('No accounts yet',
                          style: TextStyle(
                              fontFamily: TkFonts.sans,
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 22 * -.015,
                              color: TkColors.ink)),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          "Go to a site's security settings, choose "
                          '"authenticator app", and point this phone at the '
                          'square it shows you.',
                          textAlign: TextAlign.center,
                          style: TkText.body.copyWith(fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              TkPrimaryButton(
                label: 'Scan a QR code',
                onPressed: () => startAddEntry(context, ref, scan: true),
              ),
              const SizedBox(height: 10),
              TkSecondaryButton(
                label: 'Type a setup code instead',
                onPressed: () => startAddEntry(context, ref, scan: false),
              ),
              const SizedBox(height: 64),
            ],
          ),
        ),
      ),
    );
  }
}
