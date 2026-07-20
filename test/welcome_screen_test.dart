import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/ui/entry/welcome_screen.dart';

void main() {
  testWidgets(
      'tapping outside the CTA cycles intro2 -> intro1 -> the original design, '
      'looping back to the start', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WelcomeScreen()));
    await tester.pumpAndSettle();

    // intro2 shows first.
    expect(find.byWidgetPredicate(
      (w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName.endsWith('intro2.png'),
    ), findsOneWidget);
    expect(find.text('Begin the investigation'), findsOneWidget);

    // Tap the poster image itself — anywhere but the CTA button.
    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();

    expect(find.byWidgetPredicate(
      (w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName.endsWith('intro1.png'),
    ), findsOneWidget);
    expect(find.text('Begin the investigation'), findsOneWidget);

    // Tap again to reach the original mark-and-headline design, last.
    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();

    expect(find.textContaining('Something mysterious'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(find.text('Begin the investigation'), findsOneWidget);

    // One more tap loops back to intro2.
    await tester.tap(find.textContaining('Something mysterious'));
    await tester.pumpAndSettle();

    expect(find.byWidgetPredicate(
      (w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName.endsWith('intro2.png'),
    ), findsOneWidget);
  });

  testWidgets('tapping the CTA itself navigates instead of cycling the variant', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WelcomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Begin the investigation'));
    await tester.pumpAndSettle();

    // Navigated away — the welcome screen (in any variant) is gone.
    expect(find.byType(WelcomeScreen), findsNothing);
  });
}
