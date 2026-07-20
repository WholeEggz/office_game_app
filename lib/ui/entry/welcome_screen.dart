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
///
/// Three interchangeable looks — two full-bleed poster variants (intro2,
/// then intro1) followed by the original mark-and-headline design last —
/// cycled by tapping anywhere on the page except the CTA itself, looping
/// back to the first after the last. Purely cosmetic: every variant
/// leads to the same [_enter].
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  // Cycle order: intro2 first, then intro1, then the original
  // mark-and-headline design last — reversed from first-added order.
  static const _posterAssets = [
    'assets/graphics/intro2.png',
    'assets/graphics/intro1.png',
  ];

  int _variant = 0;

  void _advance() {
    HapticFeedback.selectionClick();
    setState(() => _variant = (_variant + 1) % (_posterAssets.length + 1));
  }

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
    final content = _variant < _posterAssets.length
        ? _buildPoster(context, _posterAssets[_variant], reduceMotion)
        : _buildOriginal(context, reduceMotion);

    return Scaffold(
      body: GestureDetector(
        // The CTA button below is its own descendant gesture detector, so
        // it wins the tap over this one wherever it sits — this only ever
        // fires for a tap that lands outside it.
        behavior: HitTestBehavior.opaque,
        onTap: _advance,
        child: AnimatedSwitcher(
          duration: reduceMotion ? Duration.zero : AppMotion.ceremonyHeadline,
          child: KeyedSubtree(key: ValueKey(_variant), child: content),
        ),
      ),
    );
  }

  Widget _buildOriginal(BuildContext context, bool reduceMotion) {
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
    Widget cta = _cta();

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

    return DecoratedBox(
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
    );
  }

  /// The poster is noticeably taller (in aspect ratio) than a phone
  /// screen, so a full-height `BoxFit.cover` crops a lot off both sides
  /// to fill the remaining height. Capping how much of the screen's
  /// height the image is allowed to claim (top-anchored) trades a
  /// sliver of the poster's own bottom margin for a much gentler side
  /// crop — and as a side effect moves the poster's own baked-in title
  /// up off the very bottom edge, into clearer view above the CTA.
  static const _posterHeightFactor = 0.8;

  /// A full-bleed poster with its own title and tagline already baked in
  /// — so unlike [_buildOriginal], this doesn't repeat a headline over
  /// it, just eases its own lower edge into the app's background color
  /// with a light tint (not meant to hide anything, just soften the
  /// seam) so the CTA below sits on a legible, on-brand surface instead
  /// of directly over the busiest part of the photo.
  Widget _buildPoster(BuildContext context, String asset, bool reduceMotion) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;
        final imageHeight = totalHeight * _posterHeightFactor;
        final belowImageHeight = totalHeight - imageHeight;
        final buttonAreaHeight = belowImageHeight / 3;
        // Centered two-thirds of the way up from the screen's bottom
        // edge (equivalently, one third of the way down from the
        // poster's own bottom edge) — higher than dead-center in the
        // space below the poster, so there's more room below the button
        // than above it.
        final buttonTop = imageHeight + belowImageHeight / 6;

        Widget cta = _cta(height: buttonAreaHeight);
        if (!reduceMotion) {
          cta = cta.animate(delay: 300.ms).fadeIn(duration: AppMotion.ceremonyHeadline);
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            // Pure black, not the app's ink tone — matches the poster's
            // own near-black background exactly, so the seam below it
            // disappears rather than reading as a color shift.
            const ColoredBox(color: Colors.black),
            Align(
              alignment: Alignment.topCenter,
              child: FractionallySizedBox(
                widthFactor: 1,
                heightFactor: _posterHeightFactor,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(asset, fit: BoxFit.cover),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.45),
                          ],
                          stops: const [0, 0.8, 1],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: buttonTop,
              height: buttonAreaHeight,
              left: AppSpacing.xl,
              right: AppSpacing.xl,
              child: cta,
            ),
          ],
        );
      },
    );
  }

  Widget _cta({double? height}) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: ElevatedButton(
        onPressed: () => _enter(context),
        child: const Text('Begin the investigation'),
      ),
    );
  }
}
