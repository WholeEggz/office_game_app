import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/data/local/local_auth_service.dart';
import 'package:office_game_app/data/local/local_game_repository.dart';
import 'package:office_game_app/domain/repositories/auth_service.dart';
import 'package:office_game_app/domain/repositories/game_repository.dart';
import 'package:office_game_app/ui/game/hint_progress_screen.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
      'the debug "Reset all hint statuses" button un-dismisses both the '
      'in-game and pre-game hint ledgers', (tester) async {
    final repo = LocalGameRepository();
    final auth = LocalAuthService();

    // Stays below minPlayers (never auto-starts, stays "recruiting") so no
    // daily-cutoff Timer gets scheduled — matches case_details_screen_test
    // .dart's convention for keeping widget tests free of that teardown
    // cleanup. watchVisiblePlayers already returns full player data before
    // a game starts (role defaults to villager pre-draw), which is all
    // this test needs.
    final game = await repo.createGame(
      locationTag: 'test-office',
      minPlayers: 3,
      creatorId: 'p1',
      creatorName: 'Alice',
    );
    await repo.addPlayer(gameId: game.id, playerId: 'p2', name: 'Bob');

    // Dismiss an in-game hint (game-scoped ledger) without actually
    // completing it — this is the "Got it" path, distinct from a real
    // completion signal.
    await repo.dismissHint(gameId: game.id, viewerId: 'p1', hintId: 'say_hello');

    // Dismiss a pre-game hint too (player-scoped ledger, via AuthService).
    await auth.signInWithDisplayName('Alice', country: '', city: '', companyOrOffice: '');
    await auth.dismissHint('case_list_location_sort');

    // The full merged list (4 static + ~6 in-game entries) is taller than
    // the default 800x600 test viewport — `ListView.separated` only builds
    // items actually within the viewport, so both hints this test checks
    // need to be on-screen without scrolling.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<GameRepository>.value(value: repo),
        Provider<AuthService>.value(value: auth),
      ],
      child: MaterialApp(home: HintProgressScreen(gameId: game.id, playerId: 'p1')),
    ));
    await tester.pumpAndSettle();

    // Both hints read as already dismissed/completed before reset.
    expect(
      find.ancestor(
        of: find.textContaining('Say hello'),
        matching: find.byType(Container),
      ),
      findsOneWidget,
    );
    expect(find.text('Completed'), findsWidgets);

    await tester.tap(find.text('Reset all hint statuses (debug)'));
    await tester.pumpAndSettle();

    expect(find.textContaining("Couldn't reset hints"), findsNothing);

    // "Say hello" (never actually said) is Pending again, and so is the
    // pre-game "Cases near your office..." hint — both dismissals were
    // cleared, not just one of the two ledgers.
    final sayHelloTile = find.ancestor(
      of: find.textContaining('Say hello'),
      matching: find.byType(Container),
    );
    expect(find.descendant(of: sayHelloTile, matching: find.text('Pending')), findsOneWidget);

    final locationTile = find.ancestor(
      of: find.textContaining('Cases near your office'),
      matching: find.byType(Container),
    );
    expect(find.descendant(of: locationTile, matching: find.text('Pending')), findsOneWidget);
  });
}
