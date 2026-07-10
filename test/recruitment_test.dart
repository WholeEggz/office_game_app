import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/data/local/local_game_repository.dart';
import 'package:office_game_app/domain/models/game.dart';
import 'package:office_game_app/domain/models/mafia_thread_entry.dart';
import 'package:office_game_app/domain/models/player.dart';

/// Recruitment only unlocks once mafia are *thin* relative to villagers
/// (ratio drops to ~1:5 or lower — section 8), not while mafia are already
/// well-stocked. A fresh 12-player game draws 3 mafia / 9 villagers
/// (3/9 = 0.33), which is still locked — so this helper plays out one real
/// vote round that correctly unmasks a mafia member, thinning mafia to 2
/// and growing villagers to 10 (2/10 = 0.2), landing exactly on the
/// "roughly 1:5" threshold and leaving 2 mafia for multi-member-agreement
/// tests.
Future<({Game game, String authorId, String otherMafiaId, List<String> villagerIds})>
    _gameWithRecruitmentUnlocked(LocalGameRepository repo) async {
  final game = await repo.createGame(
    locationTag: 'Test Office',
    minPlayers: 12,
    creatorId: 'p1',
    creatorName: 'Alice',
    mafiaCount: 3,
  );
  for (var i = 2; i <= 12; i++) {
    await repo.addPlayer(gameId: game.id, playerId: 'p$i', name: 'Player $i');
  }
  await repo.startGame(game.id);
  final started = await repo.watchGame(game.id).first;
  final mafiaIds = started.mafia.map((p) => p.id).toList();
  expect(mafiaIds, hasLength(3));
  expect(started.recruitmentUnlocked, isFalse);

  final unmaskTarget = mafiaIds.first;
  for (final villager in started.villagers) {
    await repo.castVote(gameId: game.id, voterId: villager.id, targetPlayerId: unmaskTarget);
  }
  await repo.resolveVotesForDay(game.id);

  final afterUnmask = await repo.watchGame(game.id).first;
  final remainingMafiaIds = afterUnmask.mafia.map((p) => p.id).toList();
  expect(remainingMafiaIds, hasLength(2));
  expect(afterUnmask.recruitmentUnlocked, isTrue);

  return (
    game: afterUnmask,
    authorId: remainingMafiaIds[0],
    otherMafiaId: remainingMafiaIds[1],
    villagerIds: afterUnmask.villagers.map((p) => p.id).toList(),
  );
}

