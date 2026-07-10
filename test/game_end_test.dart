import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/data/local/local_game_repository.dart';
import 'package:office_game_app/domain/models/game.dart';

void main() {
  test('villagers win the instant the last mafia member is unmasked', () async {
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
    expect(started.mafia, hasLength(1));
    final mafiaTarget = started.mafia.first;
    final voters = started.players.where((p) => p.id != mafiaTarget.id).toList();

    for (final voter in voters) {
      await repo.castVote(gameId: game.id, voterId: voter.id, targetPlayerId: mafiaTarget.id);
    }
    await repo.resolveVotesForDay(game.id);

    final ended = await repo.watchGame(game.id).first;
    expect(ended.status, GameStatus.ended);
    expect(ended.winner, GameWinner.villagers);
  });

  test('mafia win the instant recruitment brings them to parity', () async {
    final repo = LocalGameRepository();
    // 4 players, 1 mafia, 3 villagers. A permissive unlock threshold
    // means recruitment is available from the start (this test isn't
    // about the unlock ratio) — recruiting just one villager brings
    // mafia to 2, villagers down to 2: parity.
    final game = await repo.createGame(
      locationTag: 'Test Office',
      minPlayers: 4,
      creatorId: 'p1',
      creatorName: 'Alice',
      mafiaCount: 1,
      recruitmentUnlockThreshold: 1.0,
    );
    for (var i = 2; i <= 4; i++) {
      await repo.addPlayer(gameId: game.id, playerId: 'p$i', name: 'Player $i');
    }
    var current = await repo.watchGame(game.id).first;
    expect(current.mafia, hasLength(1));
    expect(current.recruitmentUnlocked, isTrue);

    final mafiaMember = current.mafia.first;
    final recruitTarget = current.villagers.first;
    await repo.proposeRecruitment(
      gameId: game.id,
      recruiterId: mafiaMember.id,
      targetPlayerId: recruitTarget.id,
      sign: 'a note under the keyboard',
    );
    final thread = await repo.watchMafiaThread(gameId: game.id, viewerId: mafiaMember.id).first;
    await repo.executeRecruitment(
      gameId: game.id,
      proposalId: thread.single.id,
      playerId: mafiaMember.id,
    );
    await repo.respondToRecruitment(gameId: game.id, playerId: recruitTarget.id, accept: true);

    current = await repo.watchGame(game.id).first;
    expect(current.status, GameStatus.ended);
    expect(current.winner, GameWinner.mafia);
  });

  test('a closed case rejects every further action', () async {
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
    final mafiaTarget = started.mafia.first;
    for (final voter in started.players.where((p) => p.id != mafiaTarget.id)) {
      await repo.castVote(gameId: game.id, voterId: voter.id, targetPlayerId: mafiaTarget.id);
    }
    await repo.resolveVotesForDay(game.id);

    final ended = await repo.watchGame(game.id).first;
    expect(ended.status, GameStatus.ended);
    final anyPlayer = ended.players.first;
    final anyOther = ended.players.firstWhere((p) => p.id != anyPlayer.id);

    expect(
      () => repo.castVote(gameId: game.id, voterId: anyPlayer.id, targetPlayerId: anyOther.id),
      throwsStateError,
    );
    expect(
      () => repo.addPlayer(gameId: game.id, playerId: 'latecomer', name: 'Latecomer'),
      throwsStateError,
    );
    expect(
      () => repo.logObservation(gameId: game.id, authorId: anyPlayer.id, text: 'too late'),
      throwsStateError,
    );
    expect(() => repo.resolveVotesForDay(game.id), throwsStateError);
  });

  test('leaving can itself tip the balance to a mafia win', () async {
    final repo = LocalGameRepository();
    // 6 players, 2 mafia, 4 villagers. Two villagers leaving brings it
    // to 2 mafia vs 2 villagers: parity.
    final game = await repo.createGame(
      locationTag: 'Test Office',
      minPlayers: 6,
      creatorId: 'p1',
      creatorName: 'Alice',
      mafiaCount: 2,
    );
    for (var i = 2; i <= 6; i++) {
      await repo.addPlayer(gameId: game.id, playerId: 'p$i', name: 'Player $i');
    }
    final started = await repo.watchGame(game.id).first;
    expect(started.mafia, hasLength(2));
    final departingVillagers = started.villagers.take(2).toList();

    await repo.leaveGame(gameId: game.id, playerId: departingVillagers[0].id);
    var mid = await repo.watchGame(game.id).first;
    expect(mid.status, GameStatus.active); // 2 mafia vs 3 living villagers, not yet parity

    await repo.leaveGame(gameId: game.id, playerId: departingVillagers[1].id);
    final ended = await repo.watchGame(game.id).first;
    expect(ended.status, GameStatus.ended);
    expect(ended.winner, GameWinner.mafia);
  });
}
