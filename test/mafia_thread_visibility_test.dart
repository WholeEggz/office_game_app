import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/data/local/local_game_repository.dart';
import 'package:office_game_app/domain/models/game.dart';
import 'package:office_game_app/domain/models/mafia_thread_entry.dart';

Future<({Game game, String authorId, String otherMafiaId, String villagerId})>
    _eightPlayerGameWithTwoMafia(LocalGameRepository repo) async {
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
  final mafiaIds = started.mafia.map((p) => p.id).toList();
  expect(mafiaIds, hasLength(2));
  return (
    game: started,
    authorId: mafiaIds[0],
    otherMafiaId: mafiaIds[1],
    villagerId: started.villagers.first.id,
  );
}

void main() {
  test('a pending proposal is visible to both the author and the other active mafia member', () async {
    final repo = LocalGameRepository();
    final setup = await _eightPlayerGameWithTwoMafia(repo);
    final gameId = setup.game.id;

    await repo.proposeElimination(
      gameId: gameId,
      authorId: setup.authorId,
      method: 'a note on the monitor',
      targetPlayerId: setup.villagerId,
    );

    final authorThread =
        await repo.watchMafiaThread(gameId: gameId, viewerId: setup.authorId).first;
    final otherThread =
        await repo.watchMafiaThread(gameId: gameId, viewerId: setup.otherMafiaId).first;

    expect(authorThread, hasLength(1));
    expect(otherThread, hasLength(1));
    expect(authorThread.single.type, MafiaThreadEntryType.proposal);
    expect(authorThread.single.agreedAt, isNull);
    expect(authorThread.single.resolved, isFalse);
    expect(otherThread.single.id, authorThread.single.id);

    // Still just pending — nothing revealed to villagers yet.
    final gameWhilePending = await repo.watchGame(gameId).first;
    expect(gameWhilePending.eliminationMethodDescription, isNull);
  });

  test('agreement reveals the method as a forewarning; only execution applies it', () async {
    final repo = LocalGameRepository();
    final setup = await _eightPlayerGameWithTwoMafia(repo);
    final gameId = setup.game.id;

    await repo.proposeElimination(
      gameId: gameId,
      authorId: setup.authorId,
      method: 'a note on the monitor',
      targetPlayerId: setup.villagerId,
    );
    final proposalId =
        (await repo.watchMafiaThread(gameId: gameId, viewerId: setup.authorId).first).single.id;

    await repo.acceptEliminationProposal(
      gameId: gameId,
      proposalId: proposalId,
      playerId: setup.otherMafiaId,
    );

    final agreedEntry =
        (await repo.watchMafiaThread(gameId: gameId, viewerId: setup.authorId).first).single;
    expect(agreedEntry.agreedAt, isNotNull);
    expect(agreedEntry.resolved, isFalse);

    // Agreement puts the method in front of everyone as a forewarning
    // (section 6), but doesn't move any vote weight yet.
    final gameAfterAgreement = await repo.watchGame(gameId).first;
    expect(gameAfterAgreement.eliminationMethodDescription, 'a note on the monitor');
    expect(gameAfterAgreement.eliminationSignalExecuted, isFalse);
    expect(gameAfterAgreement.playerById(setup.villagerId)!.voteWeight, 3);

    // Executing applies the effects and starts the confirmation loop.
    await repo.executeElimination(
      gameId: gameId,
      proposalId: proposalId,
      playerId: setup.authorId,
    );
    final executedEntry =
        (await repo.watchMafiaThread(gameId: gameId, viewerId: setup.authorId).first).single;
    expect(executedEntry.resolved, isTrue);
    expect(executedEntry.confirmedAt, isNull);

    final gameAfterExecution = await repo.watchGame(gameId).first;
    expect(gameAfterExecution.eliminationSignalExecuted, isTrue);
    expect(gameAfterExecution.eliminationSignalConfirmed, isFalse);
    expect(gameAfterExecution.playerById(setup.villagerId)!.voteWeight, 2);
  });

  test('a non-target acknowledging is told plainly they were not the target, nothing else changes', () async {
    final repo = LocalGameRepository();
    final setup = await _eightPlayerGameWithTwoMafia(repo);
    final gameId = setup.game.id;

    await repo.proposeElimination(
      gameId: gameId,
      authorId: setup.authorId,
      method: 'a note on the monitor',
      targetPlayerId: setup.villagerId,
    );
    final proposalId =
        (await repo.watchMafiaThread(gameId: gameId, viewerId: setup.authorId).first).single.id;
    await repo.acceptEliminationProposal(
      gameId: gameId,
      proposalId: proposalId,
      playerId: setup.otherMafiaId,
    );
    await repo.executeElimination(
      gameId: gameId,
      proposalId: proposalId,
      playerId: setup.authorId,
    );

    final someoneElse = setup.game.villagers
        .map((p) => p.id)
        .firstWhere((id) => id != setup.villagerId);

    final wasTarget =
        await repo.acknowledgeEliminationSignal(gameId: gameId, playerId: someoneElse);
    expect(wasTarget, isFalse);

    // A wrong guess changes nothing — no confirmation, no round change.
    final gameAfterWrongGuess = await repo.watchGame(gameId).first;
    expect(gameAfterWrongGuess.eliminationSignalConfirmed, isFalse);
    expect(gameAfterWrongGuess.currentRound, 1);
  });

  test('the real target confirming ends the round immediately', () async {
    final repo = LocalGameRepository();
    final setup = await _eightPlayerGameWithTwoMafia(repo);
    final gameId = setup.game.id;

    await repo.proposeElimination(
      gameId: gameId,
      authorId: setup.authorId,
      method: 'a note on the monitor',
      targetPlayerId: setup.villagerId,
    );
    final proposalId =
        (await repo.watchMafiaThread(gameId: gameId, viewerId: setup.authorId).first).single.id;
    await repo.acceptEliminationProposal(
      gameId: gameId,
      proposalId: proposalId,
      playerId: setup.otherMafiaId,
    );
    await repo.executeElimination(
      gameId: gameId,
      proposalId: proposalId,
      playerId: setup.authorId,
    );

    final wasTarget =
        await repo.acknowledgeEliminationSignal(gameId: gameId, playerId: setup.villagerId);
    expect(wasTarget, isTrue);

    // The entry itself keeps a permanent record of the confirmation...
    final confirmedEntry =
        (await repo.watchMafiaThread(gameId: gameId, viewerId: setup.authorId).first).single;
    expect(confirmedEntry.confirmedAt, isNotNull);

    // ...but confirming is, narratively, the end of the day: the round
    // advances and the next round starts with a clean slate.
    final gameAfterConfirm = await repo.watchGame(gameId).first;
    expect(gameAfterConfirm.currentRound, 2);
    expect(gameAfterConfirm.eliminationMethodDescription, isNull);
    expect(gameAfterConfirm.eliminationSignalExecuted, isFalse);
    expect(gameAfterConfirm.eliminationSignalConfirmed, isFalse);
  });

  test('an agreed-but-unexecuted proposal lapses when the round ends', () async {
    final repo = LocalGameRepository();
    final setup = await _eightPlayerGameWithTwoMafia(repo);
    final gameId = setup.game.id;

    await repo.proposeElimination(
      gameId: gameId,
      authorId: setup.authorId,
      method: 'a note on the monitor',
      targetPlayerId: setup.villagerId,
    );
    final proposalId =
        (await repo.watchMafiaThread(gameId: gameId, viewerId: setup.authorId).first).single.id;
    await repo.acceptEliminationProposal(
      gameId: gameId,
      proposalId: proposalId,
      playerId: setup.otherMafiaId,
    );

    // Round ends before anyone executes.
    await repo.resolveVotesForDay(gameId);

    final lapsedEntry =
        (await repo.watchMafiaThread(gameId: gameId, viewerId: setup.authorId).first).single;
    expect(lapsedEntry.lapsed, isTrue);
    expect(lapsedEntry.resolved, isFalse);

    final gameAfterLapse = await repo.watchGame(gameId).first;
    expect(gameAfterLapse.eliminationMethodDescription, isNull);
    expect(gameAfterLapse.playerById(setup.villagerId)!.voteWeight, 3);

    // Trying to execute a lapsed proposal is rejected.
    expect(
      () => repo.executeElimination(
        gameId: gameId,
        proposalId: proposalId,
        playerId: setup.authorId,
      ),
      throwsStateError,
    );
  });
}