void main() {
  test('recruitment stays locked while mafia are not thin relative to villagers', () async {
    final repo = LocalGameRepository();
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
    // 2 mafia, 6 villagers: 2/6 = 0.33, well above the 1:5 (0.2) threshold,
    // so still locked.
    expect(started.mafia, hasLength(2));
    expect(started.recruitmentUnlocked, isFalse);

    expect(
      () => repo.proposeRecruitment(
        gameId: game.id,
        recruiterId: started.mafia.first.id,
        targetPlayerId: started.villagers.first.id,
        sign: 'a specific pen left on their desk',
      ),
      throwsStateError,
    );
  });

  test('a full-strength villager (not just weight 0) can be recruited', () async {
    final repo = LocalGameRepository();
    final setup = await _gameWithRecruitmentUnlocked(repo);
    final gameId = setup.game.id;
    final target = setup.villagerIds.first;
    // Every villager gained +1 for correctly voting out the unmasked
    // mafia member in the setup helper, so they're above the old (now
    // removed) weight-0 requirement — the point of this test.
    expect(setup.game.playerById(target)!.voteWeight, greaterThan(0));

    await repo.proposeRecruitment(
      gameId: gameId,
      recruiterId: setup.authorId,
      targetPlayerId: target,
      sign: 'a specific pen left on their desk',
    );

    final entry =
        (await repo.watchMafiaThread(gameId: gameId, viewerId: setup.authorId).first).single;
    expect(entry.type, MafiaThreadEntryType.recruitment);
    expect(entry.agreedAt, isNull);

    // Still just pending — nothing public yet.
    final gameWhilePending = await repo.watchGame(gameId).first;
    expect(gameWhilePending.recruitmentSignDescription, isNull);
  });

  test('agreement reveals the sign publicly; only execution reaches the target', () async {
    final repo = LocalGameRepository();
    final setup = await _gameWithRecruitmentUnlocked(repo);
    final gameId = setup.game.id;
    final target = setup.villagerIds.first;

    await repo.proposeRecruitment(
      gameId: gameId,
      recruiterId: setup.authorId,
      targetPlayerId: target,
      sign: 'a specific pen left on their desk',
    );
    final proposalId =
        (await repo.watchMafiaThread(gameId: gameId, viewerId: setup.authorId).first).single.id;

    await repo.acceptRecruitmentProposal(
      gameId: gameId,
      proposalId: proposalId,
      playerId: setup.otherMafiaId,
    );
    final agreed =
        (await repo.watchMafiaThread(gameId: gameId, viewerId: setup.authorId).first).single;
    expect(agreed.agreedAt, isNotNull);

    // Agreement puts the sign in front of everyone (section 6, mirrored
    // for recruitment) but the target doesn't see an offer yet.
    final gameAfterAgreement = await repo.watchGame(gameId).first;
    expect(gameAfterAgreement.recruitmentSignDescription, 'a specific pen left on their desk');
    expect(gameAfterAgreement.recruitmentSignExecuted, isFalse);
    expect(gameAfterAgreement.playerById(target)!.pendingRecruiterId, isNull);

    // The *other* mafia member (not the original proposer) delivers it.
    await repo.executeRecruitment(
      gameId: gameId,
      proposalId: proposalId,
      playerId: setup.otherMafiaId,
    );
    final gameAfterExecute = await repo.watchGame(gameId).first;
    expect(gameAfterExecute.recruitmentSignExecuted, isTrue);
    expect(gameAfterExecute.playerById(target)!.pendingRecruiterId, setup.otherMafiaId);
  });

  test('a non-target responding is told plainly it was not them; nothing else changes', () async {
    final repo = LocalGameRepository();
    final setup = await _gameWithRecruitmentUnlocked(repo);
    final gameId = setup.game.id;
    final target = setup.villagerIds.first;
    final roundBefore = setup.game.currentRound;

    await repo.proposeRecruitment(
      gameId: gameId,
      recruiterId: setup.authorId,
      targetPlayerId: target,
      sign: 'a specific pen left on their desk',
    );
    final proposalId =
        (await repo.watchMafiaThread(gameId: gameId, viewerId: setup.authorId).first).single.id;
    await repo.acceptRecruitmentProposal(
      gameId: gameId,
      proposalId: proposalId,
      playerId: setup.otherMafiaId,
    );
    await repo.executeRecruitment(
      gameId: gameId,
      proposalId: proposalId,
      playerId: setup.authorId,
    );

    final someoneElse = setup.villagerIds.firstWhere((id) => id != target);
    final wasTarget =
        await repo.respondToRecruitment(gameId: gameId, playerId: someoneElse, accept: true);
    expect(wasTarget, isFalse);

    final gameAfterWrongGuess = await repo.watchGame(gameId).first;
    expect(gameAfterWrongGuess.playerById(someoneElse)!.role, PlayerRole.villager);
    expect(gameAfterWrongGuess.recruitmentSignConfirmed, isFalse);
    expect(gameAfterWrongGuess.currentRound, roundBefore);
  });

  test('the real target accepting joins mafia, credits the executor, and ends the round', () async {
    final repo = LocalGameRepository();
    final setup = await _gameWithRecruitmentUnlocked(repo);
    final gameId = setup.game.id;
    final target = setup.villagerIds.first;
    final roundBefore = setup.game.currentRound;

    await repo.proposeRecruitment(
      gameId: gameId,
      recruiterId: setup.authorId,
      targetPlayerId: target,
      sign: 'a specific pen left on their desk',
    );
    final proposalId =
        (await repo.watchMafiaThread(gameId: gameId, viewerId: setup.authorId).first).single.id;
    await repo.acceptRecruitmentProposal(
      gameId: gameId,
      proposalId: proposalId,
      playerId: setup.otherMafiaId,
    );
    // The *other* mafia member (not the original proposer) delivers it.
    await repo.executeRecruitment(
      gameId: gameId,
      proposalId: proposalId,
      playerId: setup.otherMafiaId,
    );

    final wasTarget =
        await repo.respondToRecruitment(gameId: gameId, playerId: target, accept: true);
    expect(wasTarget, isTrue);

    final finalGame = await repo.watchGame(gameId).first;
    final recruit = finalGame.playerById(target)!;
    expect(recruit.role, PlayerRole.mafia);
    // The executor (who actually delivered the pitch), not the original
    // proposer, is recorded as the recruiter.
    expect(recruit.recruiterId, setup.otherMafiaId);
    expect(finalGame.playerById(setup.otherMafiaId)!.recruitedPlayerIds, contains(target));

    final resolvedEntry =
        (await repo.watchMafiaThread(gameId: gameId, viewerId: setup.authorId).first).single;
    expect(resolvedEntry.recruitmentAccepted, isTrue);
    expect(resolvedEntry.confirmedAt, isNotNull);

    // Mirrors acknowledgeEliminationSignal: the real target responding
    // ends the round and clears the public signal for the fresh one.
    expect(finalGame.currentRound, roundBefore + 1);
    expect(finalGame.recruitmentSignDescription, isNull);
    expect(finalGame.recruitmentSignExecuted, isFalse);
    expect(finalGame.recruitmentSignConfirmed, isFalse);
  });

  test('declining leaves the target a villager, ends the round, and frees the slot', () async {
    final repo = LocalGameRepository();
    final setup = await _gameWithRecruitmentUnlocked(repo);
    final gameId = setup.game.id;
    final target = setup.villagerIds.first;
    final roundBefore = setup.game.currentRound;

    await repo.proposeRecruitment(
      gameId: gameId,
      recruiterId: setup.authorId,
      targetPlayerId: target,
      sign: 'a specific pen left on their desk',
    );
    final proposalId =
        (await repo.watchMafiaThread(gameId: gameId, viewerId: setup.authorId).first).single.id;
    await repo.acceptRecruitmentProposal(
      gameId: gameId,
      proposalId: proposalId,
      playerId: setup.otherMafiaId,
    );
    await repo.executeRecruitment(
      gameId: gameId,
      proposalId: proposalId,
      playerId: setup.authorId,
    );

    final wasTarget =
        await repo.respondToRecruitment(gameId: gameId, playerId: target, accept: false);
    expect(wasTarget, isTrue);

    final gameAfterDecline = await repo.watchGame(gameId).first;
    expect(gameAfterDecline.playerById(target)!.role, PlayerRole.villager);
    expect(gameAfterDecline.playerById(target)!.pendingRecruiterId, isNull);
    expect(gameAfterDecline.currentRound, roundBefore + 1);
    // Recruitment stays unlocked — ratio hasn't changed, only the round did.
    expect(gameAfterDecline.recruitmentUnlocked, isTrue);

    // The slot is free again — a new proposal (even for the same person)
    // is accepted.
    final anotherTarget = setup.villagerIds[1];
    await repo.proposeRecruitment(
      gameId: gameId,
      recruiterId: setup.authorId,
      targetPlayerId: anotherTarget,
      sign: 'leaving a coffee on their desk',
    );
    final entries = await repo.watchMafiaThread(gameId: gameId, viewerId: setup.authorId).first;
    expect(entries.where((e) => e.type == MafiaThreadEntryType.recruitment), hasLength(2));
  });

  test('only one recruitment can be in flight at a time', () async {
    final repo = LocalGameRepository();
    final setup = await _gameWithRecruitmentUnlocked(repo);
    final gameId = setup.game.id;

    await repo.proposeRecruitment(
      gameId: gameId,
      recruiterId: setup.authorId,
      targetPlayerId: setup.villagerIds[0],
      sign: 'a specific pen left on their desk',
    );

    expect(
      () => repo.proposeRecruitment(
        gameId: gameId,
        recruiterId: setup.authorId,
        targetPlayerId: setup.villagerIds[1],
        sign: 'a different sign',
      ),
      throwsStateError,
    );
  });

  test('an agreed-but-unexecuted recruitment lapses when the round ends', () async {
    final repo = LocalGameRepository();
    final setup = await _gameWithRecruitmentUnlocked(repo);
    final gameId = setup.game.id;
    final target = setup.villagerIds.first;

    await repo.proposeRecruitment(
      gameId: gameId,
      recruiterId: setup.authorId,
      targetPlayerId: target,
      sign: 'a specific pen left on their desk',
    );
    final proposalId =
        (await repo.watchMafiaThread(gameId: gameId, viewerId: setup.authorId).first).single.id;
    await repo.acceptRecruitmentProposal(
      gameId: gameId,
      proposalId: proposalId,
      playerId: setup.otherMafiaId,
    );

    await repo.resolveVotesForDay(gameId);

    final lapsedEntry =
        (await repo.watchMafiaThread(gameId: gameId, viewerId: setup.authorId).first).single;
    expect(lapsedEntry.lapsed, isTrue);

    final gameAfterLapse = await repo.watchGame(gameId).first;
    expect(gameAfterLapse.playerById(target)!.pendingRecruiterId, isNull);
    expect(gameAfterLapse.playerById(target)!.role, PlayerRole.villager);
    expect(gameAfterLapse.recruitmentSignDescription, isNull);
  });

  test('a mafia member leaving thins the living ratio and can unlock recruitment', () async {
    final repo = LocalGameRepository();
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
    // 2 mafia, 6 villagers: 2/6 = 0.33, above the default 0.2 threshold —
    // locked, same setup as the "stays locked" test above.
    expect(started.recruitmentUnlocked, isFalse);

    // One of the two mafia members leaves. The *living* ratio is now 1
    // remaining mafia against the same 6 living villagers (1/6 = 0.167),
    // which should unlock recruitment even though the departed member is
    // still sitting in the roster with an unchanged mafia role.
    await repo.leaveGame(gameId: game.id, playerId: started.mafia.first.id);

    final afterLeave = await repo.watchGame(game.id).first;
    expect(afterLeave.mafia, hasLength(2)); // still 2 by raw role — one just left
    expect(afterLeave.livingMafia, hasLength(1));
    expect(afterLeave.recruitmentUnlocked, isTrue);
  });
}
