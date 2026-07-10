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

  /// An Informant was unmasked this round by *someone else's* vote — for
  /// every player who isn't the target and isn't a rewarded voter (see
  /// [correctVoteReward]), so the case's biggest event of the round is
  /// still acknowledged for them, just without personal credit.
  mafiaUnmaskedByOthers,

  /// The mafia's elimination signal landed on this villager — the target
  /// of [GameRepository.executeElimination], discovering their own
  /// weight loss.
  targetedByMafia,

  /// This villager's fellow villagers cast the round's winning vote
  /// against *them*, eroding their weight the same way a mafia hit would.
  targetedByVillagers,

  /// Successfully executed a recruitment — the target accepted.
  recruitmentExecuted,

  /// Was recruited and just switched sides.
  recruitedSwitchSides,

  /// The case ended and this player's side won.
  finaleWin,

  /// The case ended and this player's side lost.
  finaleLoss,

  /// Just joined this case for the first time (as its creator or by
  /// joining an existing one).
  joinedCase,

  /// Opened a case they'd already joined, on any visit after the first.
  reenteredCase,

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
