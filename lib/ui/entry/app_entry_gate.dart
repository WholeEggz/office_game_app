import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/colors.dart';
import '../../domain/repositories/auth_service.dart';
import 'entry_screen.dart';
import 'player_entry_screen.dart';
import 'welcome_screen.dart';

/// Decides what a cold launch actually opens on, once the chosen backend's
/// AuthService is available (see main.dart). Separate from
/// PlayerEntryScreen's own resumeSession() check, which still governs
/// whether *that* screen shows its registration form or the game list —
/// this gate only decides whether WelcomeScreen (a signed-out-only beat)
/// and EntryScreen (a debug-only Player/Tester choice — real builds have
/// no Tester option to choose between) are worth showing at all:
///
///   signed out             -> WelcomeScreen (which itself then leads to
///                              EntryScreen in debug, PlayerEntryScreen
///                              in a real build — see WelcomeScreen._enter)
///   signed in, debug build  -> EntryScreen, unconditionally — the
///                              Player/Tester choice is a dev affordance,
///                              not tied to whether a session exists
///   signed in, real build   -> straight to PlayerEntryScreen, which
///                              resolves instantly to the game list
class AppEntryGate extends StatefulWidget {
  const AppEntryGate({super.key});

  @override
  State<AppEntryGate> createState() => _AppEntryGateState();
}

class _AppEntryGateState extends State<AppEntryGate> {
  bool _checking = true;
  bool _signedIn = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final resumed = await context.read<AuthService>().resumeSession();
    if (!mounted) return;
    setState(() {
      _signedIn = resumed != null;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: AppColors.ink,
        body: Center(child: CircularProgressIndicator(color: AppColors.brass)),
      );
    }
    if (!_signedIn) return const WelcomeScreen();
    return kDebugMode ? const EntryScreen() : const PlayerEntryScreen();
  }
}
