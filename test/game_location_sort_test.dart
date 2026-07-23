import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/data/local/local_auth_service.dart';
import 'package:office_game_app/data/local/local_game_repository.dart';
import 'package:office_game_app/domain/repositories/auth_service.dart';
import 'package:office_game_app/domain/repositories/game_repository.dart';
import 'package:office_game_app/ui/entry/player_entry_screen.dart';
import 'package:provider/provider.dart';

void main() {
  group('LocalGameRepository creator location fields', () {
    test('persist when passed to createGame', () async {
      final repo = LocalGameRepository();
      final game = await repo.createGame(
        locationTag: 'Test Office',
        minPlayers: 4,
        creatorId: 'p1',
        creatorName: 'Alice',
        creatorCountry: 'Poland',
        creatorCity: 'Warsaw',
        creatorCompanyOrOffice: 'Acme Corp',
      );

      expect(game.creatorCountry, 'Poland');
      expect(game.creatorCity, 'Warsaw');
      expect(game.creatorCompanyOrOffice, 'Acme Corp');
    });

    test('default to blank when omitted — a legitimate no-match, not an error', () async {
      final repo = LocalGameRepository();
      final game = await repo.createGame(
        locationTag: 'Test Office 2',
        minPlayers: 4,
        creatorId: 'p1',
        creatorName: 'Alice',
      );

      expect(game.creatorCountry, '');
      expect(game.creatorCity, '');
      expect(game.creatorCompanyOrOffice, '');
    });
  });

  group('PlayerEntryScreen "Find your case" location-tiered sort', () {
    Future<void> pumpSignedIn(
      WidgetTester tester,
      LocalGameRepository repo,
      LocalAuthService auth, {
      required String country,
      required String city,
      required String companyOrOffice,
    }) async {
      // The case-list screen's static hint banner adds enough height to
      // push later tiles below the default 800x600 test viewport — a
      // taller one avoids needing to script scrolling by hand.
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await auth.signInWithDisplayName(
        'Viewer',
        country: country,
        city: city,
        companyOrOffice: companyOrOffice,
      );
      await tester.pumpWidget(MultiProvider(
        providers: [
          Provider<GameRepository>.value(value: repo),
          Provider<AuthService>.value(value: auth),
        ],
        child: const MaterialApp(home: PlayerEntryScreen()),
      ));
      await tester.pump();
      await tester.pump();
    }

    testWidgets(
        'a case at the viewer\'s own company ranks above one only sharing a city, which '
        'ranks above one sharing nothing', (tester) async {
      final repo = LocalGameRepository();
      final auth = LocalAuthService();

      // Oldest first, so without location-tiering "newest first" (today's
      // default sort) would list them in exactly the opposite order.
      await repo.createGame(
        locationTag: 'No Match Case',
        minPlayers: 4,
        creatorId: 'creator1',
        creatorName: 'Creator1',
        creatorCountry: 'France',
        creatorCity: 'Paris',
        creatorCompanyOrOffice: 'Globex',
      );
      await repo.createGame(
        locationTag: 'Same City Case',
        minPlayers: 4,
        creatorId: 'creator2',
        creatorName: 'Creator2',
        creatorCountry: 'Poland',
        creatorCity: 'Warsaw',
        creatorCompanyOrOffice: 'Initech',
      );
      await repo.createGame(
        locationTag: 'Same Company Case',
        minPlayers: 4,
        creatorId: 'creator3',
        creatorName: 'Creator3',
        creatorCountry: 'Poland',
        creatorCity: 'Warsaw',
        creatorCompanyOrOffice: 'Acme Corp',
      );

      await pumpSignedIn(tester, repo, auth,
          country: 'Poland', city: 'Warsaw', companyOrOffice: 'Acme Corp');

      final tags = tester
          .widgetList<Text>(find.byWidgetPredicate((w) =>
              w is Text &&
              (w.data == 'No Match Case' ||
                  w.data == 'Same City Case' ||
                  w.data == 'Same Company Case')))
          .map((t) => t.data)
          .toList();

      expect(tags, ['Same Company Case', 'Same City Case', 'No Match Case']);
      expect(find.text('Your company'), findsOneWidget);
      expect(find.text('Your city'), findsOneWidget);
    });
  });
}
