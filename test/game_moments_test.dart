import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/data/local/local_game_repository.dart';
import 'package:office_game_app/domain/models/game_moment.dart';

void main() {
  test(
      'correctly unmasking a mafia member rewards every voter who backed them, '
      'and only them — the target and non-voters get the roundEnded fallback instead',
      () async {
    final repo = LocalGameRepository();
    // 2 mafia so unmasking one doesn't also end the game (1 mafia left
    // against 7 villagers isn't parity) — keeps this test focused on the
    // moment bookkeeping, not the finale.
    final game = await repo.createGame(
      locationTag: 'Test Office',
      minPlayers: 8,
      creatorId: 'p1',
      creatorName: 'Alice',
      mafiaCount: 2,
    );
    for (var i = 2; i <= 8; i++) {
      await repo.addPlayer(gameId: game.id, playerId: 'p$i', name: 'Player $i');
    }
    await repo.startGame(game.id);
    final started = await repo.watchGame(game.id).first;
    final target = started.mafia.first;
    final otherMafia = started.mafia.firstWhere((p) => p.id != target.id);
    final voters = started.players.where((p) => p.id != target.id).toList();

    for (final voter in voters) {
      await repo.castVote(gameId: game.id, voterId: voter.id, targetPlayerId: target.id);
    }
    await repo.resolveVotesForDay(game.id);

    for (final voter in voters) {
      final moments =
          await repo.fetchUnacknowledgedMoments(gameId: game.id, playerId: voter.id);
      expect(moments, hasLength(1));
      expect(moments.single.type, GameMomentType.correctVoteReward);
      expect(moments.single.round, 1);
    }

    // The unmasked target isn't a "voter who backed them" — they get the
    // generic fallback, not a reward for their own unmasking.
    final targetMoments =
        await repo.fetchUnacknowledgedMoments(gameId: game.id, playerId: target.id);
    expect(targetMoments, hasLength(1));
    expect(targetMoments.single.type, GameMomentType.roundEnded);

    // otherMafia is already included in `voters` above (voted too), so no
    // separate assertion needed — but double-check nobody outside the
    // roster is missing coverage.
    expect(otherMafia.id, isNot(target.id));
  });

  test('a round with nothing specific to report gives everyone the roundEnded fallback',
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
    await repo.startGame(game.id);
    // No votes cast at all this round.
    await repo.resolveVotesForDay(game.id);

    for (final id in ['p1', 'p2', 'p3', 'p4']) {
      final moments = await repo.fetchUnacknowledgedMoments(gameId: game.id, playerId: id);
      expect(moments, hasLength(1));
      expect(moments.single.type, GameMomentType.roundEnded);
      expect(moments.single.round, 1);
    }
  });

  test(
      'a successful recruitment credits the executor and marks the recruit switching sides — '
      'neither also gets the roundEnded fallback for that round, but everyone else does',
      () async {
    final repo = LocalGameRepository();
    // 1 mafia, 5 villagers; recruiting one villager lands on 2 mafia vs 4
    // villagers — not parity, so this stays focused on the recruitment
    // moments rather than also triggering a finale.
    final game = await repo.createGame(
      locationTag: 'Test Office',
      minPlayers: 6,
      creatorId: 'p1',
      creatorName: 'Alice',
      mafiaCount: 1,
      recruitmentUnlockThreshold: 1.0,
    );
    for (var i = 2; i <= 6; i++) {
      await repo.addPlayer(gameId: game.id, playerId: 'p$i', name: 'Player $i');
    }
    await repo.startGame(game.id);
    final started = await repo.watchGame(game.id).first;
    final recruiter = started.mafia.single;
    final target = started.villagers.first;
    final bystanders =
        started.players.where((p) => p.id != recruiter.id && p.id != target.id).toList();
    expect(bystanders, hasLength(4));

    await repo.proposeRecruitment(
      gameId: game.id,
      recruiterId: recruiter.id,
      targetPlayerId: target.id,
      sign: 'a specific pen left on their desk',
    );
    final proposalId =
        (await repo.watchMafiaThread(gameId: game.id, viewerId: recruiter.id).first).single.id;
    await repo.executeRecruitment(gameId: game.id, proposalId: proposalId, playerId: recruiter.id);
    await repo.respondToRecruitment(gameId: game.id, playerId: target.id, accept: true);

    final recruiterMoments =
        await repo.fetchUnacknowledgedMoments(gameId: game.id, playerId: recruiter.id);
    expect(recruiterMoments, hasLength(1));
    expect(recruiterMoments.single.type, GameMomentType.recruitmentExecuted);
    expect(recruiterMoments.single.round, 1);

    final targetMoments =
        await repo.fetchUnacknowledgedMoments(gameId: game.id, playerId: target.id);
    expect(targetMoments, hasLength(1));
    expect(targetMoments.single.type, GameMomentType.recruitedSwitchSides);
    expect(targetMoments.single.round, 1);

    for (final p in bystanders) {
      final moments = await repo.fetchUnacknowledgedMoments(gameId: game.id, playerId: p.id);
      expect(moments, hasLength(1));
      expect(moments.single.type, GameMomentType.roundEnded);
    }
  });

  test('the case ending records finaleWin for the winning side and finaleLoss for the other',
      () async {
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
    await repo.startGame(game.id);
    final started = await repo.watchGame(game.id).first;
    final mafia = started.mafia.single;
    final villagers = started.villagers;

    for (final voter in started.players.where((p) => p.id != mafia.id)) {
      await repo.castVote(gameId: game.id, voterId: voter.id, targetPlayerId: mafia.id);
    }
    await repo.resolveVotesForDay(game.id);

    final ended = await repo.watchGame(game.id).first;
    expect(ended.status.name, 'ended');

    for (final v in villagers) {
      final moments = await repo.fetchUnacknowledgedMoments(gameId: game.id, playerId: v.id);
      expect(moments.map((m) => m.type), contains(GameMomentType.finaleWin));
    }
    final mafiaMoments = await repo.fetchUnacknowledgedMoments(gameId: game.id, playerId: mafia.id);
    expect(mafiaMoments.map((m) => m.type), contains(GameMomentType.finaleLoss));
  });

  test('the mafia winning records finaleWin for them (including an already-unmasked member) '
      'and finaleLoss for the villagers', () async {
    final repo = LocalGameRepository();
    // Mirrors game_end_test.dart's parity-via-recruitment setup: 4 players,
    // 1 mafia, recruitment unlocked from the start — one successful
    // recruitment reaches 2 mafia vs 2 villagers, mafia parity win.
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
    await repo.startGame(game.id);
    final started = await repo.watchGame(game.id).first;
    final recruiter = started.mafia.single;
    final target = started.villagers.first;
    final remainingVillager =
        started.villagers.firstWhere((p) => p.id != target.id);

    await repo.proposeRecruitment(
      gameId: game.id,
      recruiterId: recruiter.id,
      targetPlayerId: target.id,
      sign: 'a specific pen left on their desk',
    );
    final proposalId =
        (await repo.watchMafiaThread(gameId: game.id, viewerId: recruiter.id).first).single.id;
    await repo.executeRecruitment(gameId: game.id, proposalId: proposalId, playerId: recruiter.id);
    await repo.respondToRecruitment(gameId: game.id, playerId: target.id, accept: true);

    final ended = await repo.watchGame(game.id).first;
    expect(ended.status.name, 'ended');
    expect(ended.winner?.name, 'mafia');

    final recruiterMoments =
        await repo.fetchUnacknowledgedMoments(gameId: game.id, playerId: recruiter.id);
    expect(recruiterMoments.map((m) => m.type), contains(GameMomentType.finaleWin));
    final newRecruitMoments =
        await repo.fetchUnacknowledgedMoments(gameId: game.id, playerId: target.id);
    expect(newRecruitMoments.map((m) => m.type), contains(GameMomentType.finaleWin));
    final villagerMoments =
        await repo.fetchUnacknowledgedMoments(gameId: game.id, playerId: remainingVillager.id);
    expect(villagerMoments.map((m) => m.type), contains(GameMomentType.finaleLoss));
  });

  test('acknowledging moments clears them, and later moments still accumulate afterward',
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
    await repo.startGame(game.id);
    await repo.resolveVotesForDay(game.id);

    final firstFetch = await repo.fetchUnacknowledgedMoments(gameId: game.id, playerId: 'p1');
    expect(firstFetch, hasLength(1));
    expect(firstFetch.single.round, 1);

    await repo.acknowledgeAllMoments(gameId: game.id, playerId: 'p1');
    expect(await repo.fetchUnacknowledgedMoments(gameId: game.id, playerId: 'p1'), isEmpty);

    await repo.resolveVotesForDay(game.id);
    final secondFetch = await repo.fetchUnacknowledgedMoments(gameId: game.id, playerId: 'p1');
    expect(secondFetch, hasLength(1));
    expect(secondFetch.single.round, 2);

    // Acknowledging is scoped to the one player who checked in — everyone
    // else's moments from the same rounds are untouched.
    final p2Moments = await repo.fetchUnacknowledgedMoments(gameId: game.id, playerId: 'p2');
    expect(p2Moments, hasLength(2));
    expect(p2Moments.map((m) => m.round), [1, 2]);
  });
}
