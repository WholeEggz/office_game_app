import '../models/game.dart';
import '../models/mafia_thread_entry.dart';
import '../models/observation.dart';
import '../models/player.dart';
import '../models/vote.dart';

/// Everything a [HintDefinition]'s predicates need to judge relevance and
/// completion for one player in one game — assembled from the same
/// repository streams `GameScreen` already subscribes to, never fetched
/// separately.
class HintContext {
  final Game game;
  final Player self;
  final List<Observation> observations;
  final List<Vote> currentRoundVotes;
  final List<Vote> voteHistory;
  final List<MafiaThreadEntry> mafiaThread;

  /// Hint ids [self] has manually dismissed for this game — only hints with
  /// no natural completion signal of their own ever consult this (see
  /// `HintDefinition.dismissible`).
  final Set<String> dismissedHintIds;

  const HintContext({
    required this.game,
    required this.self,
    required this.observations,
    required this.currentRoundVotes,
    required this.voteHistory,
    required this.mafiaThread,
    required this.dismissedHintIds,
  });

  bool get isCurrentMafia => self.role == PlayerRole.mafia && !self.wasUnmasked;

  /// Note: [observations] is already limited to the last 3 rounds (the
  /// repository purges older entries), so this can read `false` again for a
  /// player who posted once long ago and has been quiet since — acceptable
  /// here since the nudge ("say something") is still a reasonable one.
  bool get hasEverPosted => observations.any((o) => o.authorId == self.id);

  bool get hasPostedThisRound =>
      observations.any((o) => o.authorId == self.id && o.round == game.currentRound);

  bool get hasEverVoted => voteHistory.any((v) => v.voterId == self.id);

  bool get hasVotedThisRound => currentRoundVotes.any((v) => v.voterId == self.id);

  bool get hasPostedToMafiaThread => mafiaThread.any((m) => m.authorId == self.id);
}
