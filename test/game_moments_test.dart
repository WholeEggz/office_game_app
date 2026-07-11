import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/data/local/local_game_repository.dart';
import 'package:office_game_app/domain/models/game_moment.dart';

/// Every player gets a joinedCase moment the instant they're added
/// (creator or otherwise) — acknowledging it upfront in most tests below
/// keeps their fetch assertions focused on whatever happens *after* setup,
/// the same way a real player would already have seen "you joined" before
/// anything else in the case happens to them.
Future<void> _ackAll(LocalGameRepository repo, String gameId, Iterable<String> playerIds) async {
  for (final id in playerIds) {
    await repo.acknowledgeAllMoments(gameId: gameId, playerId: id);
  }
}

void main() {
  test('joining or creating a case records a joinedCase moment, round 1', () async {
    final repo = LocalGameRepository();
    final game = await repo.createGame(
      locationTag: 'Test Office',
      minPlayers: 4,
      creatorId: 'p1',
      creatorName: 'Alice',
    );
    final creatorMoments = await repo.fetchUnacknowledgedMoments(gameId: game.id, playerId: 'p1');
    expect(creatorMoments, hasLength(1));
    expect(creatorMoments.single.type, GameMomentType.joinedCase);
    expect(creatorMoments.single.round, 1);

    await repo.addPlayer(gameId: game.id, playerId: 'p2', name: 'Bob');
    final joinerMoments = await repo.fetchUnacknowledgedMoments(gameId: game.id, playerId: 'p2');
    expect(joinerMoments, hasLength(1));
    expect(joinerMoments.single.type, GameMomentType.joinedCase);
  });

  test('re-entering a case records reenteredCase, and only when explicitly called', () async {
    final repo = LocalGameRepository();
    final game = await repo.createGame(
      locationTag: 'Test Office',
      minPlayers: 4,
      creatorId: 'p1',
      creatorName: 'Alice',
    );
    await _ackAll(repo, game.id, ['p1']);

    expect(await repo.fetchUnacknowledgedMoments(gameId: game.id, playerId: 'p1'), isEmpty);

    await repo.recordReentry(gameId: game.id, playerId: 'p1');
    final moments = await repo.fetchUnacknowledgedMoments(gameId: game.id, playerId: 'p1');
    expect(moments, hasLength(1));
    expect(moments.single.type, GameMomentType.reenteredCase);
  });

  test(
      'correctly unmasking a mafia member rewards every voter who backed them, informs '
      'everyone else that an Informant was caught, and gives neither group the '
      'roundEnded fallback — the target gets neither (the stamp ceremony covers them)',
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
    final started = await repo.watchGame(game.id).first;
    await _ackAll(repo, game.id, started.players.map((p) => p.id));

    final target = started.mafia.first;
    final rewardedVoters = started.players.where((p) => p.id != target.id).take(3).toList();
    final bystanders = started.players
        .where((p) => p.id != target.id && !rewardedVoters.any((r) => r.id == p.id))
        .toList();
    expect(bystanders, isNotEmpty);

    for (final voter in rewardedVoters) {
      await repo.castVote(gameId: game.id, voterId: voter.id, targetPlayerId: target.id);
    }
    await repo.resolveVotesForDay(game.id);

    for (final voter in rewardedVoters) {
      final moments =
          await repo.fetchUnacknowledgedMoments(gameId: game.id, playerId: voter.id);
      expect(moments, hasLength(1));
      expect(moments.single.type, GameMomentType.correctVoteReward);
    }
    for (final p in bystanders) {
      final moments = await repo.fetchUnacknowledgedMoments(gameId: game.id, playerId: p.id);
      expect(moments, hasLength(1));
      expect(moments.single.type, GameMomentType.mafiaUnmaskedByOthers);
    }
    // The unmasked target isn't a "voter who backed them", and the stamp
    // ceremony (not a moment) covers their own discovery — they fall
    // through to the plain fallback.
    final targetMoments =
        await repo.fetchUnacknowledgedMoments(gameId: game.id, playerId: target.id);
    expect(targetMoments, hasLength(1));
    expect(targetMoments.single.type, GameMomentType.roundEnded);
  });

  test(
      'a round with nothing specific to report gives villagers the roundEnded '
      'fallback, and gives the still-uncaught mafia member survivedRoundAsMafia instead',
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
    final started = await repo.watchGame(game.id).first;
    await _ackAll(repo, game.id, started.players.map((p) => p.id));

    // No votes cast at all this round.
    await repo.resolveVotesForDay(game.id);

    for (final villager in started.villagers) {
      final moments =
          await repo.fetchUnacknowledgedMoments(gameId: game.id, playerId: villager.id);
      expect(moments, hasLength(1));
      expect(moments.single.type, GameMomentType.roundEnded);
      expect(moments.single.round, 1);
    }

    final mafiaMember = started.mafia.single;
    final mafiaMoments =
        await repo.fetchUnacknowledgedMoments(gameId: game.id, playerId: mafiaMember.id);
    expect(mafiaMoments, hasLength(1));
    expect(mafiaMoments.single.type, GameMomentType.survivedRoundAsMafia);
    expect(mafiaMoments.single.round, 1);
  });

  test(
      'villagers mistakenly voting out one of their own targets that villager, and only '
      'them — other villagers get the roundEnded fallback, the still-uncaught mafia '
      'member gets survivedRoundAsMafia', () async {
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
    final started = await repo.watchGame(game.id).first;
    await _ackAll(repo, game.id, started.players.map((p) => p.id));
    final target = started.villagers.first;

    for (final voter in started.players.where((p) => p.id != target.id)) {
      await repo.castVote(gameId: game.id, voterId: voter.id, targetPlayerId: target.id);
    }
    await repo.resolveVotesForDay(game.id);

    final targetMoments =
        await repo.fetchUnacknowledgedMoments(gameId: game.id, playerId: target.id);
    expect(targetMoments, hasLength(1));
    expect(targetMoments.single.type, GameMomentType.targetedByVillagers);

    for (final voter in started.villagers.where((p) => p.id != target.id)) {
      final moments =
          await repo.fetchUnacknowledgedMoments(gameId: game.id, playerId: voter.id);
      expect(moments, hasLength(1));
      expect(moments.single.type, GameMomentType.roundEnded);
    }

    final mafiaMember = started.mafia.single;
    final mafiaMoments =
        await repo.fetchUnacknowledgedMoments(gameId: game.id, playerId: mafiaMember.id);
    expect(mafiaMoments, hasLength(1));
    expect(mafiaMoments.single.type, GameMomentType.survivedRoundAsMafia);
  });

  test(
      "the mafia's elimination signal landing on a villager targets them specifically, "
      "and doesn't also give them the roundEnded fallback once the round resolves later",
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
    final started = await repo.watchGame(game.id).first;
    await _ackAll(repo, game.id, started.players.map((p) => p.id));
    final mafia = started.mafia.single;
    final target = started.villagers.first;

    await repo.proposeElimination(
      gameId: game.id,
      authorId: mafia.id,
      method: 'a note left on their monitor',
      targetPlayerId: target.id,
    );
    final proposalId =
        (await repo.watchMafiaThread(gameId: game.id, viewerId: mafia.id).first).single.id;
    await repo.executeElimination(gameId: game.id, proposalId: proposalId, playerId: mafia.id);

    final targetMomentsRightAfter =
        await repo.fetchUnacknowledgedMoments(gameId: game.id, playerId: target.id);
    expect(targetMomentsRightAfter, hasLength(1));
    expect(targetMomentsRightAfter.single.type, GameMomentType.targetedByMafia);

    // Acknowledge that one, then let the round resolve with nobody
    // voting — the earlier targeting shouldn't also produce a roundEnded
    // for the same round once it's actually acknowledged and re-fetched.
    await repo.acknowledgeAllMoments(gameId: game.id, playerId: target.id);
    await repo.resolveVotesForDay(game.id);
    final targetMomentsAfterResolve =
        await repo.fetchUnacknowledgedMoments(gameId: game.id, playerId: target.id);
    expect(targetMomentsAfterResolve, isEmpty);
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
    final started = await repo.watchGame(game.id).first;
    await _ackAll(repo, game.id, started.players.map((p) => p.id));
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
    await _ackAll(repo, game.id, ['p1', 'p2', 'p3', 'p4']);

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
