enum MafiaThreadEntryType { message, proposal, recruitment }

/// An entry in the mafia's async coordination channel (section 7).
/// Readable only by current mafia members — enforced in
/// `GameRepository.watchMafiaThread`, not by hiding it in the UI.
///
/// Both [MafiaThreadEntryType.proposal] (elimination) and
/// [MafiaThreadEntryType.recruitment] move through the same lifecycle:
/// pending acceptance → [agreedAt] set once every active mafia member has
/// accepted (the execution window opens) → [executedAt] once a mafia
/// member confirms they carried it out in the real world → [confirmedAt]
/// once the target responds, or [lapsed] if the window (1 hour, or the
/// round ending — whichever is first) closes before anyone executes.
class MafiaThreadEntry {
  final String id;
  final String gameId;
  final int round;
  final String authorId;
  final MafiaThreadEntryType type;

  /// Free-text note, used when [type] is [MafiaThreadEntryType.message].
  final String? message;

  /// Proposed elimination method description (e.g. "a note on the monitor"),
  /// used when [type] is [MafiaThreadEntryType.proposal].
  final String? proposedMethod;

  /// The villager targeted — an elimination target when [type] is
  /// [MafiaThreadEntryType.proposal], a recruitment target when [type] is
  /// [MafiaThreadEntryType.recruitment]. Never shown outside the mafia
  /// thread.
  final String? proposedTargetId;

  /// Active mafia members who have accepted this proposal.
  final List<String> acceptedByPlayerIds;

  /// Set the moment every currently-active mafia member has accepted —
  /// this starts the execution countdown. Null while still gathering
  /// acceptances.
  final DateTime? agreedAt;

  /// Set when a mafia member confirms they carried it out in the real
  /// world: for a [MafiaThreadEntryType.proposal] this is the moment the
  /// target's vote weight drops and the signal becomes visible to
  /// villagers; for a [MafiaThreadEntryType.recruitment] this is the
  /// moment the target actually sees the offer waiting for them.
  final DateTime? executedAt;

  /// Who called [executedAt] — for recruitment this is the mafia member
  /// who actually approached the target, and becomes their recruiter
  /// (cell structure, design pillar #4), since that's who the target had
  /// the real conversation with.
  final String? executedByPlayerId;

  /// True once the execution window closed with no [executedAt] — the
  /// agreed action lapses and is never applied.
  final bool lapsed;

  /// The target's response. For a [MafiaThreadEntryType.proposal], set
  /// once the actual target has acknowledged receiving the signal
  /// (section 6). For a [MafiaThreadEntryType.recruitment], set once the
  /// target answers the offer — see [recruitmentAccepted] for which way.
  final DateTime? confirmedAt;

  /// Only meaningful when [type] is [MafiaThreadEntryType.recruitment]:
  /// null until the target responds, then true (joined) or false
  /// (declined).
  final bool? recruitmentAccepted;

  final DateTime createdAt;

  bool get resolved => executedAt != null;

  const MafiaThreadEntry({
    required this.id,
    required this.gameId,
    required this.round,
    required this.authorId,
    required this.type,
    this.message,
    this.proposedMethod,
    this.proposedTargetId,
    this.acceptedByPlayerIds = const [],
    this.agreedAt,
    this.executedAt,
    this.executedByPlayerId,
    this.lapsed = false,
    this.confirmedAt,
    this.recruitmentAccepted,
    required this.createdAt,
  });

  MafiaThreadEntry copyWith({
    List<String>? acceptedByPlayerIds,
    DateTime? agreedAt,
    DateTime? executedAt,
    String? executedByPlayerId,
    bool? lapsed,
    DateTime? confirmedAt,
    bool? recruitmentAccepted,
  }) {
    return MafiaThreadEntry(
      id: id,
      gameId: gameId,
      round: round,
      authorId: authorId,
      type: type,
      message: message,
      proposedMethod: proposedMethod,
      proposedTargetId: proposedTargetId,
      acceptedByPlayerIds: acceptedByPlayerIds ?? this.acceptedByPlayerIds,
      agreedAt: agreedAt ?? this.agreedAt,
      executedAt: executedAt ?? this.executedAt,
      executedByPlayerId: executedByPlayerId ?? this.executedByPlayerId,
      lapsed: lapsed ?? this.lapsed,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      recruitmentAccepted: recruitmentAccepted ?? this.recruitmentAccepted,
      createdAt: createdAt,
    );
  }
}
