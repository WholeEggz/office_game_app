import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/data/local/local_game_repository.dart';
import 'package:office_game_app/domain/repositories/game_repository.dart';
import 'package:office_game_app/ui/entry/case_creation_screen.dart';
import 'package:provider/provider.dart';

void main() {
  Finder totalField() => find.byKey(const ValueKey('roster_total_field'));
  Finder mafiaField() => find.byKey(const ValueKey('roster_mafia_field'));
  Finder cutoffField() => find.byKey(const ValueKey('daily_cutoff_field'));

  String textAt(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data!;

  testWidgets('starts with fixed defaults: 8 players, 2 mafia, 6 villagers', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: CaseCreationScreen(creator: (id: 'p1', displayName: 'Alice')),
    ));

    expect(tester.widget<TextField>(totalField()).controller!.text, '8');
    expect(tester.widget<TextField>(mafiaField()).controller!.text, '2');
    expect(textAt(tester, 'expected_roster_villagers'), '6');
  });

  testWidgets('editing "players" updates the derived villagers figure live, leaves mafia alone',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: CaseCreationScreen(creator: (id: 'p1', displayName: 'Alice')),
    ));

    await tester.enterText(totalField(), '12');
    await tester.pump();

    expect(tester.widget<TextField>(mafiaField()).controller!.text, '2'); // untouched
    expect(textAt(tester, 'expected_roster_villagers'), '10');
  });

  testWidgets('editing "mafia" updates the derived villagers figure live, leaves players alone',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: CaseCreationScreen(creator: (id: 'p1', displayName: 'Alice')),
    ));

    await tester.enterText(mafiaField(), '3');
    await tester.pump();

    expect(tester.widget<TextField>(totalField()).controller!.text, '8'); // untouched
    expect(textAt(tester, 'expected_roster_villagers'), '5');
  });

  testWidgets('mafia larger than players clamps the villagers preview at 0, not negative',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: CaseCreationScreen(creator: (id: 'p1', displayName: 'Alice')),
    ));

    await tester.enterText(totalField(), '4');
    await tester.pump();
    await tester.enterText(mafiaField(), '99');
    await tester.pump();

    expect(textAt(tester, 'expected_roster_villagers'), '0');
  });

  testWidgets('the removed "villagers per mafia" and "hours to act" fields are gone', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: CaseCreationScreen(creator: (id: 'p1', displayName: 'Alice')),
    ));

    expect(find.textContaining('Villagers per mafia'), findsNothing);
    expect(find.textContaining('Hours to act'), findsNothing);
  });

  testWidgets(
      'creating with the default 8/2 split computes a recruitment threshold '
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
    // 8 players, 2 mafia -> 6 villagers -> 2/6 threshold, exactly the
    // case's own starting mafia:villager ratio.
    expect(created.recruitmentUnlockThreshold, closeTo(2 / 6, 0.0001));
    expect(created.executionWindow, const Duration(hours: 1));
  });

  testWidgets('the computed recruitment threshold tracks an edited mafia/players split',
      (tester) async {
    final repo = LocalGameRepository();
    await tester.pumpWidget(Provider<GameRepository>.value(
      value: repo,
      child: const MaterialApp(
        home: CaseCreationScreen(creator: (id: 'p1', displayName: 'Alice')),
      ),
    ));

    await tester.enterText(totalField(), '10');
    await tester.pump();
    await tester.enterText(mafiaField(), '2');
    await tester.pump();

    await tester.ensureVisible(find.text('Open the case'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open the case'));
    await tester.pumpAndSettle();

    final games = await repo.watchGames(viewerId: 'p1').first;
    final created = games.single;
    // 10 players, 2 mafia -> 8 villagers -> 2/8 = 0.25.
    expect(created.recruitmentUnlockThreshold, closeTo(0.25, 0.0001));
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
