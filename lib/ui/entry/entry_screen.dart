import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../design/graphics.dart';
import '../../design/spacing.dart';
import '../../design/typography.dart';
import '../common/dossier_card.dart';
import '../role_switcher/role_switcher_screen.dart';
import 'player_entry_screen.dart';

/// The app's actual first screen: pick between the real player flow
/// (register, find your game, join it) and the one-device tester flow
/// (create/quick-start a game, then jump between every identity in it).
class EntryScreen extends StatelessWidget {
  const EntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Office Game')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Center(
              child: SvgPicture.asset(AppGraphics.appMark, width: 72, height: 72),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('How do you want to play?', style: AppTypography.displayMedium),
            const SizedBox(height: AppSpacing.xl),
            DossierCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Player', style: AppTypography.heading),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Register, find the game you were invited to, and join it — '
                    'the real flow, one identity per device.',
                    style: AppTypography.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PlayerEntryScreen()),
                    ),
                    child: const Text('Continue as a player'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            DossierCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Tester', style: AppTypography.heading),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'One device, several identities — switch between players to test '
                    'the rules before this runs on separate phones.',
                    style: AppTypography.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RoleSwitcherScreen()),
                    ),
                    child: const Text('Continue as tester'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
