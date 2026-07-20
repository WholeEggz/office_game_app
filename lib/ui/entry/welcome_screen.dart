import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../design/spacing.dart';
import 'entry_screen.dart';
import 'player_entry_screen.dart';

/// The signed-out-only first beat of a cold launch (see AppEntryGate,
/// which decides whether this shows at all) — atmosphere before the
/// functional flow starts. Leads to EntryScreen's Player/Tester choice in
/// debug builds; a real build has no Tester option, so it skips straight
/// to PlayerEntryScreen instead.
///
/// A single full-bleed poster (intro2) for now — the earlier tap-to-cycle
/// through other looks is paused (see git history for the mark-and-
/// headline design and the intro1 variant) in favor of this: a tap
/// doesn't change the screen, it reveals the next line of a slow tease
/// of secrets, each played with the same fade-in/whisper/fade-out
/// treatment as the first line, which plays on its own shortly after
/// load. Looping back to the first secret after the last, indefinitely.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  static const _posterAsset = 'assets/graphics/intro2.png';

  /// Whispered one at a time — [0] plays itself, unprompted, shortly after
  /// load; every tap after that reveals the next.
  static const _secrets = [
    'Something mysterious is happening in your office',
    'Some of your friends work on a secret case',
    'Some of them belong to the mafia',
    "No one is quite who they seem to be",
    'Trust is the first thing that goes missing',
    'The only way to know for sure is to look closer',
  ];

  int _secretIndex = 0;

  /// True once the player has tapped at least once — the very first
  /// secret plays itself after a deliberate breath of quiet; every one a
  /// tap reveals should feel immediate instead, not wait through that
  /// same pause again.
  bool _hasTapped = false;

  void _revealNextSecret() {
    HapticFeedback.selectionClick();
    setState(() {
      _hasTapped = true;
      _secretIndex = (_secretIndex + 1) % _secrets.length;
    });
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
    return Scaffold(
      body: GestureDetector(
        // The CTA button below is its own descendant gesture detector, so
        // it wins the tap over this one wherever it sits — this only ever
        // fires for a tap that lands outside it.
        behavior: HitTestBehavior.opaque,
        onTap: _revealNextSecret,
        child: _buildPoster(context, reduceMotion),
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

  Widget _buildPoster(BuildContext context, bool reduceMotion) {
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
                    Image.asset(_posterAsset, fit: BoxFit.cover),
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
                    // Never intercepts the reveal-next-secret tap
                    // underneath, whether it's mid-fade or invisible.
                    if (!reduceMotion)
                      IgnorePointer(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                            child: _buildWhisper(),
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

  /// A one-shot flourish — fades in over the poster, holds, then fades
  /// back out — for whichever secret is current, keyed so a fresh tap
  /// (or the very first automatic showing) always replays from scratch
  /// rather than interrupting an existing fade in place. A slight fixed
  /// tilt (not an animated rotation) plus a faint, near-whispered fill
  /// give it a torn-poster-insert look rather than a clean, flat banner.
  Widget _buildWhisper() {
    return KeyedSubtree(
      key: ValueKey(_secretIndex),
      child: Transform.rotate(
        angle: -0.06,
        child: Text(
          _secrets[_secretIndex],
          textAlign: TextAlign.center,
          style: GoogleFonts.anton(
            fontSize: 34,
            height: 1.3,
            color: Colors.white.withValues(alpha: 0.32),
            letterSpacing: 1,
            shadows: [
              Shadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 16),
            ],
          ),
        ),
      )
          .animate()
          // The initial wait is a per-effect delay on fadeIn, not a
          // construct-level Animate(delay:) — that variant runs a plain
          // timer before the animation controller itself even starts,
          // which pumpAndSettle() doesn't track the way it does the
          // controller-driven gap in .then(delay:) below, and left a
          // dangling Timer past widget disposal in tests. Only the very
          // first, unprompted showing gets that breath of quiet — a tap
          // should feel answered right away, not delayed.
          .fadeIn(delay: _hasTapped ? Duration.zero : 1200.ms, duration: 900.ms)
          .then(delay: 2200.ms)
          .fadeOut(duration: 900.ms),
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
