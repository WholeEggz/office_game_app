import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/data/local/local_auth_service.dart';
import 'package:office_game_app/data/local/local_game_repository.dart';
import 'package:office_game_app/domain/repositories/auth_service.dart';
import 'package:office_game_app/domain/repositories/game_repository.dart';
import 'package:office_game_app/ui/entry/player_entry_screen.dart';
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
    await tester.pumpAndSettle();

    // "Welcome to the case" (joinedCase, recorded when they were first
    // added — and now carrying the former role-reveal ceremony's content)
    // is first in the queue, ahead of the round-scoped moment.
    expect(find.textContaining('Welcome to the case'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    // pumpAndSettle, not a single pump — a dialog's pop transition isn't
    // instant, and the next dialog in the queue needs the first one fully
    // gone before its own "Continue" is unambiguous to find.
    await tester.pumpAndSettle();

    expect(find.textContaining('Round 1 has ended'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();

    // Only the joinedCase welcome dialog so far — nothing round-related
    // has happened yet.
    expect(find.textContaining('Welcome to the case'), findsOneWidget);
    expect(find.textContaining('has ended'), findsNothing);
    expect(find.textContaining('Good catch'), findsNothing);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();

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

  testWidgets(
      'joining a case via "Find your case" shows a welcome dialog the first time, and '
      '"Enter" on a later visit shows a welcome-back dialog instead', (tester) async {
    final repo = LocalGameRepository();
    final auth = LocalAuthService();
    // minPlayers 4 so the case is still just `recruiting` after Alice
    // joins as the 2nd player below — a 2-player, 1-mafia game would hit
    // instant parity and end itself the moment she joined, queuing a
    // finale dialog that would tangle up this test's own assertions.
    final game = await repo.createGame(
      locationTag: 'Test Office',
      minPlayers: 4,
      creatorId: 'creator',
      creatorName: 'Creator',
      mafiaCount: 1,
    );

    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<GameRepository>.value(value: repo),
        Provider<AuthService>.value(value: auth),
      ],
      child: const MaterialApp(home: PlayerEntryScreen()),
    ));
    // One frame for PlayerEntryScreen's initial resumeSession() check to
    // resolve before the registration form is in the tree.
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'Alice');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump();

    // Tapping "Join" from the list opens the case details screen first;
    // "Join this case" there is what actually joins.
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Join this case'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Welcome to the case'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // Back out to "Find your case" and enter the same case again — this
    // time it's "Enter", not "Join".
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Enter'), findsOneWidget);
    await tester.tap(find.text('Enter'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Welcome back'), findsOneWidget);
    expect(find.textContaining('Welcome to the case'), findsNothing);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // Fill the roster and close the case so no cutoff timer is left
    // pending at teardown.
    await repo.addPlayer(gameId: game.id, playerId: 'p3', name: 'Player 3');
    await repo.addPlayer(gameId: game.id, playerId: 'p4', name: 'Player 4');
    final started = await repo.watchGame(game.id).first;
    final mafia = started.mafia.single;
    for (final voter in started.players.where((p) => p.id != mafia.id)) {
      await repo.castVote(gameId: game.id, voterId: voter.id, targetPlayerId: mafia.id);
    }
    await repo.resolveVotesForDay(game.id);
    await tester.pump();
    await tester.pump();
    await _drainDialogs(tester);
  });
}
