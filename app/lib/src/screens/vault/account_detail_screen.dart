import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/totp.dart';
import '../../data/models.dart';
import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../services/platform.dart';
import '../../state/providers.dart';

/// A8 (4j): account detail — code card, where-this-lives, rename, pin, remove.
class AccountDetailScreen extends ConsumerStatefulWidget {
  const AccountDetailScreen({super.key, required this.accountId});

  final String accountId;

  @override
  ConsumerState<AccountDetailScreen> createState() =>
      _AccountDetailScreenState();
}

class _AccountDetailScreenState extends ConsumerState<AccountDetailScreen> {
  bool _copied = false;

  Account? get _account {
    final accounts = ref.read(vaultProvider).accounts;
    for (final a in accounts) {
      if (a.id == widget.accountId) return a;
    }
    return null;
  }

  Future<void> _copy(String code) async {
    HapticFeedback.lightImpact();
    await PlatformServices.copyCode(code);
    setState(() => _copied = true);
    Future.delayed(TkMotion.copiedHold, () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _rename(Account account) async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController(text: account.siteName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: TkColors.paper,
        title: Text(l.detailRename,
            style: const TextStyle(
                fontFamily: TkFonts.sans,
                fontSize: 20,
                fontWeight: FontWeight.w600)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(fontFamily: TkFonts.sans, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel, style: const TextStyle(color: TkColors.ink50)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l.saveLabel, style: const TextStyle(color: TkColors.green)),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await ref.read(vaultProvider.notifier).mutate((data) => VaultData(
            accounts: [
              for (final a in data.accounts)
                if (a.id == account.id) a.copyWith(siteName: result) else a,
            ],
            mutedSites: data.mutedSites,
          ));
      setState(() {});
    }
  }

  Future<void> _remove(Account account) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: TkColors.paper,
        title: Text(l.detailRemoveTitle(account.siteName),
            style: const TextStyle(
                fontFamily: TkFonts.sans,
                fontSize: 20,
                fontWeight: FontWeight.w600)),
        content: Text(
          l.detailRemoveWarning(account.siteName),
          style: TkText.body.copyWith(fontSize: 14.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.detailKeepIt,
                style: const TextStyle(color: TkColors.ink50)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.detailRemove,
                style: const TextStyle(color: TkColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(vaultProvider.notifier).mutate((data) => VaultData(
            accounts:
                data.accounts.where((a) => a.id != account.id).toList(),
            mutedSites: data.mutedSites,
          ));
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(vaultProvider);
    final l = AppLocalizations.of(context);
    final account = _account;
    if (account == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    final now =
        ref.watch(tickProvider).maybeWhen(data: (t) => t, orElse: DateTime.now);
    final code = account.totp.codeAt(now);
    final secondsLeft = account.totp.secondsRemaining(now);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: TkColors.paper,
        elevation: 0,
        leading: const BackButton(color: TkColors.ink),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(
              children: [
                TkAvatarTile(
                    letter: account.siteName.isEmpty
                        ? '?'
                        : account.siteName[0].toUpperCase(),
                    color: brandColorFor(account.siteName),
                    size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(account.siteName,
                          style: const TextStyle(
                              fontFamily: TkFonts.sans,
                              fontSize: 23,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 23 * -.018,
                              color: TkColors.ink)),
                      if (account.username.isNotEmpty)
                        Text(account.username,
                            style: TkText.metadata.copyWith(fontSize: 13.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: TkCard(
              radius: TkRadius.largeCard,
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(formatCodeForDisplay(code),
                      style: TkText.codeDetail),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(l.detailNewIn(secondsLeft),
                          style: TkText.metadata.copyWith(fontSize: 12)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: TkCountdownBar(
                              fraction: secondsLeft / account.period)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TkPrimaryButton(
                    label: _copied ? l.copied : l.copyCode,
                    onPressed: () => _copy(code),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: TkSectionLabel(l.detailWhereLives),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: TkCard(
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: TkColors.paperSunk,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.smartphone,
                        size: 16, color: TkColors.ink55),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.detailThisPhone,
                            style: const TextStyle(
                                fontFamily: TkFonts.sans,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: TkColors.ink)),
                        Text(l.detailPlusKit, style: TkText.metadata),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              children: [
                TkCard(
                  onTap: () => _rename(account),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(l.detailRename,
                          style: const TextStyle(
                              fontFamily: TkFonts.sans,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                              color: TkColors.ink)),
                      Text(account.siteName,
                          style: const TextStyle(
                              fontFamily: TkFonts.sans,
                              fontSize: 15.5,
                              color: TkColors.ink35)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TkCard(
                  onTap: () async {
                    await ref
                        .read(vaultProvider.notifier)
                        .mutate((data) => VaultData(
                              accounts: [
                                for (final a in data.accounts)
                                  if (a.id == account.id)
                                    a.copyWith(pinned: !a.pinned)
                                  else
                                    a,
                              ],
                              mutedSites: data.mutedSites,
                            ));
                    setState(() {});
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(l.detailMoveTop,
                          style: const TextStyle(
                              fontFamily: TkFonts.sans,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                              color: TkColors.ink)),
                      Text(account.pinned ? l.detailOn : l.detailOff,
                          style: TextStyle(
                              fontFamily: TkFonts.sans,
                              fontSize: 15.5,
                              color: account.pinned
                                  ? TkColors.green
                                  : TkColors.ink35)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TkCard(
                  onTap: () => _remove(account),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.detailRemoveAccount,
                          style: const TextStyle(
                              fontFamily: TkFonts.sans,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                              color: TkColors.danger)),
                      const SizedBox(height: 5),
                      Text(
                        l.detailRemoveWarning(account.siteName),
                        style: TkText.bodySecondary.copyWith(
                            fontSize: 12.8, color: TkColors.ink55),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
