import 'player.dart';

enum GameStatus { recruiting, active, ended }

/// Who a finished game's outcome favored. Villagers win the instant no
/// living mafia member remains (all unmasked, or all left); mafia win the
/// instant they reach parity or a majority against living villagers — the
/// "comeback" recruitment exists to make possible (concept doc section 4).
/// There's no fixed season length; whichever condition is met first ends
/// the game.
enum GameWinner { villagers, mafia }

/// A single running game at a location. Multiple `Game`s can exist
/// concurrently for the same `locationTag` (section 3).
class Game {
  final String id;
  final String locationTag;
  final GameStatus status;
  final int minPlayers;
  final List<Player> players;
  final int currentRound;

  /// Free text the creator writes at case creation describing this case's
  /// own variant of the rules (e.g. "players use real names and
  /// departments" vs. "identities are anonymous, figure it out yourself")
  /// — shown to a prospective player before they join, alongside the
  /// roster. Optional; blank is a normal, unremarkable value, not an
  /// error state.
  final String rulesDescription;

  /// How many mafia members are drawn at [status] transition to `active`
  /// — a direct target count, not a ratio, so it always lands exactly
  /// (clamped to at least 1 and at most the roster size at start —
  /// section 5's split is a starting parameter to tune, not a fixed
  /// rule). Editable per case at creation.
  final int mafiaCount;

  /// The mafia:villager ratio at or below which [recruitmentUnlocked]
  /// flips true (section 8) — e.g. 0.2 for "1:5 or thinner". Editable per
  /// case at creation, same reasoning as [mafiaCount].
  final double recruitmentUnlockThreshold;

  /// How long an agreed elimination or recruitment proposal stays live
  /// before it lapses (also capped by the round ending, whichever comes
  /// first). Editable per case at creation.
  final Duration executionWindow;

  /// Time-of-day (since midnight) the working day's votes resolve on
  /// their own, with no one needing to press anything — section 10's
  /// "a sensible default fallback, e.g. 5:00 PM". Editable per case at
  /// creation; the repository reschedules the next occurrence itself
  /// every time a round actually resolves, by whatever means.
  final Duration dailyCutoffTime;

  /// Today's elimination method (e.g. "a note left on your monitor") —
  /// the *method* is public to all villagers, never the target (section
  /// 6). Set the moment every active mafia member agrees on it, well
  /// before it's actually carried out, so there's real day-long vigilance
  /// to watch for it.
  final String? eliminationMethodDescription;

  /// True once a mafia member has confirmed they actually carried out the
  /// agreed method — this is also the moment the target's vote weight
  /// drops. Before this, [eliminationMethodDescription] is only a
  /// forewarning of what to watch for.
  final bool eliminationSignalExecuted;

  /// True once the actual target has acknowledged receiving the signal.
  /// Public to every villager as a general "the hit landed" confirmation —
  /// without revealing who was targeted.
  final bool eliminationSignalConfirmed;

  /// Today's recruitment sign (e.g. "a specific pen left on their desk")
  /// — mirrors [eliminationMethodDescription] exactly: public to every
  /// villager the moment every active mafia member agrees on it, target
  /// never revealed, well before anyone actually delivers it.
  final String? recruitmentSignDescription;

  /// True once a mafia member has confirmed they actually delivered the
  /// sign to the target — this is also the moment the target actually
  /// sees the offer waiting for them. Mirrors [eliminationSignalExecuted].
  final bool recruitmentSignExecuted;

  /// True once the actual target has responded (accepted or declined —
  /// either way). Public to every villager as a general "it landed"
  /// confirmation, without revealing who or which way they answered.
  /// Mirrors [eliminationSignalConfirmed].
  final bool recruitmentSignConfirmed;

  /// Set the moment [status] flips to `ended` — null until then, and
  /// never cleared afterward.
  final GameWinner? winner;

  final DateTime createdAt;

  /// True if this case requires a 3-word passphrase to get past its
  /// [CaseDetailsScreen] and actually join — the passphrase itself never
  /// lives on this model (or anywhere else a prospective, not-yet-joined
  /// player can read): `GameRepository.verifyPassphrase` and the
  /// [addPlayer] passphrase check are the only ways to test it. This flag
  /// alone is what the case list badges as "Restricted" so prospective
  /// players know to ask for it before tapping in.
  final bool isRestricted;

  /// The player who created this case — acts as its admin (e.g. the only
  /// one who can look up a restricted case's passphrase again after
  /// creation). Never changes after creation.
  final String creatorId;

