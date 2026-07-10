import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/data/local/local_game_repository.dart';
import 'package:office_game_app/domain/repositories/game_repository.dart';
import 'package:office_game_app/ui/game/game_screen.dart';
import 'package:provider/provider.dart';

// An active game keeps a real daily-cutoff Timer scheduled (and, every
// time a round resolves, immediately reschedules a fresh one ~24h out) —
// flutter_test's widget-test binding asserts no Timer is pending at
// teardown, and no fixed-size pump can out-run a chain that reschedules
// itself forever. The only real fix is to drive the game to `ended` before
// the test finishes, since that's the one case where the repository
// itself stops rescheduling — so every test here closes its own case as
// its last step, draining whatever moment dialog(s) that produces along
// the way.
Future<void> _drainDialogs(WidgetTester tester) async {
  while (tester.any(find.text('Continue'))) {
    await tester.tap(find.text('Continue').first);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'a moment that happened while a player was away shows as a dialog the next time '
      'they enter, and is gone on the entry after that', (tester) async {
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

    // Round 1 resolves with nobody voting — a plain roundEnded moment for
    // every player, recorded before anyone's GameScreen ever opens (the
    // "was away when it happened" scenario).
    await repo.resolveVotesForDay(game.id);

    await tester.pumpWidget(Provider<GameRepository>.value(
      value: repo,
      child: MaterialApp(
        home: GameScreen(gameId: game.id, playerId: viewer.id),
      ),
    ));
    await tester.pump();

    // Dismiss the role-reveal ceremony that always plays on entry.
    await tester.tap(find.text('Open the case file'));
    await tester.pump();
    await tester.pump(); // one more frame for the post-role-reveal moments fetch

    expect(find.textContaining('Round 1 has ended'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pump();

    expect(find.textContaining('Round 1 has ended'), findsNothing);

    // Confirmed acknowledged at the repository level too, not just
    // dismissed on screen.
    final remaining =
        await repo.fetchUnacknowledgedMoments(gameId: game.id, playerId: viewer.id);
    expect(remaining, isEmpty);

    // Close the case (see _drainDialogs) so no cutoff timer is left
    // pending at teardown.
    for (final voter in started.players.where((p) => p.id != mafia.id)) {
      await repo.castVote(gameId: game.id, voterId: voter.id, targetPlayerId: mafia.id);
    }
    await repo.resolveVotesForDay(game.id);
    await tester.pump();
    await tester.pump();
    await _drainDialogs(tester);
  });

  testWidgets('a moment for the acting player appears live, without leaving and re-entering',
      (tester) async {
    final repo = LocalGameRepository();
    // 8 players so 2 mafia isn't instant parity (2 mafia / 6 villagers) —
    // the game needs to stay running to observe a live update rather than
    // an immediate finale.
    final game = await repo.createGame(
      locationTag: 'Test Office',
      minPlayers: 8,
      creatorId: 'p1',
      creatorName: 'Alice',
      mafiaCount: 2,
    );
    for (var i = 2; i <= 8; i++) {
      await repo.addPlayer(gameId: game.id, playerId: 'p$i', name: 'Player $i');
    }
    final started = await repo.watchGame(game.id).first;
    final target = started.mafia.first;
    final otherMafia = started.mafia.firstWhere((p) => p.id != target.id);
    final voter = started.villagers.first;

    await tester.pumpWidget(Provider<GameRepository>.value(
      value: repo,
      child: MaterialApp(
        home: GameScreen(gameId: game.id, playerId: voter.id),
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('Open the case file'));
    await tester.pump();
    await tester.pump();
    // Nothing has happened yet — no dialog on first entry.
    expect(find.textContaining('has ended'), findsNothing);
    expect(find.textContaining('Good catch'), findsNothing);

    // Everyone votes for `target`, cast directly through the repository —
    // this player's GameScreen is already open and just watching, not the
    // one triggering the resolution.
    for (final p in started.players) {
      if (p.id == target.id) continue;
      await repo.castVote(gameId: game.id, voterId: p.id, targetPlayerId: target.id);
    }
    await repo.resolveVotesForDay(game.id);
    // The game stream emission should trigger the live moments check
    // without this screen ever being re-entered.
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Good catch'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pump();

    // Close the case (unmask the remaining mafia member too) so no cutoff
    // timer is left pending at teardown.
    final current = await repo.watchGame(game.id).first;
    for (final p in current.players.where((p) => p.id != otherMafia.id)) {
      await repo.castVote(gameId: game.id, voterId: p.id, targetPlayerId: otherMafia.id);
    }
    await repo.resolveVotesForDay(game.id);
    await tester.pump();
    await tester.pump();
    await _drainDialogs(tester);
  });
}
