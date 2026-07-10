import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/data/local/local_game_repository.dart';
import 'package:office_game_app/domain/models/player.dart';

void main() {
  test('a departed player can no longer vote or be voted for, but stays in the roster', () async {
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

    await repo.leaveGame(gameId: game.id, playerId: 'p2');

    final afterLeaving = await repo.watchGame(game.id).first;
    final departed = afterLeaving.playerById('p2')!;
    expect(departed.hasLeft, isTrue);
    // Still resolvable by id — history involving them shouldn't collapse
    // to "someone".
    expect(afterLeaving.players.map((p) => p.id), contains('p2'));

    expect(
      () => repo.castVote(gameId: game.id, voterId: 'p2', targetPlayerId: 'p3'),
      throwsStateError,
    );
    expect(
      () => repo.castVote(gameId: game.id, voterId: 'p3', targetPlayerId: 'p2'),
      throwsStateError,
    );
  });

  test('leaving is rejected for a player who was never in the game', () async {
    final repo = LocalGameRepository();
    final game = await repo.createGame(
      locationTag: 'Test Office',
      minPlayers: 1,
      creatorId: 'p1',
      creatorName: 'Alice',
    );
    expect(
      () => repo.leaveGame(gameId: game.id, playerId: 'ghost'),
      throwsStateError,
    );
  });

  test('a departed mafia member no longer counts toward proposal agreement', () async {
    final repo = LocalGameRepository();
    final game = await repo.createGame(
      locationTag: 'Test Office',
      minPlayers: 6,
      creatorId: 'p1',
      creatorName: 'Alice',
      // 6 players, 2 mafia, 4 villagers: two mafia to require agreement
      // from both, while staying well clear of the mafia-parity win
      // condition this test isn't about.
      mafiaCount: 2,
    );
    for (var i = 2; i <= 6; i++) {
      await repo.addPlayer(gameId: game.id, playerId: 'p$i', name: 'Player $i');
    }
    final started = await repo.watchGame(game.id).first;
    final mafiaIds = started.mafia.map((p) => p.id).toList();
    expect(mafiaIds, hasLength(2));
    final proposer = mafiaIds.first;
    final otherMafia = mafiaIds.last;
    final target = started.villagers.first;

    await repo.proposeElimination(
      gameId: game.id,
      authorId: proposer,
      method: 'a note on the monitor',
      targetPlayerId: target.id,
    );
    // Still pending — the other active mafia member hasn't accepted yet.
    var afterPropose = await repo.watchMafiaThread(gameId: game.id, viewerId: proposer).first;
    expect(afterPropose.single.agreedAt, isNull);

    // The other mafia member leaves instead of ever responding.
    await repo.leaveGame(gameId: game.id, playerId: otherMafia);

    final afterLeaving = await repo.watchMafiaThread(gameId: game.id, viewerId: proposer).first;
    expect(afterLeaving.single.agreedAt, isNotNull);
  });

  test('mafia inactive status auto-reactivates after 24 hours', () {
    fakeAsync((async) {
      final repo = LocalGameRepository();
      late String gameId;
      late String mafiaId;

      repo
          .createGame(
            locationTag: 'Test Office',
            minPlayers: 4,
            creatorId: 'p1',
            creatorName: 'Alice',
          )
          .then((game) => gameId = game.id);
      async.flushMicrotasks();

      for (var i = 2; i <= 4; i++) {
        repo.addPlayer(gameId: gameId, playerId: 'p$i', name: 'Player $i');
        async.flushMicrotasks();
      }

      repo.watchGame(gameId).first.then((game) => mafiaId = game.mafia.first.id);
      async.flushMicrotasks();

      repo.setMemberActive(gameId: gameId, playerId: mafiaId, isActive: false);
      async.flushMicrotasks();

      bool? isActiveNow;
      repo.watchGame(gameId).first.then((game) => isActiveNow = game.playerById(mafiaId)!.isActive);
      async.flushMicrotasks();
      expect(isActiveNow, isFalse);

      async.elapse(const Duration(hours: 23));
      bool? stillInactive;
      repo.watchGame(gameId).first.then((game) => stillInactive = game.playerById(mafiaId)!.isActive);
      async.flushMicrotasks();
      expect(stillInactive, isFalse);

      async.elapse(const Duration(hours: 2)); // total 25h elapsed
      bool? reactivated;
      repo.watchGame(gameId).first.then((game) => reactivated = game.playerById(mafiaId)!.isActive);
      async.flushMicrotasks();
      expect(reactivated, isTrue);
    });
  });

  test('leaving cancels a pending inactivity auto-reactivation timer', () {
    fakeAsync((async) {
      final repo = LocalGameRepository();
      late String gameId;
      late String mafiaId;

      repo
          .createGame(
            locationTag: 'Test Office',
            minPlayers: 4,
            creatorId: 'p1',
            creatorName: 'Alice',
          )
          .then((game) => gameId = game.id);
      async.flushMicrotasks();

      for (var i = 2; i <= 4; i++) {
        repo.addPlayer(gameId: gameId, playerId: 'p$i', name: 'Player $i');
        async.flushMicrotasks();
      }

      repo.watchGame(gameId).first.then((game) => mafiaId = game.mafia.first.id);
      async.flushMicrotasks();

      repo.setMemberActive(gameId: gameId, playerId: mafiaId, isActive: false);
      async.flushMicrotasks();
      repo.leaveGame(gameId: gameId, playerId: mafiaId);
      async.flushMicrotasks();

      // No leftover timer should fire and crash or otherwise misbehave.
      async.elapse(const Duration(hours: 25));

      Player? departed;
      repo.watchGame(gameId).first.then((game) => departed = game.playerById(mafiaId));
      async.flushMicrotasks();
      expect(departed!.hasLeft, isTrue);
    });
  });
}
