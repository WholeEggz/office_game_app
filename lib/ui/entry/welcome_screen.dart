import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../design/colors.dart';
import '../../design/graphics.dart';
import '../../design/spacing.dart';
import '../../design/typography.dart';
import 'entry_screen.dart';
import 'player_entry_screen.dart';

/// The signed-out-only first beat of a cold launch (see AppEntryGate,
/// which decides whether this shows at all) — atmosphere before the
/// functional flow starts. Leads to EntryScreen's Player/Tester choice in
/// debug builds; a real build has no Tester option, so it skips straight
/// to PlayerEntryScreen instead.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  void _enter(BuildContext context) {
    HapticFeedback.selectionClick();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => kDebugMode ? const EntryScreen() : const PlayerEntryScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    Widget mark = SvgPicture.asset(AppGraphics.appMark, width: 116, height: 116);
    Widget headline = Text(
      'Something mysterious is\nhappening around your office…',
      textAlign: TextAlign.center,
      style: AppTypography.displayLarge,
    );
    Widget subhead = Text(
      'A social deduction game for your team.',
      textAlign: TextAlign.center,
      style: AppTypography.body.copyWith(color: AppColors.textSecondary),
    );
    Widget cta = SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () => _enter(context),
        child: const Text('Begin the investigation'),
      ),
    );

    if (!reduceMotion) {
      // A single shimmer sweep once the seal has scaled in — not a
      // repeating one: an unbounded animation never settles, which hangs
      // pumpAndSettle() in any test that mounts this screen, and burns
      // battery for as long as a real user happens to linger here.
      mark = mark
          .animate()
          .scale(
            begin: const Offset(0.85, 0.85),
            end: const Offset(1, 1),
            duration: AppMotion.ceremonySeal,
            curve: Curves.easeOutBack,
          )
          .shimmer(
            duration: const Duration(milliseconds: 900),
            color: AppColors.brass.withValues(alpha: 0.55),
          );
      headline = headline
          .animate(delay: 250.ms)
          .fadeIn(duration: AppMotion.ceremonyHeadline)
          .slideY(begin: 0.15, end: 0, duration: AppMotion.ceremonyHeadline);
      subhead = subhead
          .animate(delay: 450.ms)
          .fadeIn(duration: AppMotion.ceremonyHeadline);
      cta = cta.animate(delay: 700.ms).fadeIn(duration: AppMotion.ceremonyHeadline);
    }

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.2),
            radius: 1.1,
            colors: [AppColors.surfaceRaised, AppColors.ink],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Column(
              children: [
                const Spacer(flex: 3),
                mark,
                const SizedBox(height: AppSpacing.xxl),
                headline,
                const SizedBox(height: AppSpacing.md),
                subhead,
                const Spacer(flex: 2),
                cta,
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