  const Game({
    required this.id,
    required this.locationTag,
    this.status = GameStatus.recruiting,
    required this.minPlayers,
    this.players = const [],
    this.currentRound = 1,
    this.rulesDescription = '',
    this.mafiaCount = 1,
    this.recruitmentUnlockThreshold = 0.2,
    this.executionWindow = const Duration(hours: 1),
    this.dailyCutoffTime = const Duration(hours: 17),
    this.eliminationMethodDescription,
    this.eliminationSignalExecuted = false,
    this.eliminationSignalConfirmed = false,
    this.recruitmentSignDescription,
    this.recruitmentSignExecuted = false,
    this.recruitmentSignConfirmed = false,
    this.winner,
    required this.createdAt,
    this.isRestricted = false,
    required this.creatorId,
  });

  Player? playerById(String playerId) {
    for (final player in players) {
      if (player.id == playerId) return player;
    }
    return null;
  }

  List<Player> get mafia =>
      players.where((p) => p.role == PlayerRole.mafia).toList();

  /// Mafia who can currently act: not sick-leave-inactive, and not gone
  /// for good ([Player.hasLeft]) — a departed member can never come back
  /// as "active" the way a returning-from-leave one can, so this excludes
  /// them regardless of their (now-meaningless) [Player.isActive] value.
  List<Player> get activeMafia =>
      mafia.where((p) => p.isActive && !p.hasLeft).toList();

  List<Player> get villagers =>
      players.where((p) => p.role == PlayerRole.villager).toList();

  /// Mafia who are still actually in the game — excludes anyone who's
  /// [Player.hasLeft], since a departed member isn't a threat anymore.
  List<Player> get livingMafia => mafia.where((p) => !p.hasLeft).toList();

  /// Villagers who are still actually in the game — see [livingMafia].
  List<Player> get livingVillagers => villagers.where((p) => !p.hasLeft).toList();

  /// Recruitment unlocks once the mafia:villager ratio *drops* to
  /// [recruitmentUnlockThreshold] or thinner (section 8) — i.e. once mafia
  /// are a small minority relative to villagers and need reinforcement,
  /// not once they're already well-stocked. Uses *living* counts, same as
  /// the win-condition check — someone who's left shouldn't keep propping
  /// up (or dragging down) a ratio they're no longer part of.
  bool get recruitmentUnlocked {
    final mafiaCount = livingMafia.length;
    final villagerCount = livingVillagers.length;
    if (mafiaCount == 0 || villagerCount == 0) return false;
    return mafiaCount / villagerCount <= recruitmentUnlockThreshold;
  }

  Game copyWith({
    GameStatus? status,
    List<Player>? players,
    int? currentRound,
    String? eliminationMethodDescription,
    bool clearEliminationMethodDescription = false,
    bool? eliminationSignalExecuted,
    bool? eliminationSignalConfirmed,
    String? recruitmentSignDescription,
    bool clearRecruitmentSignDescription = false,
    bool? recruitmentSignExecuted,
    bool? recruitmentSignConfirmed,
    GameWinner? winner,
  }) {
    return Game(
      id: id,
      locationTag: locationTag,
      status: status ?? this.status,
      minPlayers: minPlayers,
      players: players ?? this.players,
      currentRound: currentRound ?? this.currentRound,
      rulesDescription: rulesDescription,
      mafiaCount: mafiaCount,
      recruitmentUnlockThreshold: recruitmentUnlockThreshold,
      executionWindow: executionWindow,
      dailyCutoffTime: dailyCutoffTime,
      eliminationMethodDescription: clearEliminationMethodDescription
          ? null
          : (eliminationMethodDescription ?? this.eliminationMethodDescription),
      eliminationSignalExecuted:
          eliminationSignalExecuted ?? this.eliminationSignalExecuted,
      eliminationSignalConfirmed:
          eliminationSignalConfirmed ?? this.eliminationSignalConfirmed,
      recruitmentSignDescription: clearRecruitmentSignDescription
          ? null
          : (recruitmentSignDescription ?? this.recruitmentSignDescription),
      recruitmentSignExecuted:
          recruitmentSignExecuted ?? this.recruitmentSignExecuted,
      recruitmentSignConfirmed:
          recruitmentSignConfirmed ?? this.recruitmentSignConfirmed,
      winner: winner ?? this.winner,
      createdAt: createdAt,
      isRestricted: isRestricted,
      creatorId: creatorId,
    );
  }
}
