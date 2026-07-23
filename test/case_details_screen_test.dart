import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/data/local/local_auth_service.dart';
import 'package:office_game_app/data/local/local_game_repository.dart';
import 'package:office_game_app/domain/repositories/auth_service.dart';
import 'package:office_game_app/domain/repositories/game_repository.dart';
import 'package:office_game_app/ui/entry/player_entry_screen.dart';
import 'package:office_game_app/ui/game/game_screen.dart';
import 'package:provider/provider.dart';

/// Registers "Alice" via the real player flow and lands on "Find your
/// case" — the shared setup for every test below. The case stays
/// `recruiting` (never reaches its 4-player minimum) so no daily-cutoff
/// `Timer` gets scheduled, keeping these tests free of the teardown
/// cleanup `game_screen_moments_test.dart`'s tests need for active games.
Future<void> _signInAndShowList(WidgetTester tester, LocalGameRepository repo) async {
  // The registration form's static location hint adds enough height to
  // push "Continue" below the default 800x600 test viewport — a taller
  // one avoids needing to script scrolling by hand for every tap/lookup.
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<GameRepository>.value(value: repo),
      Provider<AuthService>.value(value: LocalAuthService()),
    ],
    child: const MaterialApp(home: PlayerEntryScreen()),
  ));
  // One frame for PlayerEntryScreen's initial resumeSession() check to
  // resolve before the registration form is in the tree.
  await tester.pump();
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), 'Alice');
  await tester.enterText(fields.at(1), 'Poland');
  await tester.enterText(fields.at(2), 'Warsaw');
  await tester.enterText(fields.at(3), 'Acme Corp');
  await tester.tap(find.text('Continue'));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('the case list caption shows round count alongside status and player count',
      (tester) async {
    final repo = LocalGameRepository();
    await repo.createGame(
      locationTag: 'Third Floor',
      minPlayers: 4,
      creatorId: 'creator',
      creatorName: 'Creator',
    );

    await _signInAndShowList(tester, repo);

    expect(find.textContaining('round 1'), findsOneWidget);
    expect(find.textContaining('recruiting · round 1 · 1/4 players'), findsOneWidget);
  });

  testWidgets('tapping "Join" on a case not yet joined opens details instead of joining '
      'immediately', (tester) async {
    final repo = LocalGameRepository();
    await repo.createGame(
      locationTag: 'Third Floor',
      minPlayers: 4,
      creatorId: 'creator',
      creatorName: 'Creator',
      rulesDescription: 'Players use real names and departments.',
    );

    await _signInAndShowList(tester, repo);
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();

    // Details screen content, not a live GameScreen — no role-reveal
    // ceremony, no case dashboard.
    expect(find.text('Case rules'), findsOneWidget);
    expect(find.text('Players use real names and departments.'), findsOneWidget);
    expect(find.text('Players so far'), findsOneWidget);
    expect(find.text('Creator'), findsOneWidget);
    expect(find.text('Join this case'), findsOneWidget);

    // Not actually joined yet — the repository roster is untouched.
    final game = await repo.watchGame((await repo.watchGames(viewerId: 'creator').first).single.id)
        .first;
    expect(game.players, hasLength(1));
  });

  testWidgets('a case with no rules text shows a plain fallback line', (tester) async {
    final repo = LocalGameRepository();
    await repo.createGame(
      locationTag: 'Third Floor',
      minPlayers: 4,
      creatorId: 'creator',
      creatorName: 'Creator',
    );

    await _signInAndShowList(tester, repo);
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();

    expect(find.text('No rules noted for this case.'), findsOneWidget);
  });

  testWidgets('"Join this case" actually joins and lands on GameScreen, and a single back '
      'returns to the case list, not the details screen', (tester) async {
    final repo = LocalGameRepository();
    await repo.createGame(
      locationTag: 'Third Floor',
      minPlayers: 4,
      creatorId: 'creator',
      creatorName: 'Creator',
    );

    await _signInAndShowList(tester, repo);
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Join this case'));
    await tester.pumpAndSettle();

    expect(find.byType(GameScreen), findsOneWidget);
    final game = await repo.watchGame((await repo.watchGames(viewerId: 'creator').first).single.id)
        .first;
    expect(game.players.map((p) => p.name), containsAll(['Creator', 'Alice']));

    // Dismiss the joinedCase welcome dialog so the back button is actually
    // on screen (it sits on the dashboard underneath) — the same drain
    // pattern as game_screen_moments_test.dart.
    while (tester.any(find.text('Continue'))) {
      await tester.tap(find.text('Continue').first);
      await tester.pumpAndSettle();
    }

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Find your case'), findsOneWidget);
  });
}
