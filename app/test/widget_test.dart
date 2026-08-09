import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twofa/main.dart';

void main() {
  testWidgets('app boots to a frame without crashing', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: TwoKeysApp()));
    await tester.pump();
    expect(find.byType(TwoKeysApp), findsOneWidget);
  });
}
