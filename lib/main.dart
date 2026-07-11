import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/firebase/firebase_auth_service.dart';
import 'data/firebase/firebase_game_repository.dart';
import 'data/local/local_auth_service.dart';
import 'data/local/local_game_repository.dart';
import 'design/theme.dart';
import 'domain/repositories/auth_service.dart';
import 'domain/repositories/game_repository.dart';
import 'firebase_options.dart';
import 'ui/entry/backend_selection_screen.dart';
import 'ui/entry/entry_screen.dart';

/// Firebase backend integration (implementation_plan.md, Phase 1b) is
/// complete as of Milestone 6 — FirebaseGameRepository/FirebaseAuthService
/// implement the full GameRepository/AuthService contract, the same one
/// LocalGameRepository/LocalAuthService implement. Which pair actually
/// backs a given app session is chosen at runtime by
/// BackendSelectionScreen rather than fixed here, so Local (zero backend,
/// fastest for iterating on a new game-logic change) and Firebase (the
/// real target) can both be exercised from the same build.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (kDebugMode) {
    _useFirebaseEmulators();
  }
  runApp(const OfficeGameApp());
}

void _useFirebaseEmulators() {
  // The Android emulator can't resolve the host machine's `localhost`;
  // 10.0.2.2 is its documented alias for it. iOS simulator and web both
  // share the host's network namespace, so `localhost` works directly.
  final host = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? '10.0.2.2'
      : 'localhost';
  FirebaseAuth.instance.useAuthEmulator(host, 9099);
  FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
  FirebaseFunctions.instance.useFunctionsEmulator(host, 5001);
}

class OfficeGameApp extends StatefulWidget {
  const OfficeGameApp({super.key});

  @override
  State<OfficeGameApp> createState() => _OfficeGameAppState();
}

class _OfficeGameAppState extends State<OfficeGameApp> {
  AppBackend? _backend;

  @override
  Widget build(BuildContext context) {
    final backend = _backend;
    // MultiProvider must wrap MaterialApp itself, not just sit inside
    // `home:` — MaterialApp owns the Navigator, and a route pushed via
    // Navigator.push (EntryScreen -> RoleSwitcherScreen, for instance) is
    // a sibling in that Navigator's route stack, not a descendant of
    // whatever `home:` rendered. A provider nested inside `home:` is
    // invisible to every route pushed after it; it has to be an ancestor
    // of the Navigator to reach all of them.
    if (backend == null) {
      return MaterialApp(
        title: 'Office Game',
        debugShowCheckedModeBanner: false,
        theme: buildOfficeGameTheme(),
        home: BackendSelectionScreen(onSelect: (selected) => setState(() => _backend = selected)),
      );
    }
    return MultiProvider(
      providers: backend == AppBackend.firebase
          ? [
              Provider<GameRepository>(create: (_) => FirebaseGameRepository()),
              Provider<AuthService>(create: (_) => FirebaseAuthService()),
            ]
          : [
              Provider<GameRepository>(create: (_) => LocalGameRepository()),
              Provider<AuthService>(create: (_) => LocalAuthService()),
            ],
      child: MaterialApp(
        title: 'Office Game',
        debugShowCheckedModeBanner: false,
        theme: buildOfficeGameTheme(),
        home: const EntryScreen(),
      ),
    );
  }
}
