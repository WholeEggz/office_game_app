/// A villager's logged observation (section 10). Deliberately ephemeral —
/// callers purge entries older than 3 rounds so this never becomes a
/// permanent, searchable record of accusations against real coworkers.
class Observation {
  final String id;
  final String gameId;
  final String authorId;

  /// Null for a general observation, otherwise the player it's about.
  final String? targetPlayerId;

  final String text;
  final int round;
  final DateTime createdAt;

  const Observation({
    required this.id,
    required this.gameId,
    required this.authorId,
    this.targetPlayerId,
    required this.text,
    required this.round,
    required this.createdAt,
  });
}
