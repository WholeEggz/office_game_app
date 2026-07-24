import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/data/local/local_auth_service.dart';
import 'package:office_game_app/data/local/local_game_repository.dart';
import 'package:office_game_app/domain/repositories/auth_service.dart';
import 'package:office_game_app/domain/repositories/game_repository.dart';
import 'package:office_game_app/ui/entry/player_entry_screen.dart';
import 'package:provider/provider.dart';

Future<void> _signIn(WidgetTester tester, LocalGameRepository repo) async {
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
  // resolve (there's nothing to resume here, but the loading spinner it
  // shows in the meantime means the registration form isn't in the tree
  // yet on the very first frame).
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
  testWidgets('sorting by most players reorders the case list', (tester) async {
    final repo = LocalGameRepository();
    await repo.createGame(
      locationTag: 'Small Case',
      minPlayers: 4,
      creatorId: 'creator1',
      creatorName: 'Creator 1',
    );
    final bigGame = await repo.createGame(
      locationTag: 'Big Case',
      minPlayers: 4,
      creatorId: 'creator2',
      creatorName: 'Creator 2',
    );
    await repo.addPlayer(gameId: bigGame.id, playerId: 'extra1', name: 'Extra 1');
    await repo.addPlayer(gameId: bigGame.id, playerId: 'extra2', name: 'Extra 2');

    await _signIn(tester, repo);

    // Default (newest first) puts "Big Case" (created last) above "Small
    // Case" — switch to "Most players" and confirm it reorders instead.
    await tester.tap(find.textContaining('Sort:'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Most players'));
    await tester.pumpAndSettle();

    final bigCaseY = tester.getTopLeft(find.text('Big Case')).dy;
    final smallCaseY = tester.getTopLeft(find.text('Small Case')).dy;
    expect(bigCaseY, lessThan(smallCaseY));
  });

  testWidgets('deselecting a status pill hides cases in that status', (tester) async {
    final repo = LocalGameRepository();
    await repo.createGame(
      locationTag: 'Open Case',
      minPlayers: 4,
      creatorId: 'creator1',
      creatorName: 'Creator 1',
    );

    await _signIn(tester, repo);
    expect(find.text('Open Case'), findsOneWidget);

    // "recruiting" is the only status present — deselecting it should hide
    // the case (and can't be un-toggled down to zero statuses selected).
    await tester.tap(find.text('recruiting'));
    await tester.pumpAndSettle();

    expect(find.text('Open Case'), findsNothing);
    expect(find.text('No cases match these filters.'), findsOneWidget);
  });

  testWidgets(
      'the "New here?" hint is the first thing shown on the case list, and '
      '"Got it" dismisses it for good', (tester) async {
    final repo = LocalGameRepository();
    await repo.createGame(
      locationTag: 'Open Case',
      minPlayers: 4,
      creatorId: 'creator1',
      creatorName: 'Creator 1',
    );

    await _signIn(tester, repo);

    final welcomeY = tester.getTopLeft(find.textContaining('New here?')).dy;
    final locationHintY =
        tester.getTopLeft(find.textContaining('Cases near your office')).dy;
    expect(welcomeY, lessThan(locationHintY));

    // Dismissing it must not surface the "Couldn't dismiss" SnackBar —
    // that was the reported bug, caused by this hint previously routing
    // through the game-scoped GameRepository.dismissHint (which needs a
    // gameId that doesn't exist on this pre-game screen) instead of
    // AuthService.dismissHint.
    await tester.tap(find.text('Got it').first);
    await tester.pumpAndSettle();

    expect(find.textContaining("Couldn't dismiss"), findsNothing);
    expect(find.textContaining('New here?'), findsNothing);

    // Still gone after a rebuild (e.g. sorting/filtering), not just
    // faded out for this frame.
    await tester.tap(find.text('recruiting'));
    await tester.pumpAndSettle();
    expect(find.textContaining('New here?'), findsNothing);
  });

  testWidgets('"Open Help" on the "New here?" hint both dismisses it and opens Help',
      (tester) async {
    final repo = LocalGameRepository();
    await repo.createGame(
      locationTag: 'Open Case',
      minPlayers: 4,
      creatorId: 'creator1',
      creatorName: 'Creator 1',
    );

    await _signIn(tester, repo);

    await tester.tap(find.text('Open Help'));
    await tester.pumpAndSettle();

    expect(find.text('How to play'), findsOneWidget);
    expect(find.textContaining("Couldn't dismiss"), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.textContaining('New here?'), findsNothing);
  });
}
