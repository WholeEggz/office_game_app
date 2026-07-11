import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/local/local_auth_service.dart';
import 'data/local/local_game_repository.dart';
import 'design/theme.dart';
import 'domain/repositories/auth_service.dart';
import 'domain/repositories/game_repository.dart';
import 'firebase_options.dart';
import 'ui/entry/entry_screen.dart';

/// Firebase backend integration is being built behind the local
/// implementations (see implementation_plan.md, Phase 1b). Until the DI
/// seam swaps over, this just proves the app boots against the Local
/// Emulator Suite; `LocalGameRepository`/`LocalAuthService` still drive
/// the UI.
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

class OfficeGameApp extends StatelessWidget {
  const OfficeGameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
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
