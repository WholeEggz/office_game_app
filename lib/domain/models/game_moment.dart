/// A discrete, player-specific "something happened to you" event, recorded
/// by the repository at the exact instant it occurs (a vote reward, a
/// successful recruitment, the case ending, a round simply ending) rather
/// than inferred later by diffing before/after state. That's what lets a
/// player who wasn't looking at the time catch up on everything they
/// missed the next time they open this case, in the order it happened.
enum GameMomentType {
  /// Voted for an Informant who got unmasked this round — the standard +1
  /// vote weight reward for a correct read.
  correctVoteReward,

  /// Successfully executed a recruitment — the target accepted.
  recruitmentExecuted,

  /// Was recruited and just switched sides.
  recruitedSwitchSides,

  /// The case ended and this player's side won.
  finaleWin,

  /// The case ended and this player's side lost.
  finaleLoss,

  /// A round ended with nothing more specific to report for this player —
  /// the fallback so a round never passes with zero acknowledgement.
  roundEnded,
}

class GameMoment {
  final String id;
  final String gameId;
  final String playerId;
  final GameMomentType type;
  final int round;
  final DateTime createdAt;

  const GameMoment({
    required this.id,
    required this.gameId,
    required this.playerId,
    required this.type,
    required this.round,
    required this.createdAt,
  });
}
