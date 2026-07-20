import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/ui/entry/welcome_screen.dart';

void main() {
  testWidgets(
      'stays on the intro2 poster and reveals secrets one at a time as the '
      'player taps, looping back to the first', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WelcomeScreen()));
    await tester.pumpAndSettle();

    expect(find.byWidgetPredicate(
      (w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName.endsWith('intro2.png'),
    ), findsOneWidget);
    expect(find.text('Something mysterious is happening in your office'), findsOneWidget);
    expect(find.text('Begin the investigation'), findsOneWidget);

    // Tap the poster itself — anywhere but the CTA button.
    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();

    // Still the same poster — only the whispered line changed.
    expect(find.byWidgetPredicate(
      (w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName.endsWith('intro2.png'),
    ), findsOneWidget);
    expect(find.text('Some of your friends work on a secret case'), findsOneWidget);

    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();
    expect(find.text('Some of them belong to the mafia'), findsOneWidget);

    // Tap through the remaining secrets and confirm it loops back to the
    // very first one afterward.
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byType(Image));
      await tester.pumpAndSettle();
    }
    expect(find.text('Something mysterious is happening in your office'), findsOneWidget);
  });

  testWidgets('tapping the CTA navigates instead of revealing another secret', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WelcomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Begin the investigation'));
    await tester.pumpAndSettle();

    expect(find.byType(WelcomeScreen), findsNothing);
  });
}
