import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/data/local/local_game_repository.dart';
import 'package:office_game_app/domain/hints/hint_catalog.dart';
import 'package:office_game_app/domain/hints/hint_context.dart';
import 'package:office_game_app/domain/hints/hint_definition.dart';
import 'package:office_game_app/domain/hints/hint_engine.dart';
import 'package:office_game_app/domain/models/game.dart';

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
    game = await repo.createGame(
      locationTag: 'test-office',
      minPlayers: 3,
      creatorId: 'p1',
      creatorName: 'Alice',
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

  test('welcome_help only completes once dismissHint is called for that viewer', () async {
    var ctx = await contextFor('p1');
    expect(evaluateHint(hintCatalog.firstWhere((h) => h.id == 'welcome_help'), ctx),
        HintStatus.active);

    await repo.dismissHint(gameId: game.id, viewerId: 'p1', hintId: 'welcome_help');

    ctx = await contextFor('p1');
    expect(evaluateHint(hintCatalog.firstWhere((h) => h.id == 'welcome_help'), ctx),
        HintStatus.completed);

    // A different viewer's own dismissal is untouched.
    final otherCtx = await contextFor('p2');
    expect(evaluateHint(hintCatalog.firstWhere((h) => h.id == 'welcome_help'), otherCtx),
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
    // Nothing done yet: welcome_help (100) outranks say_hello (90) and
    // cast_first_vote (80), which are all active simultaneously.
    expect(top?.id, 'welcome_help');
  });

  test('dismissing welcome_help then completing say_hello does not resurrect welcome_help',
      () async {
    // Reproduces the exact reported sequence: dismiss the "New here?" hint,
    // then say hello in the observation log, then check both the banner
    // pick and welcome_help's own status again. Uses a guaranteed villager
    // (roles are drawn randomly at game start) so mafia_thread_intro never
    // outranks cast_first_vote here regardless of the random draw.
    final freshGame = await repo.watchGame(game.id).first;
    final playerId = freshGame.villagers.first.id;

    await repo.dismissHint(gameId: game.id, viewerId: playerId, hintId: 'welcome_help');
    var ctx = await contextFor(playerId);
    expect(evaluateHint(hintCatalog.firstWhere((h) => h.id == 'welcome_help'), ctx),
        HintStatus.completed);
    expect(topBannerHint(hintCatalog, ctx)?.id, 'say_hello');

    await repo.logObservation(gameId: game.id, authorId: playerId, text: 'Hello everyone');

    ctx = await contextFor(playerId);
    expect(evaluateHint(hintCatalog.firstWhere((h) => h.id == 'welcome_help'), ctx),
        HintStatus.completed,
        reason: 'welcome_help must stay dismissed regardless of other hints completing');
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

  test('welcome_help points at the Help screen as its secondary action', () {
    final hint = hintCatalog.firstWhere((h) => h.id == 'welcome_help');
    expect(hint.actionTarget, HintActionTarget.help);
    expect(hint.actionLabel, isNotNull);
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
}
