import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/data/local/local_game_repository.dart';
import 'package:office_game_app/domain/repositories/game_repository.dart';
import 'package:office_game_app/ui/entry/case_creation_screen.dart';
import 'package:provider/provider.dart';

void main() {
  Finder villagersField() => find.byKey(const ValueKey('roster_villagers_field'));
  Finder mafiaField() => find.byKey(const ValueKey('roster_mafia_field'));
  Finder cutoffField() => find.byKey(const ValueKey('daily_cutoff_field'));

  String textAt(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data!;

  testWidgets('starts with fixed defaults: 6 villagers, 2 mafia, 8 players', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: CaseCreationScreen(creator: (id: 'p1', displayName: 'Alice')),
    ));

    expect(tester.widget<TextField>(villagersField()).controller!.text, '6');
    expect(tester.widget<TextField>(mafiaField()).controller!.text, '2');
    expect(textAt(tester, 'expected_roster_total'), '8');
  });

  testWidgets('editing "villagers" updates the derived players total live, leaves mafia alone',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: CaseCreationScreen(creator: (id: 'p1', displayName: 'Alice')),
    ));

    await tester.enterText(villagersField(), '10');
    await tester.pump();

    expect(tester.widget<TextField>(mafiaField()).controller!.text, '2'); // untouched
    expect(textAt(tester, 'expected_roster_total'), '12');
  });

  testWidgets('editing "mafia" updates the derived players total live, leaves villagers alone',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: CaseCreationScreen(creator: (id: 'p1', displayName: 'Alice')),
    ));

    await tester.enterText(mafiaField(), '3');
    await tester.pump();

    expect(tester.widget<TextField>(villagersField()).controller!.text, '6'); // untouched
    expect(textAt(tester, 'expected_roster_total'), '9');
  });

  testWidgets('a zero or blank mafia count floors the players total at villagers + 1, not villagers',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: CaseCreationScreen(creator: (id: 'p1', displayName: 'Alice')),
    ));

    await tester.enterText(villagersField(), '4');
    await tester.pump();
    await tester.enterText(mafiaField(), '0');
    await tester.pump();

    // Mafia floors at 1 (mirroring the repo's own game-start clamp), so
    // the total reflects that floor, not the raw "0" typed in.
    expect(textAt(tester, 'expected_roster_total'), '5');
  });

  testWidgets('the roster caption spells out the live numbers instead of "this many"',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: CaseCreationScreen(creator: (id: 'p1', displayName: 'Alice')),
    ));

    expect(find.textContaining('this many'), findsNothing);
    expect(
      find.textContaining('The case starts the moment 8 players have joined; '
          '2 of them are drawn as mafia at random.'),
      findsOneWidget,
    );

    await tester.enterText(villagersField(), '10');
    await tester.pump();
    await tester.enterText(mafiaField(), '3');
    await tester.pump();

    expect(
      find.textContaining('The case starts the moment 13 players have joined; '
          '3 of them are drawn as mafia at random.'),
      findsOneWidget,
    );
  });

  testWidgets('the removed "villagers per mafia" and "hours to act" fields are gone', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: CaseCreationScreen(creator: (id: 'p1', displayName: 'Alice')),
    ));

    expect(find.textContaining('Villagers per mafia'), findsNothing);
    expect(find.textContaining('Hours to act'), findsNothing);
  });

  testWidgets('the "defaults match the concept doc" blurb is gone', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: CaseCreationScreen(creator: (id: 'p1', displayName: 'Alice')),
    ));

    expect(find.textContaining('Defaults match'), findsNothing);
  });

  testWidgets(
      'creating with the default 6/2 split computes a recruitment threshold '
      'and execution window from that split, not a separate field', (tester) async {
    final repo = LocalGameRepository();
    await tester.pumpWidget(Provider<GameRepository>.value(
      value: repo,
      child: const MaterialApp(
        home: CaseCreationScreen(creator: (id: 'p1', displayName: 'Alice')),
      ),
    ));

    await tester.ensureVisible(find.text('Open the case'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open the case'));
    await tester.pumpAndSettle();

    final games = await repo.watchGames(viewerId: 'p1').first;
    final created = games.single;
    // 6 villagers, 2 mafia -> 2/6 threshold, exactly the case's own
    // starting mafia:villager ratio.
    expect(created.recruitmentUnlockThreshold, closeTo(2 / 6, 0.0001));
    expect(created.executionWindow, const Duration(hours: 1));
    expect(created.minPlayers, 8);
  });

  testWidgets('the computed recruitment threshold tracks an edited villagers/mafia split',
      (tester) async {
    final repo = LocalGameRepository();
    await tester.pumpWidget(Provider<GameRepository>.value(
      value: repo,
      child: const MaterialApp(
        home: CaseCreationScreen(creator: (id: 'p1', displayName: 'Alice')),
      ),
    ));

    await tester.enterText(villagersField(), '8');
    await tester.pump();
    await tester.enterText(mafiaField(), '2');
    await tester.pump();

    await tester.ensureVisible(find.text('Open the case'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open the case'));
    await tester.pumpAndSettle();

    final games = await repo.watchGames(viewerId: 'p1').first;
    final created = games.single;
    // 8 villagers, 2 mafia -> 2/8 = 0.25.
    expect(created.recruitmentUnlockThreshold, closeTo(0.25, 0.0001));
    expect(created.minPlayers, 10);
  });

  testWidgets('the daily cutoff field still works, styled as a boxed data field', (tester) async {
    final repo = LocalGameRepository();
    await tester.pumpWidget(Provider<GameRepository>.value(
      value: repo,
      child: const MaterialApp(
        home: CaseCreationScreen(creator: (id: 'p1', displayName: 'Alice')),
      ),
    ));

    expect(tester.widget<TextField>(cutoffField()).controller!.text, '17:00');

    await tester.enterText(cutoffField(), '09:15');
    await tester.ensureVisible(find.text('Open the case'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open the case'));
    await tester.pumpAndSettle();

    final games = await repo.watchGames(viewerId: 'p1').first;
    expect(games.single.dailyCutoffTime, const Duration(hours: 9, minutes: 15));
  });
}
