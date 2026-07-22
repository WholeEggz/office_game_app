import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/domain/stats/achievements.dart';
import 'package:office_game_app/domain/stats/track_record.dart';

TrackRecord _record({
  int casesPlayed = 0,
  int casesAsWitness = 0,
  int casesAsInformant = 0,
  int casesWon = 0,
  int casesLost = 0,
  int correctUnmasks = 0,
  int votesCast = 0,
  double? voteAccuracy,
  int survivedAsMafiaCount = 0,
  int currentStreak = 0,
  int recruitmentsExecuted = 0,
}) {
  return TrackRecord(
    casesPlayed: casesPlayed,
    casesAsWitness: casesAsWitness,
    casesAsInformant: casesAsInformant,
    casesWon: casesWon,
    casesLost: casesLost,
    correctUnmasks: correctUnmasks,
    votesCast: votesCast,
    voteAccuracy: voteAccuracy,
    survivedAsMafiaCount: survivedAsMafiaCount,
    currentStreak: currentStreak,
    recruitmentsExecuted: recruitmentsExecuted,
  );
}

void main() {
  group('Rank.forCasesPlayed', () {
    test('sits at Rookie below the Associate threshold', () {
      expect(Rank.forCasesPlayed(0), Rank.rookie);
      expect(Rank.forCasesPlayed(4), Rank.rookie);
    });

    test('climbs at each exact threshold, not one before it', () {
      expect(Rank.forCasesPlayed(5), Rank.associate);
      expect(Rank.forCasesPlayed(14), Rank.associate);
      expect(Rank.forCasesPlayed(15), Rank.detective);
      expect(Rank.forCasesPlayed(29), Rank.detective);
      expect(Rank.forCasesPlayed(30), Rank.inspector);
      expect(Rank.forCasesPlayed(59), Rank.inspector);
      expect(Rank.forCasesPlayed(60), Rank.chiefInspector);
      expect(Rank.forCasesPlayed(99), Rank.chiefInspector);
      expect(Rank.forCasesPlayed(100), Rank.legend);
      expect(Rank.forCasesPlayed(500), Rank.legend);
    });

    test('Rank.next walks the ladder, and Legend has no next', () {
      expect(Rank.rookie.next, Rank.associate);
      expect(Rank.associate.next, Rank.detective);
      expect(Rank.detective.next, Rank.inspector);
      expect(Rank.inspector.next, Rank.chiefInspector);
      expect(Rank.chiefInspector.next, Rank.legend);
      expect(Rank.legend.next, isNull);
    });
  });

  group('badge unlock predicates', () {
    BadgeDef badge(BadgeId id) => allBadges.singleWhere((b) => b.id == id);

    test('firstCase unlocks on any case played', () {
      expect(badge(BadgeId.firstCase).isUnlocked(_record(casesPlayed: 0)), isFalse);
      expect(badge(BadgeId.firstCase).isUnlocked(_record(casesPlayed: 1)), isTrue);
    });

    test('caseClosed unlocks on the first win', () {
      expect(badge(BadgeId.caseClosed).isUnlocked(_record(casesWon: 0)), isFalse);
      expect(badge(BadgeId.caseClosed).isUnlocked(_record(casesWon: 1)), isTrue);
    });

    test('sharpEye and bloodhound gate on correctUnmasks at 1 and 10', () {
      expect(badge(BadgeId.sharpEye).isUnlocked(_record(correctUnmasks: 1)), isTrue);
      expect(badge(BadgeId.bloodhound).isUnlocked(_record(correctUnmasks: 9)), isFalse);
      expect(badge(BadgeId.bloodhound).isUnlocked(_record(correctUnmasks: 10)), isTrue);
    });

    test('perfectRead requires both 100% accuracy and a minimum sample of 5 votes', () {
      final tinyPerfect = _record(correctUnmasks: 2, votesCast: 2, voteAccuracy: 1.0);
      expect(badge(BadgeId.perfectRead).isUnlocked(tinyPerfect), isFalse);
      final bigPerfect = _record(correctUnmasks: 5, votesCast: 5, voteAccuracy: 1.0);
      expect(badge(BadgeId.perfectRead).isUnlocked(bigPerfect), isTrue);
      final bigButImperfect = _record(correctUnmasks: 4, votesCast: 5, voteAccuracy: 0.8);
      expect(badge(BadgeId.perfectRead).isUnlocked(bigButImperfect), isFalse);
    });

    test('onARoll and unstoppable gate on currentStreak at 3 and 7', () {
      expect(badge(BadgeId.onARoll).isUnlocked(_record(currentStreak: 2)), isFalse);
      expect(badge(BadgeId.onARoll).isUnlocked(_record(currentStreak: 3)), isTrue);
      expect(badge(BadgeId.unstoppable).isUnlocked(_record(currentStreak: 6)), isFalse);
      expect(badge(BadgeId.unstoppable).isUnlocked(_record(currentStreak: 7)), isTrue);
    });

    test('undercover and ghost gate on survivedAsMafiaCount at 1 and 5', () {
      expect(badge(BadgeId.undercover).isUnlocked(_record(survivedAsMafiaCount: 1)), isTrue);
      expect(badge(BadgeId.ghost).isUnlocked(_record(survivedAsMafiaCount: 4)), isFalse);
      expect(badge(BadgeId.ghost).isUnlocked(_record(survivedAsMafiaCount: 5)), isTrue);
    });

    test('recruiter unlocks on the first successful recruitment', () {
      expect(badge(BadgeId.recruiter).isUnlocked(_record(recruitmentsExecuted: 0)), isFalse);
      expect(badge(BadgeId.recruiter).isUnlocked(_record(recruitmentsExecuted: 1)), isTrue);
    });

    test('veteran and centuryClub gate on casesPlayed at 25 and 100', () {
      expect(badge(BadgeId.veteran).isUnlocked(_record(casesPlayed: 24)), isFalse);
      expect(badge(BadgeId.veteran).isUnlocked(_record(casesPlayed: 25)), isTrue);
      expect(badge(BadgeId.centuryClub).isUnlocked(_record(casesPlayed: 99)), isFalse);
      expect(badge(BadgeId.centuryClub).isUnlocked(_record(casesPlayed: 100)), isTrue);
    });

    test('every badge has a unique id', () {
      final ids = allBadges.map((b) => b.id).toSet();
      expect(ids, hasLength(allBadges.length));
    });
  });
}
