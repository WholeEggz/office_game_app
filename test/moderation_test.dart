import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/data/local/local_game_repository.dart';

void main() {
  test('reportPlayer requires both reporter and target to be in the game', () async {
    final repo = LocalGameRepository();
    final game = await repo.createGame(
      locationTag: 'Test Office',
      minPlayers: 4,
      creatorId: 'p1',
      creatorName: 'Alice',
    );
    await repo.addPlayer(gameId: game.id, playerId: 'p2', name: 'Ben');

    expect(
      () => repo.reportPlayer(
        gameId: game.id,
        reporterId: 'not-in-game',
        targetPlayerId: 'p2',
        reason: 'spam',
      ),
      throwsStateError,
    );
    expect(
      () => repo.reportPlayer(
        gameId: game.id,
        reporterId: 'p1',
        targetPlayerId: 'not-in-game',
        reason: 'spam',
      ),
      throwsStateError,
    );

    // A valid report against a real player doesn't throw, and (unlike
    // gameplay actions) doesn't require the game to be active/recruiting
    // specifically — reporting is a safety action, not a game action.
    await repo.reportPlayer(
      gameId: game.id,
      reporterId: 'p1',
      targetPlayerId: 'p2',
      reason: 'inappropriate name',
    );
  });

  test('blockPlayer/unblockPlayer are per-viewer and reversible', () async {
    final repo = LocalGameRepository();
    final game = await repo.createGame(
      locationTag: 'Test Office',
      minPlayers: 4,
      creatorId: 'p1',
      creatorName: 'Alice',
    );
    await repo.addPlayer(gameId: game.id, playerId: 'p2', name: 'Ben');
    await repo.addPlayer(gameId: game.id, playerId: 'p3', name: 'Cara');

    expect(
      await repo.watchBlockedPlayerIds(gameId: game.id, viewerId: 'p1').first,
      isEmpty,
    );

    await repo.blockPlayer(gameId: game.id, viewerId: 'p1', blockedPlayerId: 'p2');
    expect(
      await repo.watchBlockedPlayerIds(gameId: game.id, viewerId: 'p1').first,
      {'p2'},
    );

    // Someone else's block list is untouched — this is a per-viewer
    // preference, not a game-truth change everyone shares.
    expect(
      await repo.watchBlockedPlayerIds(gameId: game.id, viewerId: 'p3').first,
      isEmpty,
    );

    await repo.unblockPlayer(gameId: game.id, viewerId: 'p1', blockedPlayerId: 'p2');
    expect(
      await repo.watchBlockedPlayerIds(gameId: game.id, viewerId: 'p1').first,
      isEmpty,
    );
  });

  test('watchBlockedPlayerIds emits live updates as blocks change', () async {
    final repo = LocalGameRepository();
    final game = await repo.createGame(
      locationTag: 'Test Office',
      minPlayers: 4,
      creatorId: 'p1',
      creatorName: 'Alice',
    );
    await repo.addPlayer(gameId: game.id, playerId: 'p2', name: 'Ben');

    final emissions = <Set<String>>[];
    final sub = repo.watchBlockedPlayerIds(gameId: game.id, viewerId: 'p1').listen(emissions.add);
    await Future<void>.delayed(Duration.zero);

    await repo.blockPlayer(gameId: game.id, viewerId: 'p1', blockedPlayerId: 'p2');
    await Future<void>.delayed(Duration.zero);

    await sub.cancel();
    expect(emissions.last, {'p2'});
  });
}
