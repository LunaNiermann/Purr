import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/tokens.dart';
import '../../design/widgets.dart';
import '../../services/approval_service.dart';
import '../../services/pairing_service.dart';
import '../../services/push.dart';
import '../../services/relay_api.dart';
import '../../state/providers.dart';

/// Design 5d: ask about notifications only once there's a paired computer AND
/// at least one account — the first moment a push has something to say. Our
/// priming sheet precedes the OS prompt and always leaves a graceful "not now".
Future<void> maybePrimeNotifications(
    BuildContext context, WidgetRef ref) async {
  if (!PushService.available) return;
  if (ref.read(prefsProvider).notificationsChoice != 'unasked') return;
  if (ref.read(pairingProvider).pairing == null) return;
  if (ref.read(vaultProvider).accounts.isEmpty) return;

  final wants = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: TkColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
    builder: (context) => SafeArea(
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
            const TkBrandTile(size: 52),
            const SizedBox(height: 16),
            const Text('Want the code to come to you?',
                style: TkText.screenTitle),
            const SizedBox(height: 10),
            Text(
              'With notifications on, signing in on your computer is one tap '
              'here — no unlocking, no hunting for the right account.',
              style: TkText.body.copyWith(fontSize: 15),
            ),
            const SizedBox(height: 15),
            // Inline preview of the exact push.
            TkCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const TkBrandTile(size: 34),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Purr',
                            style: TextStyle(
                                fontFamily: TkFonts.sans,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: TkColors.ink)),
                        const SizedBox(height: 2),
                        Text('Your browser needs a code. Tap to approve.',
                            style: TkText.bodySecondary
                                .copyWith(fontSize: 13, height: 1.45)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
                "That's the only kind of notification we send. No tips, no "
                'news, no nudges.',
                style: TkText.bodySecondary.copyWith(color: TkColors.ink55)),
            const SizedBox(height: 18),
            TkPrimaryButton(
              label: 'Turn on notifications',
              onPressed: () => Navigator.pop(context, true),
            ),
            const SizedBox(height: 10),
            TkSecondaryButton(
              label: "Not now — I'll open the app myself",
              onPressed: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    ),
  );

  final notifier = ref.read(prefsProvider.notifier);
  if (wants != true) {
    await notifier.update((p) => p.copyWith(notificationsChoice: 'declined'));
    return;
  }

  final granted = await PushService.requestPermission();
  await notifier.update((p) =>
      p.copyWith(notificationsChoice: granted ? 'granted' : 'declined'));

  if (granted) {
    // Make sure the relay has our token now that we can actually receive.
    final pairing = await PairingService().current();
    final token = await PushService.token();
    if (pairing != null && token != null) {
      await RelayApi(baseUrl: pairing.relayUrl)
          .updateFcmToken(
            pairingId: pairing.pairingId,
            phoneToken: pairing.phoneToken,
            fcmToken: token,
          )
          .catchError((_) {});
    }
  }
}
