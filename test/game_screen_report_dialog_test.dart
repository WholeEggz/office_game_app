import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/data/local/local_game_repository.dart';
import 'package:office_game_app/domain/repositories/game_repository.dart';
import 'package:office_game_app/ui/game/game_screen.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

// Regression test for a crash where the report dialog's TextEditingController
// was disposed the instant showDialog's Future resolved, racing the dialog's
// still-running dismiss animation and throwing "used after being disposed."
void main() {
  testWidgets(
      'submitting the roster report dialog closes cleanly and shows a confirmation',
      (tester) async {
    final repo = LocalGameRepository();
    final game = await repo.createGame(
      locationTag: 'Test Office',
      minPlayers: 4,
      creatorId: 'p1',
      creatorName: 'Alice',
      mafiaCount: 1,
    );
    for (var i = 2; i <= 4; i++) {
      await repo.addPlayer(gameId: game.id, playerId: 'p$i', name: 'Player $i');
    }
    final started = await repo.watchGame(game.id).first;
    final viewer = started.villagers.first;
    final mafia = started.mafia.single;

    await tester.pumpWidget(Provider<GameRepository>.value(
      value: repo,
      child: MaterialApp(
        home: GameScreen(gameId: game.id, playerId: viewer.id),
      ),
    ));
    await tester.pump();
    await tester.pump(); // one more frame for the joinedCase moment to queue
    while (tester.any(find.text('Continue'))) {
      await tester.tap(find.text('Continue').first);
      await tester.pump();
    }
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(PhosphorIconsLight.dotsThreeVertical).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'inappropriate name');
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Report submitted.'), findsOneWidget);

    // Close the case so no daily-cutoff Timer is left pending at teardown.
    for (final voter in started.players.where((p) => p.id != mafia.id)) {
      await repo.castVote(gameId: game.id, voterId: voter.id, targetPlayerId: mafia.id);
    }
    await repo.resolveVotesForDay(game.id);
    await tester.pump();
    await tester.pump();
    while (tester.any(find.text('Continue'))) {
      await tester.tap(find.text('Continue').first);
      await tester.pump();
    }
    await tester.pumpAndSettle();
  });
}
