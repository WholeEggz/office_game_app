import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/data/local/local_game_repository.dart';
import 'package:office_game_app/domain/models/player.dart';

void main() {
  test('voting for a villager erodes their weight, mirroring a mafia elimination', () async {
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
    final villagerTarget =
        started.villagers.firstWhere((p) => p.id != 'p1' && p.role == PlayerRole.villager);

    // Everyone piles onto one villager instead of a mafia member.
    for (final voter in started.players) {
      if (voter.id == villagerTarget.id) continue;
      await repo.castVote(gameId: game.id, voterId: voter.id, targetPlayerId: villagerTarget.id);
    }
    await repo.resolveVotesForDay(game.id);

    final resolved = await repo.watchGame(game.id).first;
    final target = resolved.playerById(villagerTarget.id)!;
    expect(target.role, PlayerRole.villager);
    expect(target.voteWeight, villagerTarget.voteWeight - 1);
    // Voting for a villager isn't rewarded the way catching mafia is —
    // only the target's own weight moves.
    for (final voter in resolved.players) {
      if (voter.id == villagerTarget.id) continue;
      final before = started.playerById(voter.id)!.voteWeight;
      expect(voter.voteWeight, before);
    }
  });

  test('repeatedly voting out the same villager can floor their weight at 0, never negative', () async {
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
    final villagerTarget =
        started.villagers.firstWhere((p) => p.id != 'p1' && p.role == PlayerRole.villager);

    // Three rounds of the same villager taking the plurality — weight
    // 3 -> 2 -> 1 -> 0 -> (stays 0).
    for (var round = 0; round < 4; round++) {
      final current = await repo.watchGame(game.id).first;
      for (final voter in current.players) {
        if (voter.id == villagerTarget.id) continue;
        await repo.castVote(gameId: game.id, voterId: voter.id, targetPlayerId: villagerTarget.id);
      }
      await repo.resolveVotesForDay(game.id);
    }

    final finalGame = await repo.watchGame(game.id).first;
    expect(finalGame.playerById(villagerTarget.id)!.voteWeight, 0);
  });

  test('voting for mafia still unmasks them and rewards voters, unchanged', () async {
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
    final mafiaTarget = started.mafia.first;
    final voters = started.players.where((p) => p.id != mafiaTarget.id).toList();

    for (final voter in voters) {
      await repo.castVote(gameId: game.id, voterId: voter.id, targetPlayerId: mafiaTarget.id);
    }
    await repo.resolveVotesForDay(game.id);

    final resolved = await repo.watchGame(game.id).first;
    final target = resolved.playerById(mafiaTarget.id)!;
    expect(target.role, PlayerRole.villager);
    expect(target.wasUnmasked, isTrue);
    for (final voter in voters) {
      final before = started.playerById(voter.id)!.voteWeight;
      expect(resolved.playerById(voter.id)!.voteWeight, before + 1);
    }
  });
}
