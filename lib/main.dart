import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/local/local_auth_service.dart';
import 'data/local/local_game_repository.dart';
import 'design/theme.dart';
import 'domain/repositories/auth_service.dart';
import 'domain/repositories/game_repository.dart';
import 'ui/entry/entry_screen.dart';

void main() {
  runApp(const OfficeGameApp());
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
