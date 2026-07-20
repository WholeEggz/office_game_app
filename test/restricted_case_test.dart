import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/data/local/local_auth_service.dart';
import 'package:office_game_app/data/local/local_game_repository.dart';
import 'package:office_game_app/domain/repositories/auth_service.dart';
import 'package:office_game_app/domain/repositories/game_repository.dart';
import 'package:office_game_app/ui/entry/case_creation_screen.dart';
import 'package:office_game_app/ui/entry/player_entry_screen.dart';
import 'package:office_game_app/ui/game/game_screen.dart';
import 'package:provider/provider.dart';

void main() {
  group('LocalGameRepository', () {
    test('createGame requires exactly 3 distinct passphrase words when restricted', () async {
      final repo = LocalGameRepository();
      await expectLater(
        repo.createGame(
          locationTag: 'Too Few',
          minPlayers: 4,
          creatorId: 'p1',
          creatorName: 'Alice',
          isRestricted: true,
          passphraseWords: ['tiger', 'blue'],
        ),
        throwsStateError,
      );
      await expectLater(
        repo.createGame(
          locationTag: 'Duplicate Words',
          minPlayers: 4,
          creatorId: 'p1',
          creatorName: 'Alice',
          isRestricted: true,
          passphraseWords: ['tiger', 'Tiger', 'blue'],
        ),
        throwsStateError,
      );

      final game = await repo.createGame(
        locationTag: 'Just Right',
        minPlayers: 4,
        creatorId: 'p1',
        creatorName: 'Alice',
        isRestricted: true,
        passphraseWords: ['tiger', 'blue', 'moon'],
      );
      expect(game.isRestricted, isTrue);
    });

    test('addPlayer rejects a wrong or missing passphrase, accepts the right one '
        'case/whitespace-insensitively and in any order', () async {
      final repo = LocalGameRepository();
      final game = await repo.createGame(
        locationTag: 'Restricted Case',
        minPlayers: 4,
        creatorId: 'creator',
        creatorName: 'Creator',
        isRestricted: true,
        passphraseWords: ['tiger', 'blue', 'moon'],
      );

      await expectLater(
        repo.addPlayer(gameId: game.id, playerId: 'p2', name: 'Bob'),
        throwsStateError,
      );
      await expectLater(
        repo.addPlayer(
          gameId: game.id,
          playerId: 'p2',
          name: 'Bob',
          passphraseWords: ['tiger', 'blue', 'sun'],
        ),
        throwsStateError,
      );

      final player = await repo.addPlayer(
        gameId: game.id,
        playerId: 'p2',
        name: 'Bob',
        // Different order, mixed case, stray whitespace — none of it matters.
        passphraseWords: [' MOON', 'Tiger ', 'blue'],
      );
      expect(player.name, 'Bob');
    });

    test('verifyPassphrase matches without joining, and is always true for an '
        'unrestricted case', () async {
      final repo = LocalGameRepository();
      final restricted = await repo.createGame(
        locationTag: 'Restricted Case',
        minPlayers: 4,
        creatorId: 'creator',
        creatorName: 'Creator',
        isRestricted: true,
        passphraseWords: ['tiger', 'blue', 'moon'],
      );
      expect(
        await repo.verifyPassphrase(gameId: restricted.id, words: ['blue', 'moon', 'tiger']),
        isTrue,
      );
      expect(
        await repo.verifyPassphrase(gameId: restricted.id, words: ['wrong', 'words', 'here']),
        isFalse,
      );
      // Verifying never joins anyone.
      final stillJustCreator = await repo.watchGame(restricted.id).first;
      expect(stillJustCreator.players, hasLength(1));

      final open = await repo.createGame(
        locationTag: 'Open Case',
        minPlayers: 4,
        creatorId: 'creator2',
        creatorName: 'Creator2',
      );
      expect(await repo.verifyPassphrase(gameId: open.id, words: []), isTrue);
    });

    test('fetchGamePassphrase only returns the words to the case\'s own creator', () async {
      final repo = LocalGameRepository();
      final restricted = await repo.createGame(
        locationTag: 'Restricted Case',
        minPlayers: 4,
        creatorId: 'creator',
        creatorName: 'Creator',
        isRestricted: true,
        passphraseWords: ['tiger', 'blue', 'moon'],
      );
      expect(restricted.creatorId, 'creator');

      final creatorWords =
          await repo.fetchGamePassphrase(gameId: restricted.id, playerId: 'creator');
      expect(creatorWords, unorderedEquals(['tiger', 'blue', 'moon']));

      final otherWords =
          await repo.fetchGamePassphrase(gameId: restricted.id, playerId: 'someone-else');
      expect(otherWords, isNull);

      final open = await repo.createGame(
        locationTag: 'Open Case',
        minPlayers: 4,
        creatorId: 'creator2',
        creatorName: 'Creator2',
      );
      expect(
        await repo.fetchGamePassphrase(gameId: open.id, playerId: 'creator2'),
        isNull,
      );
    });
  });

  group('CaseCreationScreen', () {
    testWidgets('checking "Restricted case" creates a restricted game and reveals its '
        'passphrase before proceeding', (tester) async {
      final repo = LocalGameRepository();
      await tester.pumpWidget(Provider<GameRepository>.value(
        value: repo,
        child: const MaterialApp(
          home: CaseCreationScreen(creator: (id: 'p1', displayName: 'Alice')),
        ),
      ));

      await tester.ensureVisible(find.byKey(const ValueKey('restricted_case_checkbox')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('restricted_case_checkbox')));
      await tester.pump();
      await tester.ensureVisible(find.text('Open the case'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open the case'));
      await tester.pumpAndSettle();

      // The reveal dialog blocks navigation until dismissed.
      expect(find.text('Share this passphrase'), findsOneWidget);
      expect(find.byType(CaseCreationScreen), findsOneWidget);

      final games = await repo.watchGames(viewerId: 'p1').first;
      final created = games.single;
      expect(created.isRestricted, isTrue);

      await tester.tap(find.text("I've shared it"));
      await tester.pumpAndSettle();
      expect(find.byType(CaseCreationScreen), findsNothing);
    });

    testWidgets('leaving "Restricted case" unchecked creates a normal, unrestricted game',
        (tester) async {
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

      expect(find.text('Share this passphrase'), findsNothing);
      final games = await repo.watchGames(viewerId: 'p1').first;
      expect(games.single.isRestricted, isFalse);
    });
  });

  group('PlayerEntryScreen', () {
    Future<void> signIn(WidgetTester tester, LocalGameRepository repo, LocalAuthService auth) async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          Provider<GameRepository>.value(value: repo),
          Provider<AuthService>.value(value: auth),
        ],
        child: const MaterialApp(home: PlayerEntryScreen()),
      ));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Bob');
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('a restricted case is badged in the list, and wrong words are rejected',
        (tester) async {
      final repo = LocalGameRepository();
      await repo.createGame(
        locationTag: 'Secret Floor',
        minPlayers: 4,
        creatorId: 'creator',
        creatorName: 'Creator',
        isRestricted: true,
        passphraseWords: ['tiger', 'blue', 'moon'],
      );
      final auth = LocalAuthService();
      await signIn(tester, repo, auth);

      expect(find.textContaining('players · Restricted'), findsOneWidget);

      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(find.text('"Secret Floor" is restricted'), findsOneWidget);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'wrong');
      await tester.enterText(fields.at(1), 'words');
      await tester.enterText(fields.at(2), 'here');
      await tester.tap(find.text('Unlock').last);
      await tester.pumpAndSettle();

      expect(find.text('Incorrect passphrase.'), findsOneWidget);
      // Still on the case list — never got to details.
      expect(find.text('Case rules'), findsNothing);
    });

    testWidgets('the correct words unlock the details screen and let the player join',
        (tester) async {
      final repo = LocalGameRepository();
      await repo.createGame(
        locationTag: 'Secret Floor',
        minPlayers: 4,
        creatorId: 'creator',
        creatorName: 'Creator',
        isRestricted: true,
        passphraseWords: ['tiger', 'blue', 'moon'],
      );
      final auth = LocalAuthService();
      await signIn(tester, repo, auth);

      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      // Order and case shouldn't matter.
      await tester.enterText(fields.at(0), 'MOON');
      await tester.enterText(fields.at(1), 'Tiger');
      await tester.enterText(fields.at(2), 'blue');
      await tester.tap(find.text('Unlock').last);
      await tester.pumpAndSettle();

      expect(find.text('Case rules'), findsOneWidget);
      await tester.tap(find.text('Join this case'));
      await tester.pumpAndSettle();

      final user = auth.currentUser!;
      final game = (await repo.watchGames(viewerId: user.id).first).single;
      expect(game.players.map((p) => p.id), contains(user.id));
    });
  });

  group('GameScreen admin display', () {
    testWidgets(
        'the creator sees an Admin label and the case pass; another player sees neither',
        (tester) async {
      final repo = LocalGameRepository();
      final game = await repo.createGame(
        locationTag: 'Admin Test Floor',
        minPlayers: 4,
        creatorId: 'creator',
        creatorName: 'Creator',
        isRestricted: true,
        passphraseWords: ['tiger', 'blue', 'moon'],
      );
      await repo.addPlayer(
        gameId: game.id,
        playerId: 'p2',
        name: 'Bob',
        passphraseWords: ['tiger', 'blue', 'moon'],
      );

      await tester.pumpWidget(Provider<GameRepository>.value(
        value: repo,
        child: MaterialApp(home: GameScreen(gameId: game.id, playerId: 'creator')),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.textContaining('· Admin'), findsOneWidget);
      expect(find.text('Share with a new joiner: tiger · blue · moon'), findsOneWidget);
    });

    testWidgets('a non-creator player sees neither the Admin label nor the case pass',
        (tester) async {
      final repo = LocalGameRepository();
      final game = await repo.createGame(
        locationTag: 'Admin Test Floor 2',
        minPlayers: 4,
        creatorId: 'creator',
        creatorName: 'Creator',
        isRestricted: true,
        passphraseWords: ['tiger', 'blue', 'moon'],
      );
      await repo.addPlayer(
        gameId: game.id,
        playerId: 'p2',
        name: 'Bob',
        passphraseWords: ['tiger', 'blue', 'moon'],
      );

      await tester.pumpWidget(Provider<GameRepository>.value(
        value: repo,
        child: MaterialApp(home: GameScreen(gameId: game.id, playerId: 'p2')),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.textContaining('· Admin'), findsNothing);
      expect(find.textContaining('Share with a new joiner'), findsNothing);
    });
  });
}
