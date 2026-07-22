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
import '../../domain/models/vote.dart';
import '../../domain/repositories/game_repository.dart';

/// Placeholder icon per hint id, swappable for hand-drawn art later —
/// callers only need to change this one mapping, everything else keys off
/// [HintDefinition.id].
IconData _iconFor(String hintId) {
  switch (hintId) {
    case 'welcome_help':
      return PhosphorIconsLight.bookOpenText;
    case 'say_hello':
      return PhosphorIconsLight.handWaving;
    case 'notice_something':
      return PhosphorIconsLight.eye;
    case 'cast_first_vote':
      return PhosphorIconsLight.checkSquare;
    case 'vote_before_cutoff':
      return PhosphorIconsLight.clockCountdown;
    case 'mafia_thread_intro':
      return PhosphorIconsLight.chatsCircle;
    case 'elimination_ack_pending':
      return PhosphorIconsLight.warning;
    case 'recruitment_response_pending':
      return PhosphorIconsLight.envelopeOpen;
    default:
      return PhosphorIconsLight.info;
  }
}

String _statusLabel(HintStatus status) {
  switch (status) {
    case HintStatus.completed:
      return 'Completed';
    case HintStatus.active:
      return 'Pending';
    case HintStatus.notYetRelevant:
      return 'Not started';
  }
}

Color _statusColor(HintStatus status) {
  switch (status) {
    case HintStatus.completed:
      return AppColors.brass;
    case HintStatus.active:
      return AppColors.sageText;
    case HintStatus.notYetRelevant:
      return AppColors.textMuted;
  }
}

/// The full tutorial progress list — every [hintCatalog] entry that applies
/// to this player, with its current status. Opened from the tutorial
/// banner, or any time a player wants to check how far along they are.
class HintProgressScreen extends StatefulWidget {
  final String gameId;
  final String playerId;

  const HintProgressScreen({super.key, required this.gameId, required this.playerId});

  @override
  State<HintProgressScreen> createState() => _HintProgressScreenState();
}

class _HintProgressScreenState extends State<HintProgressScreen> {
  late final Stream<Game> _gameStream;
  late final Stream<List<Observation>> _observationsStream;
  late final Stream<List<Vote>> _votesStream;
  late final Stream<List<Vote>> _voteHistoryStream;
  late final Stream<List<MafiaThreadEntry>> _mafiaThreadStream;
  late final Stream<Set<String>> _dismissedHintIdsStream;

  @override
  void initState() {
    super.initState();
    final repo = context.read<GameRepository>();
    _gameStream = repo.watchGame(widget.gameId).asBroadcastStream();
    _observationsStream = repo
        .watchObservations(gameId: widget.gameId, viewerId: widget.playerId)
        .asBroadcastStream();
    _votesStream = repo.watchCurrentRoundVotes(widget.gameId).asBroadcastStream();
    _voteHistoryStream = repo.watchVoteHistory(widget.gameId).asBroadcastStream();
    _mafiaThreadStream = repo
        .watchMafiaThread(gameId: widget.gameId, viewerId: widget.playerId)
        .asBroadcastStream();
    _dismissedHintIdsStream = repo
        .watchDismissedHintIds(gameId: widget.gameId, viewerId: widget.playerId)
        .asBroadcastStream();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Getting started')),
      body: StreamBuilder<Game>(
        stream: _gameStream,
        builder: (context, gameSnap) {
          final game = gameSnap.data;
          if (game == null) {
            return const Center(child: CircularProgressIndicator(color: AppColors.brass));
          }
          final self = game.playerById(widget.playerId);
          if (self == null) return const SizedBox.shrink();
          return StreamBuilder<List<Observation>>(
            stream: _observationsStream,
            builder: (context, obsSnap) => StreamBuilder<List<Vote>>(
              stream: _votesStream,
              builder: (context, votesSnap) => StreamBuilder<List<Vote>>(
                stream: _voteHistoryStream,
                builder: (context, historySnap) => StreamBuilder<List<MafiaThreadEntry>>(
                  stream: _mafiaThreadStream,
                  builder: (context, threadSnap) => StreamBuilder<Set<String>>(
                    stream: _dismissedHintIdsStream,
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
                      final entries = allHintStatuses(hintCatalog, hintContext)
                          .where((e) => e.$1.appliesTo(hintContext))
                          .toList();
                      return ListView.separated(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        itemCount: entries.length,
                        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          final (hint, status) = entries[index];
                          return _HintTile(
                            hint: hint,
                            status: status,
                            message: hint.message(hintContext),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HintTile extends StatelessWidget {
  final HintDefinition hint;
  final HintStatus status;
  final String message;

  const _HintTile({required this.hint, required this.status, required this.message});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.borderHairline, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_iconFor(hint.id), size: 22, color: color),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message, style: AppTypography.bodySmall.copyWith(color: color)),
                const SizedBox(height: AppSpacing.xs),
                Text(_statusLabel(status), style: AppTypography.dataSmall.copyWith(color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
