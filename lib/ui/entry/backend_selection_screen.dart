import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../design/graphics.dart';
import '../../design/spacing.dart';
import '../../design/typography.dart';
import '../common/dossier_card.dart';

/// Which `GameRepository`/`AuthService` pair backs an app session.
enum AppBackend { local, firebase }

/// Debug-only, shown before [EntryScreen]: picks [AppBackend] for this app
/// session. Exists so Local (zero backend, fastest for iterating on a new
/// game-logic change) and Firebase (the real target — Firestore + Cloud
/// Functions, needs the Local Emulator Suite or a real project already
/// running) can both be exercised from the same build without hand-editing
/// main.dart. Same spirit as the tester/player choice one screen further
/// in, and gated the same way — gone before a real build reaches a
/// coworker who isn't in on the testing.
class BackendSelectionScreen extends StatelessWidget {
  const BackendSelectionScreen({super.key, required this.onSelect});

  final ValueChanged<AppBackend> onSelect;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Center(
              child: SvgPicture.asset(AppGraphics.appMark, width: 72, height: 72),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Which backend?', style: AppTypography.displayMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Debug-only, gone before a real build. Local never leaves this '
              'device; Firebase needs the emulator (or the real project) already '
              'running.',
              style: AppTypography.bodySmall,
            ),
            const SizedBox(height: AppSpacing.xl),
            DossierCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Local', style: AppTypography.heading),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'In-memory, no backend at all — the fastest way to try out a '
                    'new game-logic change.',
                    style: AppTypography.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ElevatedButton(
                    onPressed: () => onSelect(AppBackend.local),
                    child: const Text('Use local'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            DossierCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Firebase', style: AppTypography.heading),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Firestore + Cloud Functions — the real target this app is '
                    'being built toward.',
                    style: AppTypography.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton(
                    onPressed: () => onSelect(AppBackend.firebase),
                    child: const Text('Use Firebase'),
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
