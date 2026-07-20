import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:office_game_app/main.dart';

void main() {
  Future<void> selectLocalBackend(WidgetTester tester) async {
    expect(find.text('Use local'), findsOneWidget);
    await tester.tap(find.text('Use local'));
    await tester.pumpAndSettle();
    // AppEntryGate's resumeSession() check resolves async; a fresh
    // LocalAuthService has nothing to resume, so this lands on
    // WelcomeScreen first — tap through it to reach the actual entry
    // screen underneath.
    await tester.tap(find.text('Begin the investigation'));
    await tester.pumpAndSettle();
  }

  testWidgets('opens on the backend selector, then the player-vs-tester entry screen',
      (WidgetTester tester) async {
    await tester.pumpWidget(const OfficeGameApp());
    await selectLocalBackend(tester);

    expect(find.text('Continue as a player'), findsOneWidget);
    expect(find.text('Continue as tester'), findsOneWidget);
  });

  testWidgets('tester entry leads to the debug case setup screen', (WidgetTester tester) async {
    await tester.pumpWidget(const OfficeGameApp());
    await selectLocalBackend(tester);
    await tester.tap(find.text('Continue as tester'));
    await tester.pumpAndSettle();

    expect(find.text('Open a new case'), findsOneWidget);
    expect(find.text('Open the case'), findsOneWidget);
  });

  testWidgets('opening a case as tester reaches the debug roster without a provider error', (
    WidgetTester tester,
  ) async {
    // Regression test: _createGame is the first thing on this path that
    // actually reads AuthService/GameRepository via context.read, so it's
    // what previously caught MultiProvider being nested inside
    // MaterialApp's `home:` instead of wrapping MaterialApp itself — a
    // route pushed via Navigator.push doesn't inherit providers scoped
    // only to whatever `home:` rendered. Deliberately not "Quick start
    // (8 players)": that activates the game and schedules a real
    // daily-cutoff Timer, which flutter_test's binding asserts isn't
    // still pending at teardown (see game_screen_moments_test.dart's
    // comment) — a single creator alone never reaches minPlayers, so no
    // Timer gets scheduled, and the provider read this test cares about
    // still happens either way.
    await tester.pumpWidget(const OfficeGameApp());
    await selectLocalBackend(tester);
    await tester.tap(find.text('Continue as tester'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(2), 'Alice');
    await tester.tap(find.text('Open the case'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Debug roster — real roles, never shown to a real player like this'),
        findsOneWidget);
  });
}
