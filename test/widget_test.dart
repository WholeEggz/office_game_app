import 'package:flutter_test/flutter_test.dart';

import 'package:office_game_app/main.dart';

void main() {
  testWidgets('opens on the player-vs-tester entry screen', (WidgetTester tester) async {
    await tester.pumpWidget(const OfficeGameApp());

    expect(find.text('Continue as a player'), findsOneWidget);
    expect(find.text('Continue as tester'), findsOneWidget);
  });

  testWidgets('tester entry leads to the debug case setup screen', (WidgetTester tester) async {
    await tester.pumpWidget(const OfficeGameApp());
    await tester.tap(find.text('Continue as tester'));
    await tester.pumpAndSettle();

    expect(find.text('Open a new case'), findsOneWidget);
    expect(find.text('Open the case'), findsOneWidget);
  });
}
