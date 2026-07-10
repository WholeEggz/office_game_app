import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../design/colors.dart';
import '../../design/spacing.dart';
import '../../design/typography.dart';
import '../../domain/models/game_moment.dart';

enum _MomentTone {
  celebratory,
  drama,

  /// Worth knowing, but not personally earned or personally suffered — a
  /// step brighter than [neutral] (it gets a sound, and a distinct
  /// border), a step quieter than [celebratory]/[drama] (no haptic).
  informational,

  /// The "nothing happened" fallback — no haptic, no sound.
  neutral,
}

typedef _MomentCopy = ({String title, String body, IconData icon, _MomentTone tone});

_MomentCopy _copyFor(GameMomentType type, int round) {
  switch (type) {
    case GameMomentType.correctVoteReward:
      return (
        title: 'Good catch',
        body: 'Round $round: your vote helped unmask an Informant. +1 vote weight.',
        icon: PhosphorIconsLight.medal,
        tone: _MomentTone.celebratory,
      );
    case GameMomentType.recruitmentExecuted:
      return (
        title: 'Recruitment successful',
        body: 'Round $round: your approach worked — the Wire has a new member.',
        icon: PhosphorIconsLight.handshake,
        tone: _MomentTone.celebratory,
      );
    case GameMomentType.finaleWin:
      return (
        title: 'Case closed — your side won',
        body: 'Round $round: the case is over, and you came out on top.',
        icon: PhosphorIconsLight.trophy,
        tone: _MomentTone.celebratory,
      );
    case GameMomentType.recruitedSwitchSides:
      return (
        title: "You've switched sides",
        body: "Round $round: the sign found you, and you took it. "
            "You're an Informant now.",
        icon: PhosphorIconsLight.maskHappy,
        tone: _MomentTone.drama,
      );
    case GameMomentType.finaleLoss:
      return (
        title: 'Case closed — your side lost',
        body: 'Round $round: the case is over. Better luck in the next one.',
        icon: PhosphorIconsLight.doorOpen,
        tone: _MomentTone.drama,
      );
    case GameMomentType.mafiaUnmaskedByOthers:
      return (
        title: 'An Informant was unmasked',
        body: "Round $round: the case advanced — someone else's vote "
            "caught an Informant this round.",
        icon: PhosphorIconsLight.newspaperClipping,
        tone: _MomentTone.informational,
      );
    case GameMomentType.targetedByMafia:
      return (
        title: 'You were marked',
        body: "Round $round: the Wire's signal found you — "
            'you lost 1 vote weight.',
        icon: PhosphorIconsLight.target,
        tone: _MomentTone.drama,
      );
    case GameMomentType.targetedByVillagers:
      return (
        title: 'Voted against',
        body: "Round $round: your fellow villagers' votes landed on you "
            '— you lost 1 vote weight.',
        icon: PhosphorIconsLight.target,
        tone: _MomentTone.drama,
      );
    case GameMomentType.joinedCase:
      return (
        title: 'Welcome to the case',
        body: "Round $round: you're in — good luck out there.",
        icon: PhosphorIconsLight.handWaving,
        tone: _MomentTone.celebratory,
      );
    case GameMomentType.reenteredCase:
      return (
        title: 'Welcome back',
        body: 'Round $round: here\'s where things stand.',
        icon: PhosphorIconsLight.arrowUUpLeft,
        tone: _MomentTone.informational,
      );
    case GameMomentType.roundEnded:
      return (
        title: 'Round $round has ended',
        body: 'Nothing notable to report for you this round.',
        icon: PhosphorIconsLight.clockCounterClockwise,
        tone: _MomentTone.neutral,
      );
  }
}

/// Collapses consecutive [GameMomentType.roundEnded] entries with nothing
/// else to say down to just the most recent one — per-request, every other
/// moment type is specific enough that missing even one would feel like a
/// real gap, but "N quiet rounds passed" only needs saying once.
List<GameMoment> selectMomentsToShow(List<GameMoment> moments) {
  final specific = moments.where((m) => m.type != GameMomentType.roundEnded).toList();
  final roundEndedOnly = moments.where((m) => m.type == GameMomentType.roundEnded).toList();
  if (roundEndedOnly.isEmpty) return specific;
  return [...specific, roundEndedOnly.last];
}

/// Shows [moments] as a sequence of dismiss-to-continue dialogs, one at a
/// time — call [selectMomentsToShow] first if the caller hasn't already.
/// Each dialog is deliberately not barrier-dismissible: a queue you can
/// accidentally tap your way past isn't really a queue.
Future<void> presentMoments(BuildContext context, List<GameMoment> moments) async {
  for (final moment in moments) {
    if (!context.mounted) return;
    await _showMomentDialog(context, moment);
  }
}

Future<void> _showMomentDialog(BuildContext context, GameMoment moment) async {
  final copy = _copyFor(moment.type, moment.round);
  switch (copy.tone) {
    case _MomentTone.celebratory:
      HapticFeedback.lightImpact();
      SystemSound.play(SystemSoundType.click);
    case _MomentTone.drama:
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.click);
    case _MomentTone.informational:
      // A click to mark it as worth noticing, but no haptic — this fires
      // for things like "welcome back" that can happen on every single
      // visit, and a buzz every time would wear thin fast.
      SystemSound.play(SystemSoundType.click);
    case _MomentTone.neutral:
      // Deliberately quiet — this is the "nothing much happened" fallback,
      // not something worth a buzz or a click.
      break;
  }
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _MomentDialogCard(
      copy: copy,
      onDismiss: () => Navigator.of(context).pop(),
    ),
  );
}

class _MomentDialogCard extends StatelessWidget {
  final _MomentCopy copy;
  final VoidCallback onDismiss;

  const _MomentDialogCard({required this.copy, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final accent = switch (copy.tone) {
      _MomentTone.celebratory => AppColors.brass,
      _MomentTone.drama => AppColors.crimson,
      _MomentTone.informational => AppColors.textSecondary,
      _MomentTone.neutral => AppColors.borderStrong,
    };
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    Widget card = Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: accent, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(copy.icon, size: 40, color: accent),
          const SizedBox(height: AppSpacing.md),
          Text(copy.title, style: AppTypography.displayMedium, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.sm),
          Text(copy.body, style: AppTypography.bodySmall, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.lg),
          ElevatedButton(onPressed: onDismiss, child: const Text('Continue')),
        ],
      ),
    );
    if (!reduceMotion) {
      card = card
          .animate()
          .scale(
            begin: const Offset(0.9, 0.9),
            end: const Offset(1, 1),
            duration: AppMotion.ceremonyStamp,
            curve: Curves.easeOutBack,
          )
          .fadeIn(duration: AppMotion.ceremonyHeadline);
    }
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: card,
    );
  }
}
