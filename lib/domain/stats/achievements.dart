import 'track_record.dart';

/// A player's cross-case standing, climbed purely on [TrackRecord.casesPlayed]
/// — deliberately activity-based rather than a skill-weighted composite, so
/// it never punishes bad luck and is trivial to explain ("play more cases").
/// Skill is instead expressed through [BadgeDef]s. The second layer of
/// `office_game_concept_season1.md` section 5's "future ranking/hierarchy
/// system" (the first being the in-case +1 vote-weight reward itself).
enum Rank {
  rookie(0, 'Rookie'),
  associate(5, 'Associate'),
  detective(15, 'Detective'),
  inspector(30, 'Inspector'),
  chiefInspector(60, 'Chief Inspector'),
  legend(100, 'Legend');

  final int minCasesPlayed;
  final String label;

  const Rank(this.minCasesPlayed, this.label);

  /// The highest tier whose [minCasesPlayed] is met by [casesPlayed] —
  /// [Rank.values] is declared in ascending threshold order, so the last
  /// match wins.
  static Rank forCasesPlayed(int casesPlayed) {
    var current = Rank.rookie;
    for (final rank in Rank.values) {
      if (casesPlayed >= rank.minCasesPlayed) current = rank;
    }
    return current;
  }

  /// The tier directly above this one, or null at [legend] — there's
  /// nothing further to climb toward.
  Rank? get next {
    final i = Rank.values.indexOf(this);
    return i + 1 < Rank.values.length ? Rank.values[i + 1] : null;
  }
}

enum BadgeId {
  firstCase,
  caseClosed,
  sharpEye,
  bloodhound,
  perfectRead,
  onARoll,
  unstoppable,
  undercover,
  ghost,
  recruiter,
  veteran,
  centuryClub,
}

/// A discrete, milestone-based unlock — [isUnlocked] is a pure predicate
/// over [TrackRecord], so (like [Rank]) nothing about a player's badges
/// needs its own storage; it's recomputed from the same aggregate every
/// time the Profile screen loads. Icon choice is a UI-layer concern (see
/// `profile_screen.dart`) — this stays Flutter-free, matching
/// `track_record.dart`'s own style.
class BadgeDef {
  final BadgeId id;
  final String label;
  final String description;
  final bool Function(TrackRecord record) isUnlocked;

  const BadgeDef({
    required this.id,
    required this.label,
    required this.description,
    required this.isUnlocked,
  });
}

const List<BadgeDef> allBadges = [
  BadgeDef(
    id: BadgeId.firstCase,
    label: 'First Case',
    description: 'Join your first case.',
    isUnlocked: _firstCase,
  ),
  BadgeDef(
    id: BadgeId.caseClosed,
    label: 'Case Closed',
    description: 'Win a case.',
    isUnlocked: _caseClosed,
  ),
  BadgeDef(
    id: BadgeId.sharpEye,
    label: 'Sharp Eye',
    description: 'Cast the vote that unmasks an Informant.',
    isUnlocked: _sharpEye,
  ),
  BadgeDef(
    id: BadgeId.bloodhound,
    label: 'Bloodhound',
    description: 'Correctly unmask an Informant 10 times.',
    isUnlocked: _bloodhound,
  ),
  BadgeDef(
    id: BadgeId.perfectRead,
    label: 'Perfect Read',
    description: 'Never miscast a vote, across at least 5 votes.',
    isUnlocked: _perfectRead,
  ),
  BadgeDef(
    id: BadgeId.onARoll,
    label: 'On a Roll',
    description: 'String together a streak of 3 good rounds.',
    isUnlocked: _onARoll,
  ),
  BadgeDef(
    id: BadgeId.unstoppable,
    label: 'Unstoppable',
    description: 'String together a streak of 7 good rounds.',
    isUnlocked: _unstoppable,
  ),
  BadgeDef(
    id: BadgeId.undercover,
    label: 'Undercover',
    description: 'Complete a case as an Informant without being unmasked.',
    isUnlocked: _undercover,
  ),
  BadgeDef(
    id: BadgeId.ghost,
    label: 'Ghost',
    description: 'Survive 5 cases as an Informant, unmasked.',
    isUnlocked: _ghost,
  ),
  BadgeDef(
    id: BadgeId.recruiter,
    label: 'Recruiter',
    description: 'Successfully recruit another player.',
    isUnlocked: _recruiter,
  ),
  BadgeDef(
    id: BadgeId.veteran,
    label: 'Veteran',
    description: 'Play 25 cases.',
    isUnlocked: _veteran,
  ),
  BadgeDef(
    id: BadgeId.centuryClub,
    label: 'Century Club',
    description: 'Play 100 cases.',
    isUnlocked: _centuryClub,
  ),
];

bool _firstCase(TrackRecord r) => r.casesPlayed >= 1;
bool _caseClosed(TrackRecord r) => r.casesWon >= 1;
bool _sharpEye(TrackRecord r) => r.correctUnmasks >= 1;
bool _bloodhound(TrackRecord r) => r.correctUnmasks >= 10;
bool _perfectRead(TrackRecord r) => r.voteAccuracy == 1.0 && r.votesCast >= 5;
bool _onARoll(TrackRecord r) => r.currentStreak >= 3;
bool _unstoppable(TrackRecord r) => r.currentStreak >= 7;
bool _undercover(TrackRecord r) => r.survivedAsMafiaCount >= 1;
bool _ghost(TrackRecord r) => r.survivedAsMafiaCount >= 5;
bool _recruiter(TrackRecord r) => r.recruitmentsExecuted >= 1;
bool _veteran(TrackRecord r) => r.casesPlayed >= 25;
bool _centuryClub(TrackRecord r) => r.casesPlayed >= 100;
