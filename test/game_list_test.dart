import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/data/local/local_game_repository.dart';
import 'package:office_game_app/domain/models/player.dart';

void main() {
  test('watchGames lists every game and redacts roles for a browsing outsider', () async {
    final repo = LocalGameRepository();
    final game = await repo.createGame(
      locationTag: 'Third Floor',
      minPlayers: 4,
      creatorId: 'p1',
      creatorName: 'Alice',
    );
    for (var i = 2; i <= 4; i++) {
      await repo.addPlayer(gameId: game.id, playerId: 'p$i', name: 'Player $i');
    }
    await repo.startGame(game.id);

    // An outsider who hasn't joined yet still sees the game (to browse and
    // join it), but every player in it reads as a villager — no peeking at
    // real mafia membership before you've even joined.
    final browsed = await repo.watchGames(viewerId: 'outsider').first;
    expect(browsed, hasLength(1));
    expect(browsed.single.players.every((p) => p.role == PlayerRole.villager), isTrue);

    // A new game shows up in the list without needing a fresh subscription.
    await repo.createGame(
      locationTag: 'Fifth Floor',
      minPlayers: 4,
      creatorId: 'q1',
      creatorName: 'Bea',
    );
    final afterSecondGame = await repo.watchGames(viewerId: 'outsider').first;
    expect(afterSecondGame, hasLength(2));
  });

  test('watchGames still shows the viewer their own real role', () async {
    final repo = LocalGameRepository();
    final game = await repo.createGame(
      locationTag: 'Third Floor',
      minPlayers: 4,
      creatorId: 'p1',
      creatorName: 'Alice',
    );
    for (var i = 2; i <= 4; i++) {
      await repo.addPlayer(gameId: game.id, playerId: 'p$i', name: 'Player $i');
    }
    await repo.startGame(game.id);
    final started = await repo.watchGame(game.id).first;
    final self = started.players.first;

    final ownView = await repo.watchGames(viewerId: self.id).first;
    final seenSelf = ownView.single.players.firstWhere((p) => p.id == self.id);
    expect(seenSelf.role, self.role);
  });
}
