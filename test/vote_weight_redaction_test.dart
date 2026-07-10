import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/data/local/local_game_repository.dart';
import 'package:office_game_app/domain/models/player.dart';

void main() {
  test('an eroded villager\'s weight is only visible to themselves, never to other viewers', () async {
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

    // Everyone piles onto one villager, eroding their real weight to 2.
    for (final voter in started.players) {
      if (voter.id == villagerTarget.id) continue;
      await repo.castVote(gameId: game.id, voterId: voter.id, targetPlayerId: villagerTarget.id);
    }
    await repo.resolveVotesForDay(game.id);

    // The unredacted view (debug-only in the real UI) shows the true drop.
    final resolvedGame = await repo.watchGame(game.id).first;
    expect(resolvedGame.playerById(villagerTarget.id)!.voteWeight, lessThan(3));

    // The eroded player sees their own real weight...
    final ownView = await repo
        .watchVisiblePlayers(gameId: game.id, viewerId: villagerTarget.id)
        .first;
    expect(ownView.firstWhere((p) => p.id == villagerTarget.id).voteWeight, lessThan(3));

    // ...but every other viewer sees them still at the untouched starting
    // weight — a live number would otherwise leak "this player has been
    // confirmed not mafia" the moment it first moved.
    final otherViewerId = started.players.firstWhere((p) => p.id != villagerTarget.id).id;
    final othersView =
        await repo.watchVisiblePlayers(gameId: game.id, viewerId: otherViewerId).first;
    expect(othersView.firstWhere((p) => p.id == villagerTarget.id).voteWeight, 3);
  });
}
