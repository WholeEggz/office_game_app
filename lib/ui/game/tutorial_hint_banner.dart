import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../design/colors.dart';
import '../../design/spacing.dart';
import '../../design/typography.dart';
import '../../domain/hints/hint_catalog.dart';
import '../../domain/hints/hint_context.dart';
import '../../domain/hints/hint_definition.dart';
import '../../domain/hints/hint_engine.dart';
import '../../domain/models/game.dart';
import '../../domain/models/mafia_thread_entry.dart';
import '../../domain/models/observation.dart';
import '../../domain/models/player.dart';
import '../../domain/models/vote.dart';
import '../../domain/repositories/game_repository.dart';
import 'hint_progress_screen.dart';

/// Dismisses [hintId], surfacing any failure (e.g. a rejected write) as a
/// SnackBar instead of letting it fail silently — without this, a denied
/// write would look identical to a successful one until the hint
/// reappeared on some later rebuild, which is exactly the confusing
/// symptom this is meant to prevent.
Future<void> _dismiss(
  BuildContext context,
  GameRepository repo,
  String gameId,
  String selfId,
  String hintId,
) async {
  try {
    await repo.dismissHint(gameId: gameId, viewerId: selfId, hintId: hintId);
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Couldn't dismiss that — try again.")),
    );
  }
}

/// The top-of-screen tutorial nudge: whichever [hintCatalog] entry is
/// currently the single highest-priority active hint for this player, or
/// nothing at all once every hint that applies to them is done. Nests one
/// `StreamBuilder` per input stream (same convention as `_ObservationSection`
/// in `game_screen.dart`) to assemble one [HintContext] snapshot.
class TutorialHintBanner extends StatelessWidget {
  final String gameId;
  final Game game;
  final Player self;
  final Stream<List<Observation>> observationsStream;
  final Stream<List<Vote>> votesStream;
  final Stream<List<Vote>> voteHistoryStream;
  final Stream<List<MafiaThreadEntry>> mafiaThreadStream;
  final Stream<Set<String>> dismissedHintIdsStream;

  const TutorialHintBanner({
    super.key,
    required this.gameId,
    required this.game,
    required this.self,
    required this.observationsStream,
    required this.votesStream,
    required this.voteHistoryStream,
    required this.mafiaThreadStream,
    required this.dismissedHintIdsStream,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Observation>>(
      stream: observationsStream,
      builder: (context, obsSnap) => StreamBuilder<List<Vote>>(
        stream: votesStream,
        builder: (context, votesSnap) => StreamBuilder<List<Vote>>(
          stream: voteHistoryStream,
          builder: (context, historySnap) => StreamBuilder<List<MafiaThreadEntry>>(
            stream: mafiaThreadStream,
            builder: (context, threadSnap) => StreamBuilder<Set<String>>(
              stream: dismissedHintIdsStream,
              builder: (context, dismissedSnap) {
                final hintContext = HintContext(
                  game: game,
                  self: self,
                  observations: obsSnap.data ?? const [],
                  currentRoundVotes: votesSnap.data ?? const [],
                  voteHistory: historySnap.data ?? const [],
                  mafiaThread: threadSnap.data ?? const [],
                  dismissedHintIds: dismissedSnap.data ?? const {},
                );
                final hint = topBannerHint(hintCatalog, hintContext);
                if (hint == null) return const SizedBox.shrink();
                return _HintBannerCard(
                  gameId: gameId,
                  selfId: self.id,
                  hint: hint,
                  message: hint.message(hintContext),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _HintBannerCard extends StatelessWidget {
  final String gameId;
  final String selfId;
  final HintDefinition hint;
  final String message;

  const _HintBannerCard({
    required this.gameId,
    required this.selfId,
    required this.hint,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => HintProgressScreen(gameId: gameId, playerId: selfId),
          ),
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.sageSoft,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.sage, width: 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(PhosphorIconsLight.lightbulb, color: AppColors.sageText, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(message, style: AppTypography.body.copyWith(color: AppColors.sageText)),
              ),
              if (hint.dismissible) ...[
                const SizedBox(width: AppSpacing.sm),
                IconButton(
                  icon: Icon(PhosphorIconsLight.x, size: 16, color: AppColors.sageText),
                  tooltip: 'Dismiss',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () =>
                      _dismiss(context, context.read<GameRepository>(), gameId, selfId, hint.id),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
