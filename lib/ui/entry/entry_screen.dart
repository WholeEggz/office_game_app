import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../design/colors.dart';
import '../../design/graphics.dart';
import '../../design/spacing.dart';
import '../../design/typography.dart';
import '../common/dossier_card.dart';
import '../help/help_screen.dart';
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
      appBar: AppBar(
        title: const Text('Office Game'),
        actions: [
          IconButton(
            icon: Icon(PhosphorIconsLight.bookOpenText, color: AppColors.textSecondary),
            tooltip: 'How to play',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HelpScreen()),
            ),
          ),
        ],
      ),
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
            // Previously shown unconditionally — a real release build
            // would have let any player reach the debug role switcher
            // (mint arbitrary identities, quick-start games, and, in
            // Local backend mode, see everyone's real role with no
            // redaction at all). Gated behind kDebugMode like every
            // other debug-only affordance in this app.
            if (kDebugMode) ...[
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
          ],
        ),
      ),
    );
  }
}
