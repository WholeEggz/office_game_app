import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/data/local/local_game_repository.dart';
import 'package:office_game_app/domain/models/game.dart';

// LocalGameRepository schedules its cutoff Timer from a real DateTime.now()
// read (not package:clock), so fakeAsync can't fake that initial "now" the
// way it fakes Timer/microtask scheduling. These tests work around that by
// picking a dailyCutoffTime a fixed number of seconds after a `now`
// captured microseconds before the repository reads its own — the two stay
// in lockstep since nothing but synchronous setup code runs in between.

void main() {
  test('a round resolves on its own at the configured daily cutoff, with no manual action', () {
    fakeAsync((async) {
      final repo = LocalGameRepository();
      final now = DateTime.now();
      final cutoffTimeOfDay = Duration(hours: now.hour, minutes: now.minute, seconds: now.second) +
          const Duration(seconds: 90);
      late String gameId;

      repo
          .createGame(
            locationTag: 'Test Office',
            minPlayers: 4,
            creatorId: 'p1',
            creatorName: 'Alice',
            mafiaCount: 1,
            dailyCutoffTime: cutoffTimeOfDay,
          )
          .then((game) => gameId = game.id);
      async.flushMicrotasks();

      for (var i = 2; i <= 4; i++) {
        repo.addPlayer(gameId: gameId, playerId: 'p$i', name: 'Player $i');
        async.flushMicrotasks();
      }

      int? round(FakeAsync a) {
        int? value;
        repo.watchGame(gameId).first.then((g) => value = g.currentRound);
        a.flushMicrotasks();
        return value;
      }

      expect(round(async), 1);

      // Just short of the cutoff: still round 1, nothing fired yet.
      async.elapse(const Duration(seconds: 89));
      expect(round(async), 1);

      // Past the cutoff: resolved entirely on its own.
      async.elapse(const Duration(seconds: 5));
      expect(round(async), 2);
    });
  });

  test('resolving manually before the cutoff cancels the stale timer instead of double-firing', () {
    fakeAsync((async) {
      final repo = LocalGameRepository();
      final now = DateTime.now();
      final cutoffTimeOfDay = Duration(hours: now.hour, minutes: now.minute, seconds: now.second) +
          const Duration(seconds: 90);
      late String gameId;

      repo
          .createGame(
            locationTag: 'Test Office',
            minPlayers: 4,
            creatorId: 'p1',
            creatorName: 'Alice',
            mafiaCount: 1,
            dailyCutoffTime: cutoffTimeOfDay,
          )
          .then((game) => gameId = game.id);
      async.flushMicrotasks();

      for (var i = 2; i <= 4; i++) {
        repo.addPlayer(gameId: gameId, playerId: 'p$i', name: 'Player $i');
        async.flushMicrotasks();
      }

      int? round(FakeAsync a) {
        int? value;
        repo.watchGame(gameId).first.then((g) => value = g.currentRound);
        a.flushMicrotasks();
        return value;
      }

      // Resolve well before the cutoff — round 1 -> 2.
      repo.resolveVotesForDay(gameId);
      async.flushMicrotasks();
      expect(round(async), 2);

      // dailyCutoffTime is a fixed time-of-day, so the same "5pm today"
      // instant still applies to round 2 too (it hasn't passed yet) —
      // advancing to it should resolve exactly once more, round 2 -> 3.
      // If the original round-1 timer hadn't been cancelled and fired
      // independently, this would instead jump to round 4.
      async.elapse(const Duration(seconds: 95));
      expect(round(async), 3);
    });
  });

  test('the daily cutoff stops firing once the game has ended', () {
    fakeAsync((async) {
      final repo = LocalGameRepository();
      final now = DateTime.now();
      final cutoffTimeOfDay = Duration(hours: now.hour, minutes: now.minute, seconds: now.second) +
          const Duration(seconds: 90);
      late String gameId;

      repo
          .createGame(
            locationTag: 'Test Office',
            minPlayers: 4,
            creatorId: 'p1',
            creatorName: 'Alice',
            mafiaCount: 1, // exactly 1 mafia among 4
            dailyCutoffTime: cutoffTimeOfDay,
          )
          .then((game) => gameId = game.id);
      async.flushMicrotasks();

      for (var i = 2; i <= 4; i++) {
        repo.addPlayer(gameId: gameId, playerId: 'p$i', name: 'Player $i');
        async.flushMicrotasks();
      }

      Game? state(FakeAsync a) {
        Game? value;
        repo.watchGame(gameId).first.then((g) => value = g);
        a.flushMicrotasks();
        return value;
      }

      final started = state(async)!;
      final mafiaTarget = started.mafia.first;
      for (final voter in started.players.where((p) => p.id != mafiaTarget.id)) {
        repo.castVote(gameId: gameId, voterId: voter.id, targetPlayerId: mafiaTarget.id);
        async.flushMicrotasks();
      }
      repo.resolveVotesForDay(gameId);
      async.flushMicrotasks();

      final ended = state(async)!;
      expect(ended.status, GameStatus.ended);
      final roundAtEnd = ended.currentRound;

      // Well past the original cutoff — no crash, no further resolution.
      async.elapse(const Duration(minutes: 5));
      final stillEnded = state(async)!;
      expect(stillEnded.status, GameStatus.ended);
      expect(stillEnded.currentRound, roundAtEnd);
    });
  });
}
