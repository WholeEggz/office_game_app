/// A single villager's vote for a suspected mafia member, cast any time
/// during the day and tallied at the day's cutoff (section 10).
class Vote {
  final String id;
  final String gameId;
  final String voterId;
  final String targetPlayerId;
  final int round;

  /// The voter's vote weight at the moment the vote was cast — a
  /// weight-0 player can still cast a vote, it just won't count (section 5).
  final int weight;

  final DateTime createdAt;

  const Vote({
    required this.id,
    required this.gameId,
    required this.voterId,
    required this.targetPlayerId,
    required this.round,
    required this.weight,
    required this.createdAt,
  });
}
