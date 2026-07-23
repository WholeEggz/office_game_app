import 'dart:async';

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
import '../help/help_screen.dart';

/// Dismisses [dismissKey], surfacing any failure (e.g. a rejected write) as
/// a SnackBar instead of letting it fail silently — without this, a denied
/// write would look identical to a successful one until the hint
/// reappeared on some later rebuild, which is exactly the confusing
/// symptom this is meant to prevent.
Future<void> _dismiss(
  BuildContext context,
  GameRepository repo,
  String gameId,
  String selfId,
  String dismissKey,
) async {
  try {
    await repo.dismissHint(gameId: gameId, viewerId: selfId, hintId: dismissKey);
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Couldn't dismiss that — try again.")),
    );
  }
}

void _performAction(BuildContext context, HintActionTarget target) {
  switch (target) {
    case HintActionTarget.help:
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HelpScreen()));
  }
}

/// The top-of-screen tutorial nudge: whichever [hintCatalog] entry is
/// currently the single highest-priority active hint for this player, or
/// nothing at all once every hint that applies to them is done. Nests one
/// `StreamBuilder` per input stream (same convention as `_ObservationSection`
/// in `game_screen.dart`) to assemble one [HintContext] snapshot each build.
///
/// Owns its own fade + stagger choreography on top of that reactive data:
/// dismissing (or naturally completing) the shown hint fades it out, waits
/// [_gapDuration] with nothing shown, then fades in whatever's next —
/// rather than snapping straight to the next nudge, which read as the app
/// nagging the player rather than just informing them.
class TutorialHintBanner extends StatefulWidget {
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
  State<TutorialHintBanner> createState() => _TutorialHintBannerState();
}

class _TutorialHintBannerState extends State<TutorialHintBanner>
    with SingleTickerProviderStateMixin {
  static const _gapDuration = Duration(milliseconds: 900);

  late final AnimationController _controller;
  HintDefinition? _shownHint;
  String _shownMessage = '';
  Timer? _gapTimer;
  HintContext? _latestContext;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.base);
  }

  @override
  void dispose() {
    _gapTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Reacts to a freshly-assembled [HintContext] — called once per frame
  /// via a post-frame callback (never straight from `build()`, since it
  /// can call `setState`). Idempotent: only actually does anything when
  /// the top banner hint has changed since the last time this ran.
  void _onContext(HintContext ctx) {
    _latestContext = ctx;
    // Mid-transition (faded out, waiting out the gap) — the pending timer
    // itself will pick up _latestContext when it fires, not this call.
    if (_gapTimer != null) return;

    final topHint = topBannerHint(hintCatalog, ctx);

    if (_shownHint == null) {
      if (topHint == null) return;
      setState(() {
        _shownHint = topHint;
        _shownMessage = topHint.message(ctx);
      });
      _controller.forward(from: 0);
      return;
    }

    if (topHint != null && topHint.id == _shownHint!.id) {
      // Same hint still active — just keep its message text current (e.g.
      // a dailyCutoffTime that could theoretically change).
      final freshMessage = topHint.message(ctx);
      if (freshMessage != _shownMessage) setState(() => _shownMessage = freshMessage);
      return;
    }

    // The top hint changed (including to "nothing left") — fade the
    // current one out, then pause before revealing whatever's next.
    _controller.reverse().whenComplete(() {
      if (!mounted) return;
      setState(() => _shownHint = null);
      _gapTimer = Timer(_gapDuration, () {
        _gapTimer = null;
        if (!mounted) return;
        final latest = _latestContext;
        if (latest == null) return;
        final next = topBannerHint(hintCatalog, latest);
        if (next == null) return;
        setState(() {
          _shownHint = next;
          _shownMessage = next.message(latest);
        });
        _controller.forward(from: 0);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Observation>>(
      stream: widget.observationsStream,
      builder: (context, obsSnap) => StreamBuilder<List<Vote>>(
        stream: widget.votesStream,
        builder: (context, votesSnap) => StreamBuilder<List<Vote>>(
          stream: widget.voteHistoryStream,
          builder: (context, historySnap) => StreamBuilder<List<MafiaThreadEntry>>(
            stream: widget.mafiaThreadStream,
            builder: (context, threadSnap) => StreamBuilder<Set<String>>(
              stream: widget.dismissedHintIdsStream,
              builder: (context, dismissedSnap) {
                final hintContext = HintContext(
                  game: widget.game,
                  self: widget.self,
                  observations: obsSnap.data ?? const [],
                  currentRoundVotes: votesSnap.data ?? const [],
                  voteHistory: historySnap.data ?? const [],
                  mafiaThread: threadSnap.data ?? const [],
                  dismissedHintIds: dismissedSnap.data ?? const {},
                );
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _onContext(hintContext);
                });
                final hint = _shownHint;
                if (hint == null) return const SizedBox.shrink();
                return FadeTransition(
                  opacity: _controller,
                  child: _HintBannerCard(
                    gameId: widget.gameId,
                    selfId: widget.self.id,
                    hint: hint,
                    message: _shownMessage,
                    dismissKey: hint.dismissKey(hintContext),
                  ),
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
  final String dismissKey;

  const _HintBannerCard({
    required this.gameId,
    required this.selfId,
    required this.hint,
    required this.message,
    required this.dismissKey,
  });

  @override
  Widget build(BuildContext context) {
    final actionTarget = hint.actionTarget;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.sageSoft,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.sage, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(PhosphorIconsLight.lightbulb, color: AppColors.sageText, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(message, style: AppTypography.body.copyWith(color: AppColors.sageText)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (actionTarget != null)
                TextButton(
                  onPressed: () {
                    _dismiss(context, context.read<GameRepository>(), gameId, selfId, dismissKey);
                    _performAction(context, actionTarget);
                  },
                  child: Text(hint.actionLabel!),
                ),
              TextButton(
                onPressed: () =>
                    _dismiss(context, context.read<GameRepository>(), gameId, selfId, dismissKey),
                child: const Text('Got it'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
