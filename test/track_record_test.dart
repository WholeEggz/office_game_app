import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/data/local/local_game_repository.dart';
import 'package:office_game_app/domain/models/game.dart';
import 'package:office_game_app/domain/models/game_moment.dart';
import 'package:office_game_app/domain/models/player.dart';
import 'package:office_game_app/domain/stats/track_record.dart';

GameMoment _moment(GameMomentType type, {int round = 1, required DateTime at}) {
  return GameMoment(
    id: '$type-$round-${at.microsecondsSinceEpoch}',
    gameId: 'g',
    playerId: 'p1',
    type: type,
    round: round,
    createdAt: at,
  );
}

void main() {
  group('computeCurrentStreak', () {
    test('counts consecutive good-outcome moments back from the most recent', () {
      final t0 = DateTime(2026, 1, 1);
      final moments = [
        _moment(GameMomentType.correctVoteReward, round: 1, at: t0),
        _moment(GameMomentType.correctVoteReward, round: 2, at: t0.add(const Duration(hours: 1))),
        _moment(GameMomentType.targetedByVillagers, round: 3, at: t0.add(const Duration(hours: 2))),
        _moment(GameMomentType.correctVoteReward, round: 4, at: t0.add(const Duration(hours: 3))),
        _moment(
          GameMomentType.survivedRoundAsMafia,
          round: 5,
          at: t0.add(const Duration(hours: 4)),
        ),
      ];
      // Newest-first: round5 (good), round4 (good), round3 (bad) — stops.
      expect(computeCurrentStreak(moments), 2);
    });

    test('correctVoteReward and survivedRoundAsMafia both count as good', () {
      final t0 = DateTime(2026, 1, 1);
      final moments = [
        _moment(GameMomentType.survivedRoundAsMafia, round: 1, at: t0),
        _moment(
          GameMomentType.survivedRoundAsMafia,
          round: 2,
          at: t0.add(const Duration(hours: 1)),
        ),
      ];
      expect(computeCurrentStreak(moments), 2);
    });

    test('non-outcome moments (joins, finales, recruitment) are skipped, not breaking the run', () {
      final t0 = DateTime(2026, 1, 1);
      final moments = [
        _moment(GameMomentType.correctVoteReward, round: 1, at: t0),
        _moment(GameMomentType.joinedCase, round: 1, at: t0.add(const Duration(minutes: 30))),
        _moment(GameMomentType.correctVoteReward, round: 2, at: t0.add(const Duration(hours: 1))),
        _moment(GameMomentType.finaleWin, round: 2, at: t0.add(const Duration(hours: 2))),
      ];
      expect(computeCurrentStreak(moments), 2);
    });

    test('zero when the most recent round-outcome moment was a miss', () {
      final t0 = DateTime(2026, 1, 1);
      final moments = [
        _moment(GameMomentType.correctVoteReward, round: 1, at: t0),
        _moment(GameMomentType.roundEnded, round: 2, at: t0.add(const Duration(hours: 1))),
      ];
      expect(computeCurrentStreak(moments), 0);
    });

    test('empty history has a zero streak', () {
      expect(computeCurrentStreak(const []), 0);
    });
  });

  group('computeTrackRecord', () {
    test('a player who has never joined any case gets the empty record', () async {
      final repo = LocalGameRepository();
      final record = await computeTrackRecord(repo: repo, viewerId: 'nobody');
      expect(record.casesPlayed, 0);
      expect(record.voteAccuracy, isNull);
      expect(record.currentStreak, 0);
    });

    test('correct unmasks, votes cast, and accuracy aggregate across every case joined', () async {
      final repo = LocalGameRepository();
      var expectedVotes = 0;
      var expectedCorrect = 0;

      // p1's own role is drawn at random each case, so this can't just
      // hardcode "p1 votes for the mafia member" — if p1 *is* the mafia
      // member this time, they vote for a villager instead (a miss, same
      // as any mafia member covering for themselves). Either way, every
      // other player backs the same target so it actually wins the round.
      Future<void> playRound(String gameId) async {
        final game = await repo.watchGame(gameId).first;
        final self = game.playerById('p1')!;
        final target = self.role == PlayerRole.mafia ? game.villagers.first : game.mafia.first;
        for (final voter in game.players.where((p) => p.id != target.id)) {
          await repo.castVote(gameId: gameId, voterId: voter.id, targetPlayerId: target.id);
        }
        await repo.resolveVotesForDay(gameId);
        expectedVotes++;
        if (self.role != PlayerRole.mafia) expectedCorrect++;
      }

      final game1 = await repo.createGame(
        locationTag: 'Case 1',
        minPlayers: 4,
        creatorId: 'p1',
        creatorName: 'Alice',
      );
      for (var i = 2; i <= 4; i++) {
        await repo.addPlayer(gameId: game1.id, playerId: 'p$i', name: 'Player $i');
      }
      await playRound(game1.id);

      final game2 = await repo.createGame(
        locationTag: 'Case 2',
        minPlayers: 4,
        creatorId: 'p1',
        creatorName: 'Alice',
      );
      for (var i = 2; i <= 4; i++) {
        await repo.addPlayer(gameId: game2.id, playerId: 'q$i', name: 'Player $i');
      }
      await playRound(game2.id);

      final record = await computeTrackRecord(repo: repo, viewerId: 'p1');
      expect(record.casesPlayed, 2);
      expect(record.votesCast, expectedVotes);
      expect(record.correctUnmasks, expectedCorrect);
      expect(record.voteAccuracy, expectedCorrect / expectedVotes);
    });

    test('a case that ends in a mafia win at instant parity counts as survived and won '
        'for whichever player was drawn mafia, lost for the villager', () async {
      final repo = LocalGameRepository();
      // 1 villager + 1 mafia: mafia is an instant parity majority the
      // moment roles are drawn, so the case ends on creation/join with
      // neither player ever voting or being unmasked.
      final game = await repo.createGame(
        locationTag: 'Instant case',
        minPlayers: 2,
        creatorId: 'p1',
        creatorName: 'Alice',
        mafiaCount: 1,
      );
      await repo.addPlayer(gameId: game.id, playerId: 'p2', name: 'Bob');

      final ended = await repo.watchGame(game.id).first;
      expect(ended.status, GameStatus.ended);
      final mafiaPlayer = ended.mafia.single;
      final villagerPlayer = ended.villagers.single;

      final mafiaRecord = await computeTrackRecord(repo: repo, viewerId: mafiaPlayer.id);
      expect(mafiaRecord.casesAsInformant, 1);
      expect(mafiaRecord.casesAsWitness, 0);
      expect(mafiaRecord.survivedAsMafiaCount, 1);
      expect(mafiaRecord.casesWon, 1);
      expect(mafiaRecord.casesLost, 0);

      final villagerRecord = await computeTrackRecord(repo: repo, viewerId: villagerPlayer.id);
      expect(villagerRecord.casesAsWitness, 1);
      expect(villagerRecord.casesAsInformant, 0);
      expect(villagerRecord.survivedAsMafiaCount, 0);
      expect(villagerRecord.casesLost, 1);
      expect(villagerRecord.casesWon, 0);
    });

    test('an unmasked former mafia member counts as ever-Informant but not survived', () async {
      final repo = LocalGameRepository();
      // 2 mafia among 8 (not 4) so unmasking one doesn't itself hit parity
      // and close the case — mirrors game_moments_test.dart's same setup.
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
      final mafiaTarget = started.mafia.first;
      for (final voter in started.players.where((p) => p.id != mafiaTarget.id)) {
        await repo.castVote(gameId: game.id, voterId: voter.id, targetPlayerId: mafiaTarget.id);
      }
      await repo.resolveVotesForDay(game.id);

      final resolved = await repo.watchGame(game.id).first;
      expect(resolved.playerById(mafiaTarget.id)!.wasUnmasked, isTrue);

      final record = await computeTrackRecord(repo: repo, viewerId: mafiaTarget.id);
      expect(record.casesAsInformant, 1);
      // The case isn't over yet, so it can't count as "survived" — but even
      // if it later ended, wasUnmasked staying true would still exclude it.
      expect(record.survivedAsMafiaCount, 0);
    });

    test('a successfully executed recruitment counts toward recruitmentsExecuted', () async {
      final repo = LocalGameRepository();
      // 1 mafia, 5 villagers — mirrors game_moments_test.dart's recruitment
      // setup: recruiting one villager lands on 2 mafia vs 4 villagers, not
      // parity, so this stays focused on the recruitment count itself.
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
      final recruiter = started.mafia.single;
      final target = started.villagers.first;

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

      final recruiterRecord = await computeTrackRecord(repo: repo, viewerId: recruiter.id);
      expect(recruiterRecord.recruitmentsExecuted, 1);

      // The recruited target switched sides but didn't execute anything
      // themselves — this is specifically about who did the recruiting.
      final targetRecord = await computeTrackRecord(repo: repo, viewerId: target.id);
      expect(targetRecord.recruitmentsExecuted, 0);
    });
  });
}
