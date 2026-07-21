import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/data/local/local_auth_service.dart';
import 'package:office_game_app/data/local/local_game_repository.dart';
import 'package:office_game_app/domain/repositories/auth_service.dart';
import 'package:office_game_app/domain/repositories/game_repository.dart';
import 'package:office_game_app/ui/entry/player_entry_screen.dart';
import 'package:office_game_app/ui/entry/welcome_screen.dart';
import 'package:provider/provider.dart';

void main() {
  test('resumeSession is null before any sign-in, and reflects the current user after',
      () async {
    final auth = LocalAuthService();
    expect(await auth.resumeSession(), isNull);

    final user = await auth.signInWithDisplayName(
      'Alice',
      country: 'Poland',
      city: 'Warsaw',
      companyOrOffice: 'Acme Corp',
    );
    expect(await auth.resumeSession(), user);
  });

  test('resumeSession reflects null again after signing out', () async {
    final auth = LocalAuthService();
    await auth.signInWithDisplayName(
      'Alice',
      country: 'Poland',
      city: 'Warsaw',
      companyOrOffice: 'Acme Corp',
    );
    await auth.signOut();
    expect(await auth.resumeSession(), isNull);
  });

  testWidgets(
      'PlayerEntryScreen skips straight to "Find your case" when a session is already '
      'active — the returning signed-in user flow', (tester) async {
    final repo = LocalGameRepository();
    final auth = LocalAuthService();
    // Simulates a returning signed-in user: some earlier launch (or, for
    // the Firebase backend, a still-persisted anonymous session plus its
    // Firestore-backed display name) already resolved this identity
    // before PlayerEntryScreen ever mounts.
    await auth.signInWithDisplayName(
      'Alice',
      country: 'Poland',
      city: 'Warsaw',
      companyOrOffice: 'Acme Corp',
    );

    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<GameRepository>.value(value: repo),
        Provider<AuthService>.value(value: auth),
      ],
      child: const MaterialApp(home: PlayerEntryScreen()),
    ));
    await tester.pump();

    expect(find.text('Who are you?'), findsNothing);
    expect(find.text('Find your case'), findsOneWidget);
    expect(find.text('Signed in as Alice.'), findsOneWidget);
  });

  testWidgets('PlayerEntryScreen shows registration when there is nothing to resume',
      (tester) async {
    final repo = LocalGameRepository();
    final auth = LocalAuthService();

    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<GameRepository>.value(value: repo),
        Provider<AuthService>.value(value: auth),
      ],
      child: const MaterialApp(home: PlayerEntryScreen()),
    ));
    await tester.pump();

    expect(find.text('Who are you?'), findsOneWidget);
    expect(find.text('Find your case'), findsNothing);
  });

  testWidgets(
      'the debug "Sign out" button signs out and resets to the very first screen '
      '(WelcomeScreen)', (tester) async {
    final repo = LocalGameRepository();
    final auth = LocalAuthService();
    await auth.signInWithDisplayName(
      'Alice',
      country: 'Poland',
      city: 'Warsaw',
      companyOrOffice: 'Acme Corp',
    );

    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<GameRepository>.value(value: repo),
        Provider<AuthService>.value(value: auth),
      ],
      child: const MaterialApp(home: PlayerEntryScreen()),
    ));
    await tester.pump();
    expect(find.text('Find your case'), findsOneWidget);

    await tester.tap(find.byTooltip('Sign out (debug)'));
    await tester.pumpAndSettle();

    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(await auth.resumeSession(), isNull);
  });
}
