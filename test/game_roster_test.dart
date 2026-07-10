import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/data/local/local_game_repository.dart';

void main() {
  test('a player name must be unique within a game, case/whitespace insensitively', () async {
    final repo = LocalGameRepository();
    final game = await repo.createGame(
      locationTag: 'Test Office',
      minPlayers: 4,
      creatorId: 'p1',
      creatorName: 'Bob',
    );

    expect(
      () => repo.addPlayer(gameId: game.id, playerId: 'p2', name: 'Bob'),
      throwsStateError,
    );
    expect(
      () => repo.addPlayer(gameId: game.id, playerId: 'p3', name: ' bob '),
      throwsStateError,
    );

    // A distinct name still works fine.
    final added = await repo.addPlayer(gameId: game.id, playerId: 'p4', name: 'Carol');
    expect(added.name, 'Carol');

    // The same name is free to reuse in a *different* game.
    final otherGame = await repo.createGame(
      locationTag: 'Other Office',
      minPlayers: 4,
      creatorId: 'q1',
      creatorName: 'Someone Else',
    );
    final reused = await repo.addPlayer(gameId: otherGame.id, playerId: 'q2', name: 'Bob');
    expect(reused.name, 'Bob');
  });
}
