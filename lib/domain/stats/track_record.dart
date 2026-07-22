import '../models/game.dart';
import '../models/game_moment.dart';
import '../models/player.dart';
import '../repositories/game_repository.dart';

/// Moment types that represent a personal "good outcome" for a round —
/// the two halves of the track record's unified streak: a villager reading
/// a round correctly, or a mafia member making it through undetected.
const _goodOutcomeTypes = {GameMomentType.correctVoteReward, GameMomentType.survivedRoundAsMafia};

/// Moment types that aren't a round outcome at all — bookkeeping around
/// joining, re-entering, a case's finale, or switching sides mid-case.
/// Neither extends nor breaks the streak; they're skipped when walking
/// history for it.
const _nonOutcomeTypes = {
  GameMomentType.joinedCase,
  GameMomentType.reenteredCase,
  GameMomentType.finaleWin,
  GameMomentType.finaleLoss,
  GameMomentType.recruitmentExecuted,
  GameMomentType.recruitedSwitchSides,
};

/// A player's cross-case track record — every number here is an aggregate
/// over every case a given [AppUser] identity has ever joined, not scoped
/// to one case the way [Player]/[Game] are. See
/// `office_game_concept_season1.md` section 5's "+1 vote weight... the
/// foundation for a future ranking/hierarchy system" — this is that
/// foundation's first surface.
class TrackRecord {
  final int casesPlayed;
  final int casesAsWitness;
  final int casesAsInformant;
  final int casesWon;
  final int casesLost;

  /// Rounds where this player's vote directly earned the +1 vote-weight
  /// reward for helping unmask an Informant (section 5, 9).
  final int correctUnmasks;

  /// Total rounds this player cast a vote in, across every case — the
  /// denominator for [voteAccuracy].
  final int votesCast;

  /// [correctUnmasks] / [votesCast], counting every voted round regardless
  /// of the vote's weight at the time (a correct read is a correct read
  /// even from a vote that couldn't sway the tally). Null if [votesCast]
  /// is 0 — there's nothing to divide.
  final double? voteAccuracy;

  /// Completed cases where this player was an Informant and was never
  /// personally unmasked — a personal record independent of whether their
  /// side ultimately won or lost.
  final int survivedAsMafiaCount;

  /// Consecutive "good outcome" rounds (see [_goodOutcomeTypes]) walking
  /// backward from the most recent round-outcome moment across every case,
  /// stopping at the first miss.
  final int currentStreak;

  /// Recruitments this player personally executed as the mafia-side
  /// recruiter (section 8) — a count of [GameMomentType.recruitmentExecuted]
  /// moments, the same shape as [correctUnmasks]/[casesWon]/[casesLost].
  /// Feeds the "Recruiter" badge (see `achievements.dart`); nothing else
  /// in the track record surfaces this signal.
  final int recruitmentsExecuted;

  const TrackRecord({
    required this.casesPlayed,
    required this.casesAsWitness,
    required this.casesAsInformant,
    required this.casesWon,
    required this.casesLost,
    required this.correctUnmasks,
    required this.votesCast,
    required this.voteAccuracy,
    required this.survivedAsMafiaCount,
    required this.currentStreak,
    required this.recruitmentsExecuted,
  });

  static const empty = TrackRecord(
    casesPlayed: 0,
    casesAsWitness: 0,
    casesAsInformant: 0,
    casesWon: 0,
    casesLost: 0,
    correctUnmasks: 0,
    votesCast: 0,
    voteAccuracy: null,
    survivedAsMafiaCount: 0,
    currentStreak: 0,
    recruitmentsExecuted: 0,
  );
}

/// Walks [moments] (which may span many cases) newest-first and counts how
/// many consecutive round-outcome moments in a row are a "good outcome" —
/// stops at the first one that isn't, ignoring [_nonOutcomeTypes] entirely
/// rather than letting them break the run.
int computeCurrentStreak(List<GameMoment> moments) {
  final outcomeEvents = moments.where((m) => !_nonOutcomeTypes.contains(m.type)).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  var streak = 0;
  for (final moment in outcomeEvents) {
    if (!_goodOutcomeTypes.contains(moment.type)) break;
    streak++;
  }
  return streak;
}

/// Whether [player] was ever on the mafia side of this case — current role
/// is `mafia`, or they were unmasked at some point (and so flipped to
/// `villager`). Mirrors the exact "ever mafia" check
/// `LocalGameRepository` itself uses to decide win/loss (see the
/// [GameMomentType.finaleWin]/[GameMomentType.finaleLoss] split).
bool _wasEverInformant(Player player) => player.role == PlayerRole.mafia || player.wasUnmasked;

/// Aggregates [viewerId]'s full track record across every case they've
/// joined. Pure client-side aggregation over already-recorded data — no
/// new backend, just [GameRepository] reads.
Future<TrackRecord> computeTrackRecord({
  required GameRepository repo,
  required String viewerId,
}) async {
  final allGames = await repo.watchGames(viewerId: viewerId).first;
  final myGames = <Game, Player>{
    for (final game in allGames)
      if (game.playerById(viewerId) case final player?) game: player,
  };

  if (myGames.isEmpty) return TrackRecord.empty;

  var casesAsInformant = 0;
  var survivedAsMafiaCount = 0;
  var votesCast = 0;
  final allMoments = <GameMoment>[];

  for (final entry in myGames.entries) {
    final game = entry.key;
    final player = entry.value;

    if (_wasEverInformant(player)) casesAsInformant++;
    if (game.status == GameStatus.ended &&
        player.role == PlayerRole.mafia &&
        !player.wasUnmasked &&
        !player.hasLeft) {
      survivedAsMafiaCount++;
    }

    final votes = await repo.watchVoteHistory(game.id).first;
    votesCast += votes.where((v) => v.voterId == viewerId).length;

    allMoments.addAll(await repo.fetchAllMoments(gameId: game.id, playerId: viewerId));
  }

  final correctUnmasks = allMoments.where((m) => m.type == GameMomentType.correctVoteReward).length;
  final casesWon = allMoments.where((m) => m.type == GameMomentType.finaleWin).length;
  final casesLost = allMoments.where((m) => m.type == GameMomentType.finaleLoss).length;
  final recruitmentsExecuted =
      allMoments.where((m) => m.type == GameMomentType.recruitmentExecuted).length;

  return TrackRecord(
    casesPlayed: myGames.length,
    casesAsWitness: myGames.length - casesAsInformant,
    casesAsInformant: casesAsInformant,
    casesWon: casesWon,
    casesLost: casesLost,
    correctUnmasks: correctUnmasks,
    votesCast: votesCast,
    voteAccuracy: votesCast == 0 ? null : correctUnmasks / votesCast,
    survivedAsMafiaCount: survivedAsMafiaCount,
    currentStreak: computeCurrentStreak(allMoments),
    recruitmentsExecuted: recruitmentsExecuted,
  );
}
