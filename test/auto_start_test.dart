import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/data/local/local_game_repository.dart';
import 'package:office_game_app/domain/models/game.dart';
import 'package:office_game_app/domain/models/player.dart';

void main() {
  test('the game auto-starts the moment the roster reaches minPlayers, with no explicit startGame call',
      () async {
    // Regression test: the real player flow (PlayerEntryScreen) only ever
    // calls addPlayer, never startGame — only the debug role switcher's
    // manual button does. Before this fix, a game joined entirely through
    // the real flow stayed `recruiting` forever and every player stayed a
    // villager.
    final repo = LocalGameRepository();
    final game = await repo.createGame(
      locationTag: 'Test Office',
      minPlayers: 4,
      creatorId: 'p1',
      creatorName: 'Alice',
    );
    for (var i = 2; i <= 4; i++) {
      await repo.addPlayer(gameId: game.id, playerId: 'p$i', name: 'Player $i');
    }

    final afterLastJoin = await repo.watchGame(game.id).first;
    expect(afterLastJoin.status, GameStatus.active);
    expect(afterLastJoin.mafia, isNotEmpty);
  });

  test(
      'a game whose minPlayers is met at creation (a lone creator) auto-starts, '
      'then immediately ends since a lone player leaves no villagers', () async {
    final repo = LocalGameRepository();
    final game = await repo.createGame(
      locationTag: 'Test Office',
      minPlayers: 1,
      creatorId: 'p1',
      creatorName: 'Alice',
    );
    // Roles were drawn (auto-start did happen) — but with exactly 1 player,
    // that lone player is mafia and there are zero villagers, so the
    // mafia-parity win condition fires in the very same step.
    expect(game.status, GameStatus.ended);
    expect(game.winner, GameWinner.mafia);
    expect(game.mafia, hasLength(1));
  });

  test('a mafiaCount of 0 or less still guarantees at least one mafia member', () async {
    final repo = LocalGameRepository();
    final game = await repo.createGame(
      locationTag: 'Test Office',
      minPlayers: 4,
      creatorId: 'p1',
      creatorName: 'Alice',
      mafiaCount: 0,
    );
    for (var i = 2; i <= 4; i++) {
      await repo.addPlayer(gameId: game.id, playerId: 'p$i', name: 'Player $i');
    }

    final started = await repo.watchGame(game.id).first;
    expect(started.status, GameStatus.active);
    expect(started.mafia, hasLength(1));
    expect(started.players.every((p) => p.role == PlayerRole.villager), isFalse);
  });

  test('a mafiaCount larger than the roster clamps down to the roster size', () async {
    final repo = LocalGameRepository();
    final game = await repo.createGame(
      locationTag: 'Test Office',
      minPlayers: 4,
      creatorId: 'p1',
      creatorName: 'Alice',
      mafiaCount: 99,
    );
    for (var i = 2; i <= 4; i++) {
      await repo.addPlayer(gameId: game.id, playerId: 'p$i', name: 'Player $i');
    }

    final started = await repo.watchGame(game.id).first;
    // Clamped to exactly the roster size (4), not the requested 99 —
    // everyone ends up mafia, so mafia-parity ends the game in the same
    // step.
    expect(started.status, GameStatus.ended);
    expect(started.mafia, hasLength(4));
  });

  test('joining after the game has already started adds a plain villager, does not re-draw roles',
      () async {
    final repo = LocalGameRepository();
    final game = await repo.createGame(
      locationTag: 'Test Office',
      minPlayers: 4,
      creatorId: 'p1',
      creatorName: 'Alice',
    );
    for (var i = 2; i <= 4; i++) {
      await repo.addPlayer(gameId: game.id, playerId: 'p$i', name: 'Player $i');
    }
    final started = await repo.watchGame(game.id).first;
    final mafiaIdsAtStart = started.mafia.map((p) => p.id).toSet();

    final latecomer = await repo.addPlayer(gameId: game.id, playerId: 'p5', name: 'Player 5');
    expect(latecomer.role, PlayerRole.villager);

    final afterLatecomer = await repo.watchGame(game.id).first;
    expect(afterLatecomer.mafia.map((p) => p.id).toSet(), mafiaIdsAtStart);
  });

  test('calling startGame explicitly after auto-start already fired is a harmless no-op', () async {
    final repo = LocalGameRepository();
    final game = await repo.createGame(
      locationTag: 'Test Office',
      minPlayers: 4,
      creatorId: 'p1',
      creatorName: 'Alice',
    );
    for (var i = 2; i <= 4; i++) {
      await repo.addPlayer(gameId: game.id, playerId: 'p$i', name: 'Player $i');
    }
    final beforeExplicitCall = await repo.watchGame(game.id).first;

    await repo.startGame(game.id); // should not throw, should not reshuffle roles

    final afterExplicitCall = await repo.watchGame(game.id).first;
    expect(afterExplicitCall.mafia.map((p) => p.id).toSet(),
        beforeExplicitCall.mafia.map((p) => p.id).toSet());
  });
}
