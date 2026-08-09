import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twofa/src/data/models.dart';
import 'package:twofa/src/screens/request/request_screens.dart';
import 'package:twofa/src/services/approval_service.dart';
import 'package:twofa/src/state/providers.dart';

/// The approval and intrusion screens are biometric-gated on-device, so they
/// can't be driven end-to-end on a fingerprint-less emulator. These widget
/// tests prove they build and render their key copy from real state.
void main() {
  final account = Account(
    id: 'a1',
    siteName: 'GitHub',
    username: 'ada@fastmail.com',
    secretB32: 'JBSWY3DPEHPK3PXP',
    createdAt: DateTime.utc(2026, 1, 1),
  );

  Widget host(Widget child, {List<Account> accounts = const []}) {
    return ProviderScope(
      overrides: [
        vaultProvider.overrideWith(() => _StubVault(accounts)),
      ],
      child: MaterialApp(home: child),
    );
  }

  testWidgets('A11 incoming request shows the browser-centric ask', (tester) async {
    final request = PendingApproval(
      requestId: 'r1',
      domain: 'github.com',
      browser: 'Chrome · Windows',
      askedAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(seconds: 60)),
    );
    await tester.pumpWidget(
      host(ApprovalFlowScreen(request: request), accounts: [account]),
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Your browser needs a code. Send it?'), findsOneWidget);
    expect(find.text('github.com'), findsOneWidget);
    expect(find.text('Send the code'), findsOneWidget);
    expect(find.text("I didn't ask for this"), findsOneWidget);
    // The matched account surfaces its username in the detail block.
    expect(find.text('ada@fastmail.com'), findsOneWidget);
  });

  testWidgets('A16 intrusion aftermath states the honest framing',
      (tester) async {
    final incident = Incident(
      domain: 'github.com',
      browser: 'Chrome on Windows',
      at: DateTime.now().toUtc(),
      attempts: 3,
    );
    await tester.pumpWidget(host(IntrusionScreen(incident: incident)));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Someone has your github.com password.'), findsOneWidget);
    expect(find.text('Mute requests for this site today'), findsOneWidget);
    expect(find.text('Okay'), findsOneWidget);
  });
}

class _StubVault extends VaultController {
  _StubVault(this._accounts);
  final List<Account> _accounts;

  @override
  VaultState build() =>
      VaultState(status: VaultStatus.unlocked, data: VaultData(accounts: _accounts));
}
