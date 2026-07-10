enum PlayerRole { villager, mafia }

/// A player in a single game. Role, vote weight, and cell-structure links
/// all live here rather than being split across separate collections, since
/// every rule in the concept doc (erosion, recruitment, unmasking) mutates
/// this same shape.
class Player {
  final String id;
  final String name;
  final PlayerRole role;
  final int voteWeight;

  /// Mafia-only: 24h/end-of-day absence flag (section 7). Ignored for villagers.
  final bool isActive;

  /// Cell structure (design pillar #4): who recruited this player into the
  /// mafia. Null for the founding roster and for villagers.
  final String? recruiterId;

  /// Cell structure: players this member has personally recruited.
  final List<String> recruitedPlayerIds;

  /// True once a mafia member has been voted out and flipped to villager
  /// (section 9). A villager can never have this set.
  final bool wasUnmasked;

  /// An open recruitment offer awaiting this player's answer (section 8).
  /// Only ever set on a weight-0 villager; cleared on accept or decline.
  final String? pendingRecruiterId;

  /// True once this player has voluntarily left the game (moved on, no
  /// longer wants to play — distinct from [isActive], which is a
  /// temporary mafia-only "on leave" toggle). A player who has left stays
  /// in [Game.players] (so their name still resolves in vote/observation
  /// history) but can no longer vote, be voted for, be targeted for
  /// elimination/recruitment, or act as mafia even if their role is
  /// still `mafia` under the hood.
  final bool hasLeft;

  final DateTime joinedAt;

  const Player({
    required this.id,
    required this.name,
    required this.role,
    this.voteWeight = 3,
    this.isActive = true,
    this.recruiterId,
    this.recruitedPlayerIds = const [],
    this.wasUnmasked = false,
    this.pendingRecruiterId,
    this.hasLeft = false,
    required this.joinedAt,
  });

  Player copyWith({
    String? name,
    PlayerRole? role,
    int? voteWeight,
    bool? isActive,
    String? recruiterId,
    List<String>? recruitedPlayerIds,
    bool? wasUnmasked,
    String? pendingRecruiterId,
    bool clearPendingRecruiterId = false,
    bool? hasLeft,
  }) {
    return Player(
      id: id,
      name: name ?? this.name,
      role: role ?? this.role,
      voteWeight: voteWeight ?? this.voteWeight,
      isActive: isActive ?? this.isActive,
      recruiterId: recruiterId ?? this.recruiterId,
      recruitedPlayerIds: recruitedPlayerIds ?? this.recruitedPlayerIds,
      wasUnmasked: wasUnmasked ?? this.wasUnmasked,
      pendingRecruiterId: clearPendingRecruiterId
          ? null
          : (pendingRecruiterId ?? this.pendingRecruiterId),
      hasLeft: hasLeft ?? this.hasLeft,
      joinedAt: joinedAt,
    );
  }
}
