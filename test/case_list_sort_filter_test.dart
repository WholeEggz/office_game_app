import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/data/local/local_auth_service.dart';
import 'package:office_game_app/data/local/local_game_repository.dart';
import 'package:office_game_app/domain/repositories/auth_service.dart';
import 'package:office_game_app/domain/repositories/game_repository.dart';
import 'package:office_game_app/ui/entry/player_entry_screen.dart';
import 'package:provider/provider.dart';

Future<void> _signIn(WidgetTester tester, LocalGameRepository repo) async {
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
  await tester.enterText(find.byType(TextField), 'Alice');
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
}
