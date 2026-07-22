import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/data/local/local_auth_service.dart';
import 'package:office_game_app/data/local/local_game_repository.dart';
import 'package:office_game_app/domain/repositories/auth_service.dart';
import 'package:office_game_app/domain/repositories/game_repository.dart';
import 'package:office_game_app/domain/stats/track_record.dart';
import 'package:office_game_app/ui/profile/profile_screen.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
      'no rank or badge tile overflows, including ones scrolled past the initial viewport',
      (tester) async {
    // Every threshold met — casesPlayed: 100 alone reaches Legend and
    // unlocks every cases-played-gated badge; the rest of the fields
    // unlock every remaining badge too, so every tile in both horizontal
    // lists renders its real (unlocked) label, all the way to the last
    // one — a lazy ListView only builds/lays out what's scrolled into
    // view, so a tile past the initial viewport (e.g. "Recruiter",
    // "Veteran", "Century Club") needs an actual scroll to be checked.
    const record = TrackRecord(
      casesPlayed: 100,
      casesAsWitness: 100,
      casesAsInformant: 0,
      casesWon: 1,
      casesLost: 0,
      correctUnmasks: 10,
      votesCast: 10,
      voteAccuracy: 1.0,
      survivedAsMafiaCount: 5,
      currentStreak: 7,
      recruitmentsExecuted: 1,
    );

    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<GameRepository>.value(value: LocalGameRepository()),
        Provider<AuthService>.value(value: LocalAuthService()),
      ],
      child: const MaterialApp(
        home: ProfileScreen(
          viewerId: 'p1',
          viewerName: 'Alice',
          record: record,
          initialProfile: null,
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);

    // Drag each horizontal list, a bit at a time, all the way to its end
    // — a single huge drag can jump past intermediate items without ever
    // laying them out; several smaller drags force each one to actually
    // build in turn.
    Future<void> scrollFullyThrough(Key key) async {
      final finder = find.byKey(key);
      // The page itself is a vertical ListView taller than the test
      // surface — bring this row into the visible viewport first, or the
      // horizontal drag below has nothing on-screen to hit-test against.
      await tester.ensureVisible(finder);
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await tester.drag(finder, const Offset(-200, 0));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'overflow after scroll step $i on $key');
      }
    }

    await scrollFullyThrough(const ValueKey('rank_ladder_list'));
    await scrollFullyThrough(const ValueKey('badges_list'));

    // Confirms the scroll actually reached the last items, not just that
    // no exception happened to fire yet.
    expect(find.text('Legend'), findsOneWidget);
    expect(find.text('Century Club'), findsOneWidget);
  });

  testWidgets('tiles do not overflow under a larger accessibility text-scale setting',
      (tester) async {
    const record = TrackRecord(
      casesPlayed: 60,
      casesAsWitness: 60,
      casesAsInformant: 0,
      casesWon: 1,
      casesLost: 0,
      correctUnmasks: 1,
      votesCast: 1,
      voteAccuracy: 1.0,
      survivedAsMafiaCount: 0,
      currentStreak: 0,
      recruitmentsExecuted: 0,
    );

    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<GameRepository>.value(value: LocalGameRepository()),
        Provider<AuthService>.value(value: LocalAuthService()),
      ],
      child: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: const MaterialApp(
          home: ProfileScreen(
            viewerId: 'p1',
            viewerName: 'Alice',
            record: record,
            initialProfile: null,
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
