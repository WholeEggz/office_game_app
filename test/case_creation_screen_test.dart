import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/data/local/local_auth_service.dart';
import 'package:office_game_app/data/local/local_game_repository.dart';
import 'package:office_game_app/domain/repositories/auth_service.dart';
import 'package:office_game_app/domain/repositories/game_repository.dart';
import 'package:office_game_app/ui/entry/case_creation_screen.dart';
import 'package:provider/provider.dart';

// The screen's static hint banner needs an AuthService in the tree just to
// render (it checks whether the hint was already dismissed) — every pump
// goes through this helper so none of the tests below have to know that.
Future<void> _pumpCaseCreation(WidgetTester tester, {GameRepository? repo}) async {
  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<GameRepository>.value(value: repo ?? LocalGameRepository()),
      Provider<AuthService>.value(value: LocalAuthService()),
    ],
    child: const MaterialApp(
      home: CaseCreationScreen(creator: (id: 'p1', displayName: 'Alice')),
    ),
  ));
  // One frame for the hint banner's own async dismissed-state check to
  // resolve before assertions run.
  await tester.pump();
}

void main() {
  Finder villagersField() => find.byKey(const ValueKey('roster_villagers_field'));
  Finder mafiaField() => find.byKey(const ValueKey('roster_mafia_field'));
  Finder cutoffField() => find.byKey(const ValueKey('daily_cutoff_field'));
  Finder rulesField() => find.byKey(const ValueKey('case_rules_field'));

  String textAt(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data!;

  testWidgets('starts with fixed defaults: 6 villagers, 2 mafia, 8 players', (tester) async {
    await _pumpCaseCreation(tester);

    expect(tester.widget<TextField>(villagersField()).controller!.text, '6');
    expect(tester.widget<TextField>(mafiaField()).controller!.text, '2');
    expect(textAt(tester, 'expected_roster_total'), '8');
  });

  testWidgets('editing "villagers" updates the derived players total live, leaves mafia alone',
      (tester) async {
    await _pumpCaseCreation(tester);

    await tester.enterText(villagersField(), '10');
    await tester.pump();

    expect(tester.widget<TextField>(mafiaField()).controller!.text, '2'); // untouched
    expect(textAt(tester, 'expected_roster_total'), '12');
  });

  testWidgets('editing "mafia" updates the derived players total live, leaves villagers alone',
      (tester) async {
    await _pumpCaseCreation(tester);

    await tester.enterText(mafiaField(), '3');
    await tester.pump();

    expect(tester.widget<TextField>(villagersField()).controller!.text, '6'); // untouched
    expect(textAt(tester, 'expected_roster_total'), '9');
  });

  testWidgets('a zero or blank mafia count floors the players total at villagers + 1, not villagers',
      (tester) async {
    await _pumpCaseCreation(tester);

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
    await _pumpCaseCreation(tester);

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
    await _pumpCaseCreation(tester);

    expect(find.textContaining('Villagers per mafia'), findsNothing);
    expect(find.textContaining('Hours to act'), findsNothing);
  });

  testWidgets('the "defaults match the concept doc" blurb is gone', (tester) async {
    await _pumpCaseCreation(tester);

    expect(find.textContaining('Defaults match'), findsNothing);
  });

  testWidgets(
      'creating with the default 6/2 split computes a recruitment threshold '
      'and execution window from that split, not a separate field', (tester) async {
    final repo = LocalGameRepository();
    await _pumpCaseCreation(tester, repo: repo);

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
    await _pumpCaseCreation(tester, repo: repo);

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
    await _pumpCaseCreation(tester, repo: repo);

    expect(tester.widget<TextField>(cutoffField()).controller!.text, '17:00');

    await tester.enterText(cutoffField(), '09:15');
    await tester.ensureVisible(find.text('Open the case'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open the case'));
    await tester.pumpAndSettle();

    final games = await repo.watchGames(viewerId: 'p1').first;
    expect(games.single.dailyCutoffTime, const Duration(hours: 9, minutes: 15));
  });

  testWidgets('typing non-numeric text into villagers/mafia shows a warning but still lets '
      'the case open, falling back the same way it always did', (tester) async {
    final repo = LocalGameRepository();
    await _pumpCaseCreation(tester, repo: repo);

    expect(find.text('Enter a number'), findsNothing);

    await tester.enterText(villagersField(), 'abc');
    await tester.pump();
    expect(find.text('Enter a number'), findsOneWidget);

    await tester.enterText(mafiaField(), 'xyz');
    await tester.pump();
    expect(find.text('Enter a number'), findsNWidgets(2));

    await tester.ensureVisible(find.text('Open the case'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open the case'));
    await tester.pumpAndSettle();

    // Still opens — the warning is visible, but nothing is blocked.
    final games = await repo.watchGames(viewerId: 'p1').first;
    expect(games, hasLength(1));
  });

  testWidgets('clearing an invalid villagers/mafia value makes the warning go away',
      (tester) async {
    await _pumpCaseCreation(tester);

    await tester.enterText(villagersField(), 'nope');
    await tester.pump();
    expect(find.text('Enter a number'), findsOneWidget);

    await tester.enterText(villagersField(), '7');
    await tester.pump();
    expect(find.text('Enter a number'), findsNothing);
  });

  testWidgets('an unparseable daily cutoff shows a warning but still creates the case with '
      'the 17:00 fallback', (tester) async {
    final repo = LocalGameRepository();
    await _pumpCaseCreation(tester, repo: repo);

    expect(find.textContaining('Use HH:mm'), findsNothing);

    await tester.enterText(cutoffField(), 'banana');
    await tester.pump();
    expect(find.textContaining('Use HH:mm'), findsOneWidget);

    await tester.ensureVisible(find.text('Open the case'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open the case'));
    await tester.pumpAndSettle();

    final games = await repo.watchGames(viewerId: 'p1').first;
    expect(games.single.dailyCutoffTime, const Duration(hours: 17));
  });

  testWidgets('an out-of-range daily cutoff (e.g. 25:99) is treated as invalid too',
      (tester) async {
    await _pumpCaseCreation(tester);

    await tester.enterText(cutoffField(), '25:99');
    await tester.pump();
    expect(find.textContaining('Use HH:mm'), findsOneWidget);
  });

  testWidgets('the case rules field starts blank with an example hint, and is optional',
      (tester) async {
    final repo = LocalGameRepository();
    await _pumpCaseCreation(tester, repo: repo);

    expect(tester.widget<TextField>(rulesField()).controller!.text, isEmpty);
    expect(find.textContaining('e.g. players use real names'), findsOneWidget);

    // Blank is fine — creating the case doesn't require typing anything.
    await tester.ensureVisible(find.text('Open the case'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open the case'));
    await tester.pumpAndSettle();

    final games = await repo.watchGames(viewerId: 'p1').first;
    expect(games.single.rulesDescription, isEmpty);
  });

  testWidgets('typed case rules text is passed through to the created case', (tester) async {
    final repo = LocalGameRepository();
    await _pumpCaseCreation(tester, repo: repo);

    await tester.enterText(rulesField(), 'Identities are anonymous — figure it out yourself.');
    await tester.ensureVisible(find.text('Open the case'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open the case'));
    await tester.pumpAndSettle();

    final games = await repo.watchGames(viewerId: 'p1').first;
    expect(
      games.single.rulesDescription,
      'Identities are anonymous — figure it out yourself.',
    );
  });
}
