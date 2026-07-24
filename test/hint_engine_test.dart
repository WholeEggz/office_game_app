import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/data/local/local_game_repository.dart';
import 'package:office_game_app/domain/hints/hint_catalog.dart';
import 'package:office_game_app/domain/hints/hint_context.dart';
import 'package:office_game_app/domain/hints/hint_engine.dart';
import 'package:office_game_app/domain/models/game.dart';
import 'package:office_game_app/domain/models/mafia_thread_entry.dart';

/// Time-of-day (as a midnight-relative [Duration], matching
/// `Game.dailyCutoffTime`'s own shape) [delta] from right now — lets tests
/// pin a game's cutoff a controlled distance from "now" without needing to
/// fake the clock, since `_isWithinWindowBeforeCutoff` in hint_catalog.dart
/// reads real wall-clock time directly (same convention `LocalGameRepository`
/// itself already uses for cutoff scheduling).
Duration _timeOfDayIn(Duration delta) {
  final target = DateTime.now().add(delta);
  return Duration(hours: target.hour, minutes: target.minute, seconds: target.second);
}

void main() {
  late LocalGameRepository repo;
  late Game game;

  Future<HintContext> contextFor(String playerId) async {
    final freshGame = await repo.watchGame(game.id).first;
    final self = freshGame.playerById(playerId)!;
    final observations = await repo
        .watchObservations(gameId: game.id, viewerId: playerId)
        .first;
    final currentRoundVotes = await repo.watchCurrentRoundVotes(game.id).first;
    final voteHistory = await repo.watchVoteHistory(game.id).first;
    final mafiaThread = await repo
        .watchMafiaThread(gameId: game.id, viewerId: playerId)
        .first;
    final dismissedHintIds =
        await repo.watchDismissedHintIds(gameId: game.id, viewerId: playerId).first;
    return HintContext(
      game: freshGame,
      self: self,
      observations: observations,
      currentRoundVotes: currentRoundVotes,
      voteHistory: voteHistory,
      mafiaThread: mafiaThread,
      dismissedHintIds: dismissedHintIds,
    );
  }

  setUp(() async {
    repo = LocalGameRepository();
    // 3 players, default mafiaCount 1 -> 1 mafia / 2 villagers, so the game
    // doesn't hit the mafia-parity win condition the instant it starts (a
    // 2-player game with 1 mafia would end immediately).
    // dailyCutoffTime is pinned 30 minutes out (inside vote_before_cutoff's
    // 1-hour window) so tests that exercise it don't depend on what time of
    // day this suite happens to run at — see the dedicated window test
    // below for coverage of the boundary itself.
    game = await repo.createGame(
      locationTag: 'test-office',
      minPlayers: 3,
      creatorId: 'p1',
      creatorName: 'Alice',
      dailyCutoffTime: _timeOfDayIn(const Duration(minutes: 30)),
    );
    await repo.addPlayer(gameId: game.id, playerId: 'p2', name: 'Bob');
    game = await repo.addPlayer(gameId: game.id, playerId: 'p3', name: 'Carol')
        .then((_) => repo.watchGame(game.id).first);
  });

  test('say_hello is active until the player logs any observation', () async {
    var ctx = await contextFor('p1');
    expect(evaluateHint(hintCatalog.firstWhere((h) => h.id == 'say_hello'), ctx),
        HintStatus.active);

    await repo.logObservation(gameId: game.id, authorId: 'p1', text: 'Hello everyone');

    ctx = await contextFor('p1');
    expect(evaluateHint(hintCatalog.firstWhere((h) => h.id == 'say_hello'), ctx),
        HintStatus.completed);
  });

  test('cast_first_vote only completes for the player who actually voted', () async {
    await repo.castVote(gameId: game.id, voterId: 'p1', targetPlayerId: 'p2');

    final voterCtx = await contextFor('p1');
    expect(evaluateHint(hintCatalog.firstWhere((h) => h.id == 'cast_first_vote'), voterCtx),
        HintStatus.completed);

    final othersCtx = await contextFor('p2');
    expect(evaluateHint(hintCatalog.firstWhere((h) => h.id == 'cast_first_vote'), othersCtx),
        HintStatus.active);
  });

  test('mafia_thread_intro never applies to a villager', () async {
    final freshGame = await repo.watchGame(game.id).first;
    final ctx = await contextFor(freshGame.villagers.first.id);
    expect(
      evaluateHint(hintCatalog.firstWhere((h) => h.id == 'mafia_thread_intro'), ctx),
      HintStatus.notYetRelevant,
    );
  });

  test('topBannerHint picks the highest-priority active hint', () async {
    final ctx = await contextFor('p1');
    final top = topBannerHint(hintCatalog, ctx);
    // Nothing done yet: say_hello (90) outranks cast_first_vote (80) —
    // both are active simultaneously. (`welcome_help`, formerly the
    // highest-priority entry here, now lives in `staticHintCatalog`
    // instead — it's pre-game, not part of this in-game catalog.)
    expect(top?.id, 'say_hello');
  });

  test('completing say_hello moves the banner on to the next active hint', () async {
    // Reproduces the reported sequence (minus welcome_help, which no
    // longer lives in this catalog): say hello, then check the banner
    // picks up the next hint in line. Uses a guaranteed villager (roles
    // are drawn randomly at game start) so mafia_thread_intro never
    // outranks cast_first_vote here regardless of the random draw.
    final freshGame = await repo.watchGame(game.id).first;
    final playerId = freshGame.villagers.first.id;

    var ctx = await contextFor(playerId);
    expect(topBannerHint(hintCatalog, ctx)?.id, 'say_hello');

    await repo.logObservation(gameId: game.id, authorId: playerId, text: 'Hello everyone');

    ctx = await contextFor(playerId);
    expect(evaluateHint(hintCatalog.firstWhere((h) => h.id == 'say_hello'), ctx),
        HintStatus.completed);
    expect(topBannerHint(hintCatalog, ctx)?.id, 'cast_first_vote');
  });

  test('dismissing a recurring hint ("Got it") only silences the current round',
      () async {
    // Recurring hints use a discriminator (here, the round number) in
    // their dismiss key, so "Got it" gives temporary relief rather than
    // permanently hiding a reminder that's still useful next round.
    final hint = hintCatalog.firstWhere((h) => h.id == 'vote_before_cutoff');
    var ctx = await contextFor('p1');
    expect(evaluateHint(hint, ctx), HintStatus.active);

    await repo.dismissHint(gameId: game.id, viewerId: 'p1', hintId: hint.dismissKey(ctx));
    ctx = await contextFor('p1');
    expect(evaluateHint(hint, ctx), HintStatus.completed,
        reason: 'dismissed for this round');

    // Force a new round without ever casting a vote — the old dismissal
    // (keyed to the previous round number) shouldn't carry over.
    await repo.resolveVotesForDay(game.id);
    ctx = await contextFor('p1');
    expect(evaluateHint(hint, ctx), HintStatus.active,
        reason: 'a new round re-arms the reminder even though it was dismissed before');
  });

  test('vote_before_cutoff only becomes active in the last hour before cutoff', () async {
    // The default setUp game already has a cutoff 30 minutes out (inside
    // the window) — this test instead checks the far-away case, using a
    // fresh game so it doesn't disturb the shared default.
    final farGame = await repo.createGame(
      locationTag: 'far-office',
      minPlayers: 3,
      creatorId: 'f1',
      creatorName: 'Dana',
      dailyCutoffTime: _timeOfDayIn(const Duration(hours: 5)),
    );
    await repo.addPlayer(gameId: farGame.id, playerId: 'f2', name: 'Eve');
    await repo.addPlayer(gameId: farGame.id, playerId: 'f3', name: 'Frank');

    final freshGame = await repo.watchGame(farGame.id).first;
    final ctx = HintContext(
      game: freshGame,
      self: freshGame.players.first,
      observations: const [],
      currentRoundVotes: const [],
      voteHistory: const [],
      mafiaThread: const [],
      dismissedHintIds: const {},
    );
    expect(
      evaluateHint(hintCatalog.firstWhere((h) => h.id == 'vote_before_cutoff'), ctx),
      HintStatus.notYetRelevant,
      reason: "cutoff is hours away — no last-call nudge needed yet, and this "
          "must not crowd out whatever else is relevant in the meantime",
    );

    // The shared setUp game's cutoff (30 minutes out) is inside the window.
    final ctxSoon = await contextFor('p1');
    expect(evaluateHint(hintCatalog.firstWhere((h) => h.id == 'vote_before_cutoff'), ctxSoon),
        HintStatus.active);
  });

  test('clearDismissedHints (debug reset) reactivates a dismissed hint without '
      'touching real completions', () async {
    // say_hello dismissed via "Got it" without ever actually posting.
    await repo.dismissHint(gameId: game.id, viewerId: 'p1', hintId: 'say_hello');
    // cast_first_vote completed for real, by actually voting.
    await repo.castVote(gameId: game.id, voterId: 'p1', targetPlayerId: 'p2');

    var ctx = await contextFor('p1');
    expect(evaluateHint(hintCatalog.firstWhere((h) => h.id == 'say_hello'), ctx),
        HintStatus.completed);
    expect(evaluateHint(hintCatalog.firstWhere((h) => h.id == 'cast_first_vote'), ctx),
        HintStatus.completed);

    await repo.clearDismissedHints(gameId: game.id, viewerId: 'p1');

    ctx = await contextFor('p1');
    expect(evaluateHint(hintCatalog.firstWhere((h) => h.id == 'say_hello'), ctx),
        HintStatus.active,
        reason: 'the "Got it" dismissal was cleared');
    expect(evaluateHint(hintCatalog.firstWhere((h) => h.id == 'cast_first_vote'), ctx),
        HintStatus.completed,
        reason: 'a real completion (actually voting) is not undone by a dismissal reset');
  });

  test('notice_something resets every round while say_hello does not', () async {
    await repo.logObservation(gameId: game.id, authorId: 'p1', text: 'first note');
    var ctx = await contextFor('p1');
    expect(evaluateHint(hintCatalog.firstWhere((h) => h.id == 'notice_something'), ctx),
        HintStatus.completed);
    expect(evaluateHint(hintCatalog.firstWhere((h) => h.id == 'say_hello'), ctx),
        HintStatus.completed);

    await repo.resolveVotesForDay(game.id);

    ctx = await contextFor('p1');
    expect(evaluateHint(hintCatalog.firstWhere((h) => h.id == 'notice_something'), ctx),
        HintStatus.active,
        reason: 'a new round has no observation of its own yet');
    expect(evaluateHint(hintCatalog.firstWhere((h) => h.id == 'say_hello'), ctx),
        HintStatus.completed,
        reason: 'onboarding hints never resurface once done');
  });

  group('elimination method propose/accept/agreed hints', () {
    late LocalGameRepository eliminationRepo;
    late Game eliminationGame;
    late String mafia1;
    late String mafia2;
    late String villagerId;

    Future<HintContext> eliminationContextFor(String playerId) async {
      final freshGame = await eliminationRepo.watchGame(eliminationGame.id).first;
      final self = freshGame.playerById(playerId)!;
      final mafiaThread = await eliminationRepo
          .watchMafiaThread(gameId: eliminationGame.id, viewerId: playerId)
          .first;
      return HintContext(
        game: freshGame,
        self: self,
        observations: const [],
        currentRoundVotes: const [],
        voteHistory: const [],
        mafiaThread: mafiaThread,
        dismissedHintIds: const {},
      );
    }

    setUp(() async {
      eliminationRepo = LocalGameRepository();
      // mafiaCount: 2 so a proposal needs a SECOND mafia member's
      // acceptance before it's agreed — with the default of 1, the
      // proposer's own auto-accept would already satisfy "every active
      // mafia member," and accept_elimination_method would never have
      // anyone left to prompt. 5 players (2 mafia / 3 villagers), not 4,
      // so mafia don't start at parity and end the game the instant it
      // starts (mirrors the top-level setUp's own reasoning above).
      eliminationGame = await eliminationRepo.createGame(
        locationTag: 'elimination-office',
        minPlayers: 5,
        creatorId: 'e1',
        creatorName: 'Alice',
        mafiaCount: 2,
      );
      await eliminationRepo.addPlayer(gameId: eliminationGame.id, playerId: 'e2', name: 'Bob');
      await eliminationRepo.addPlayer(gameId: eliminationGame.id, playerId: 'e3', name: 'Carol');
      await eliminationRepo.addPlayer(gameId: eliminationGame.id, playerId: 'e4', name: 'Dave');
      eliminationGame = await eliminationRepo
          .addPlayer(gameId: eliminationGame.id, playerId: 'e5', name: 'Erin')
          .then((_) => eliminationRepo.watchGame(eliminationGame.id).first);

      final mafiaIds = eliminationGame.mafia.map((p) => p.id).toList();
      mafia1 = mafiaIds[0];
      mafia2 = mafiaIds[1];
      villagerId = eliminationGame.villagers.first.id;
    });

    test(
        'propose_elimination_method is active for mafia until someone proposes, '
        'and never applies to a villager', () async {
      var ctx = await eliminationContextFor(mafia1);
      expect(
        evaluateHint(hintCatalog.firstWhere((h) => h.id == 'propose_elimination_method'), ctx),
        HintStatus.active,
      );

      final villagerCtx = await eliminationContextFor(villagerId);
      expect(
        evaluateHint(
            hintCatalog.firstWhere((h) => h.id == 'propose_elimination_method'), villagerCtx),
        HintStatus.notYetRelevant,
      );

      await eliminationRepo.proposeElimination(
        gameId: eliminationGame.id,
        authorId: mafia1,
        method: 'a note on the monitor',
        targetPlayerId: villagerId,
      );

      ctx = await eliminationContextFor(mafia1);
      expect(
        evaluateHint(hintCatalog.firstWhere((h) => h.id == 'propose_elimination_method'), ctx),
        HintStatus.completed,
        reason: 'a proposal now exists for this round — the "propose" nudge is done',
      );
    });

    test(
        'accept_elimination_method is active for the other mafia member, not the '
        'proposer, and completes once agreed', () async {
      // Before any proposal exists at all, this must read notYetRelevant,
      // not completed — a naive `!isRelevant` negation would misread
      // "nothing to accept yet" as "already done."
      final beforeCtx = await eliminationContextFor(mafia2);
      expect(
        evaluateHint(hintCatalog.firstWhere((h) => h.id == 'accept_elimination_method'),
            beforeCtx),
        HintStatus.notYetRelevant,
      );

      await eliminationRepo.proposeElimination(
        gameId: eliminationGame.id,
        authorId: mafia1,
        method: 'a note on the monitor',
        targetPlayerId: villagerId,
      );

      // Author auto-accepted on proposal — nothing left for them to do.
      final authorCtx = await eliminationContextFor(mafia1);
      expect(
        evaluateHint(hintCatalog.firstWhere((h) => h.id == 'accept_elimination_method'), authorCtx),
        HintStatus.completed,
      );

      // The other mafia member still needs to accept.
      var otherCtx = await eliminationContextFor(mafia2);
      expect(
        evaluateHint(hintCatalog.firstWhere((h) => h.id == 'accept_elimination_method'), otherCtx),
        HintStatus.active,
      );

      final thread = await eliminationRepo
          .watchMafiaThread(gameId: eliminationGame.id, viewerId: mafia2)
          .first;
      final proposal = thread.firstWhere((e) => e.type == MafiaThreadEntryType.proposal);
      await eliminationRepo.acceptEliminationProposal(
        gameId: eliminationGame.id,
        proposalId: proposal.id,
        playerId: mafia2,
      );

      otherCtx = await eliminationContextFor(mafia2);
      expect(
        evaluateHint(hintCatalog.firstWhere((h) => h.id == 'accept_elimination_method'), otherCtx),
        HintStatus.completed,
        reason: 'accepted, and every active mafia member has now agreed',
      );
    });

    test('elimination_method_agreed is visible to everyone once agreed, until executed',
        () async {
      await eliminationRepo.proposeElimination(
        gameId: eliminationGame.id,
        authorId: mafia1,
        method: 'a note on the monitor',
        targetPlayerId: villagerId,
      );

      var villagerCtx = await eliminationContextFor(villagerId);
      expect(
        evaluateHint(
            hintCatalog.firstWhere((h) => h.id == 'elimination_method_agreed'), villagerCtx),
        HintStatus.notYetRelevant,
        reason: 'not agreed yet — only one of two mafia members has accepted',
      );

      final thread = await eliminationRepo
          .watchMafiaThread(gameId: eliminationGame.id, viewerId: mafia2)
          .first;
      final proposal = thread.firstWhere((e) => e.type == MafiaThreadEntryType.proposal);
      await eliminationRepo.acceptEliminationProposal(
        gameId: eliminationGame.id,
        proposalId: proposal.id,
        playerId: mafia2,
      );

      villagerCtx = await eliminationContextFor(villagerId);
      expect(
        evaluateHint(
            hintCatalog.firstWhere((h) => h.id == 'elimination_method_agreed'), villagerCtx),
        HintStatus.active,
        reason: 'agreed and now visible, but not executed yet',
      );

      await eliminationRepo.executeElimination(
        gameId: eliminationGame.id,
        proposalId: proposal.id,
        playerId: mafia1,
      );

      villagerCtx = await eliminationContextFor(villagerId);
      expect(
        evaluateHint(
            hintCatalog.firstWhere((h) => h.id == 'elimination_method_agreed'), villagerCtx),
        HintStatus.completed,
        reason: 'executed — elimination_ack_pending takes over from here',
      );
    });
  });
}
