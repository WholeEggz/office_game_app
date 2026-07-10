import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/data/local/local_game_repository.dart';

void main() {
  test('a custom mafia count changes how many mafia are drawn at start', () async {
    final repo = LocalGameRepository();
    final game = await repo.createGame(
      locationTag: 'Custom Case',
      minPlayers: 4,
      creatorId: 'p1',
      creatorName: 'Alice',
      mafiaCount: 3, // instead of the default's 2
      executionWindow: const Duration(minutes: 30),
    );
    for (var i = 2; i <= 4; i++) {
      await repo.addPlayer(gameId: game.id, playerId: 'p$i', name: 'Player $i');
    }
    await repo.startGame(game.id);

    final started = await repo.watchGame(game.id).first;
    expect(started.mafiaCount, 3);
    expect(started.executionWindow, const Duration(minutes: 30));
    expect(started.mafia, hasLength(3));
  });

  test('a custom recruitment threshold unlocks at a ratio the default would keep locked',
      () async {
    final repo = LocalGameRepository();
    final game = await repo.createGame(
      locationTag: 'Custom Case',
      minPlayers: 8,
      creatorId: 'p1',
      creatorName: 'Alice',
      mafiaCount: 2,
      recruitmentUnlockThreshold: 0.4,
    );
    for (var i = 2; i <= 8; i++) {
      await repo.addPlayer(gameId: game.id, playerId: 'p$i', name: 'Player $i');
    }
    await repo.startGame(game.id);

    final started = await repo.watchGame(game.id).first;
    // 2 mafia, 6 villagers — a 1:3 ratio (~0.33). The default 0.2
    // threshold would keep this locked; the custom 0.4 threshold
    // unlocks it.
    expect(started.mafia, hasLength(2));
    expect(started.recruitmentUnlocked, isTrue);
  });

  test('omitting settings keeps the original defaults', () async {
    final repo = LocalGameRepository();
    final game = await repo.createGame(
      locationTag: 'Default Case',
      minPlayers: 4,
      creatorId: 'p1',
      creatorName: 'Alice',
    );
    expect(game.mafiaCount, 1);
    expect(game.recruitmentUnlockThreshold, 0.2);
    expect(game.executionWindow, const Duration(hours: 1));
  });
}
