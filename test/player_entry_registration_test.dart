import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/data/local/local_auth_service.dart';
import 'package:office_game_app/data/local/local_game_repository.dart';
import 'package:office_game_app/domain/repositories/auth_service.dart';
import 'package:office_game_app/domain/repositories/game_repository.dart';
import 'package:office_game_app/ui/entry/player_entry_screen.dart';
import 'package:provider/provider.dart';

Future<void> _pumpRegistration(WidgetTester tester, AuthService auth) async {
  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<GameRepository>.value(value: LocalGameRepository()),
      Provider<AuthService>.value(value: auth),
    ],
    child: const MaterialApp(home: PlayerEntryScreen()),
  ));
  await tester.pump();
}

void main() {
  testWidgets('Continue does nothing until name, country, city, and company are all filled',
      (tester) async {
    final auth = LocalAuthService();
    await _pumpRegistration(tester, auth);

    final fields = find.byType(TextField);
    // Only the name filled in — still on the registration form.
    await tester.enterText(fields.at(0), 'Alice');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('Who are you?'), findsOneWidget);

    await tester.enterText(fields.at(1), 'Poland');
    await tester.enterText(fields.at(2), 'Warsaw');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('Who are you?'), findsOneWidget);

    // All 4 filled — now it proceeds.
    await tester.enterText(fields.at(3), 'Acme Corp');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Who are you?'), findsNothing);
    expect(find.text('Find your case'), findsOneWidget);
  });

  testWidgets('typing into the company field suggests a previously-registered value',
      (tester) async {
    final auth = LocalAuthService();
    // Seeds the shared suggestion directory the same way an earlier
    // registration would have, then signs out — otherwise this same
    // session would resume as "Someone else" instead of showing a fresh
    // registration form at all.
    await auth.signInWithDisplayName(
      'Someone else',
      country: 'Poland',
      city: 'Warsaw',
      companyOrOffice: 'Acme Corp',
    );
    await auth.signOut();

    await _pumpRegistration(tester, auth);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(3), 'acm');
    // The suggestion fetch is debounced (300ms).
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Acme Corp'), findsOneWidget);
  });
}
