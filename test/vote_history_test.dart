import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/data/local/local_game_repository.dart';

void main() {
  test('vote history survives round resolution, unlike current-round votes', () async {
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
    await repo.startGame(game.id);
    // Mafia is assigned randomly — pick a guaranteed villager to vote for
    // so the round's outcome is never an unmask (which, with only 1 mafia
    // by default, would end the game and derail this test, which is about
    // vote history bookkeeping, not win conditions).
    final started = await repo.watchGame(game.id).first;
    final target = started.villagers.firstWhere((p) => p.id != 'p1');
    final voters = started.players.where((p) => p.id != 'p1' && p.id != target.id).take(2);

    await repo.castVote(gameId: game.id, voterId: 'p1', targetPlayerId: target.id);
    for (final voter in voters) {
      await repo.castVote(gameId: game.id, voterId: voter.id, targetPlayerId: target.id);
    }
    final castCount = 1 + voters.length;
    await repo.resolveVotesForDay(game.id);

    // Round 2: the current-round view is empty again...
    final currentRoundVotes = await repo.watchCurrentRoundVotes(game.id).first;
    expect(currentRoundVotes, isEmpty);

    // ...but the full history still remembers round 1's votes.
    final history = await repo.watchVoteHistory(game.id).first;
    expect(history, hasLength(castCount));
    expect(history.every((v) => v.round == 1), isTrue);

    // Cast a new vote in round 2 and confirm history accumulates rather
    // than replacing.
    final anotherVoter = started.players.firstWhere((p) => p.id != 'p1');
    await repo.castVote(gameId: game.id, voterId: 'p1', targetPlayerId: anotherVoter.id);
    final historyAfterRound2Vote = await repo.watchVoteHistory(game.id).first;
    expect(historyAfterRound2Vote, hasLength(castCount + 1));
  });

  test('changing your vote within the same round does not create duplicate history entries', () async {
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
    await repo.startGame(game.id);
    final started = await repo.watchGame(game.id).first;
    // Two distinct villagers to vote for, so neither vote can accidentally
    // unmask the (randomly-assigned) mafia member and end the game.
    final villagers =
        started.villagers.where((p) => p.id != 'p1').map((p) => p.id).take(2).toList();

    await repo.castVote(gameId: game.id, voterId: 'p1', targetPlayerId: villagers[0]);
    await repo.castVote(gameId: game.id, voterId: 'p1', targetPlayerId: villagers[1]);

    final history = await repo.watchVoteHistory(game.id).first;
    expect(history, hasLength(1));
    expect(history.single.targetPlayerId, villagers[1]);
  });
}
