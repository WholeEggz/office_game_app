import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../design/colors.dart';
import '../../design/spacing.dart';
import '../../design/typography.dart';
import '../../domain/hints/static_hint_catalog.dart';
import '../../domain/repositories/auth_service.dart';

/// A dismissible informational tip for onboarding screens (registration,
/// case list, case creation) that have no `Game`/`Player` state to hang a
/// dynamic in-game hint (`tutorial_hint_banner.dart`) off of — those exist
/// before a game does, or before the player has joined one. Same
/// sage-green look, but backed by `AuthService.dismissHint`/
/// `fetchDismissedHints` (player-level, not game-level) instead of the
/// dynamic hint catalog: once dismissed, [id] never shows again for this
/// identity, and it also reads as "Completed" in `HintProgressScreen`'s
/// merged list.
///
/// [id] must be an entry in `staticHintCatalog` — that's where the actual
/// message text lives, so the banner here and the progress list can never
/// drift apart.
class StaticHintBanner extends StatefulWidget {
  final String id;

  const StaticHintBanner({super.key, required this.id});

  @override
  State<StaticHintBanner> createState() => _StaticHintBannerState();
}

class _StaticHintBannerState extends State<StaticHintBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// Null until the initial dismissed-check resolves — nothing renders
  /// before then, so there's no flash of a hint that turns out to already
  /// be dismissed.
  bool? _dismissed;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.base);
    _load();
  }

  Future<void> _load() async {
    var dismissed = false;
    try {
      final dismissedIds = await context.read<AuthService>().fetchDismissedHints();
      dismissed = dismissedIds.contains(widget.id);
    } catch (_) {
      // Fail open: if the fetch itself errors (e.g. a transient network
      // hiccup), show the hint rather than leaving it hidden forever —
      // indistinguishable from "already dismissed" otherwise, since a
      // failed Future here would just leave `_dismissed` null forever.
      dismissed = false;
    }
    if (!mounted) return;
    setState(() => _dismissed = dismissed);
    if (!dismissed) _controller.forward();
  }

  Future<void> _dismiss() async {
    await _controller.reverse();
    if (!mounted) return;
    setState(() => _dismissed = true);
    try {
      await context.read<AuthService>().dismissHint(widget.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't dismiss that — try again.")),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed ?? true) return const SizedBox.shrink();
    return FadeTransition(
      opacity: _controller,
      child: Container(
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
                  child: Text(
                    staticHintCatalog.firstWhere((h) => h.id == widget.id).message,
                    style: AppTypography.body.copyWith(color: AppColors.sageText),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: _dismiss, child: const Text('Got it')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
