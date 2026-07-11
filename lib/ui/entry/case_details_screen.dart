import 'package:flutter/material.dart';

import '../../design/spacing.dart';
import '../../design/typography.dart';
import '../../domain/models/game.dart';
import '../common/dossier_card.dart';

/// Shown before a prospective player joins a case — the creator's own
/// rules text and who's playing so far. Only reached for a case the
/// viewer hasn't joined yet (`PlayerEntryScreen` keeps the existing
/// direct-`Enter` behavior for cases already joined), so [game] is always
/// the redacted snapshot `GameRepository.watchGames` already produces for
/// a non-member browsing the list — see `LocalGameRepository._visiblePlayers`,
/// which forces every role to villager unless the viewer is already a
/// mafia member of this same game. No new repository call needed here.
class CaseDetailsScreen extends StatelessWidget {
  final Game game;
  final VoidCallback onJoin;

  const CaseDetailsScreen({super.key, required this.game, required this.onJoin});

  @override
  Widget build(BuildContext context) {
    final canJoin = game.status != GameStatus.ended;
    return Scaffold(
      appBar: AppBar(title: Text(game.locationTag)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(game.locationTag, style: AppTypography.displayMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${game.status.name} · round ${game.currentRound} · '
              '${game.players.length}/${game.minPlayers} players',
              style: AppTypography.bodySmall,
            ),
            const SizedBox(height: AppSpacing.xl),
            DossierCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Case rules', style: AppTypography.heading),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    game.rulesDescription.trim().isEmpty
                        ? 'No rules noted for this case.'
                        : game.rulesDescription,
                    style: AppTypography.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            DossierCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Players so far', style: AppTypography.heading),
                  const SizedBox(height: AppSpacing.sm),
                  for (final player in game.players)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                      child: Text(player.name, style: AppTypography.body),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (canJoin)
              ElevatedButton(
                key: const ValueKey('join_this_case_button'),
                onPressed: onJoin,
                child: const Text('Join this case'),
              )
            else
              Text('This case is closed.', style: AppTypography.bodySmall),
          ],
        ),
      ),
    );
  }
}
