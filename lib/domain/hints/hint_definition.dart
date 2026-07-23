import 'hint_context.dart';

/// `onboarding` hints complete once and never resurface for this game (a
/// first-time nudge); `recurring` hints re-derive relevance/completion every
/// time their predicates run, since they key off state that resets each
/// round (e.g. "have I voted *this* round").
enum HintScope { onboarding, recurring }

/// Who a hint is ever shown to. `mafia` is scoped to a *current* mafia
/// member ([HintContext.isCurrentMafia]) — an unmasked former member falls
/// back to `everyone`'s hints like anyone else.
enum HintAudience { everyone, mafia }

/// A second, optional screen a hint's "Got it" row can offer to jump to
/// (e.g. `welcome_help` -> Help). Kept as a plain enum here (no
/// `BuildContext`/`Navigator` in this domain layer) — the UI maps each
/// value to an actual navigation in `tutorial_hint_banner.dart`.
enum HintActionTarget { help }

/// One entry in the tutorial hint catalog (`hint_catalog.dart`). Pure data
/// plus predicates, no I/O — the same definition is evaluated for the
/// banner (top unmet hint) and the full progress list from whatever's
/// already in a [HintContext].
class HintDefinition {
  final String id;
  final HintScope scope;
  final HintAudience audience;

  /// Higher shows first in the banner when more than one hint is relevant
  /// and unmet at once.
  final int priority;

  /// Every hint gets a "Got it" button. For most hints that's the only way
  /// they ever complete besides their own [isCompleted] check; what
  /// differs is *how long* dismissing one sticks — see [dismissDiscriminator].
  ///
  /// Null (the default, e.g. every `onboarding` hint): dismissal is keyed by
  /// [id] alone, so it's permanent for this game — matches the "onboarding
  /// hints never resurface" rule.
  ///
  /// Non-null (every `recurring` hint): dismissal is keyed by [id] plus
  /// whatever this returns (e.g. the current round number, or the current
  /// signal's description) — so tapping "Got it" only silences *this*
  /// occurrence. Once the discriminator changes (a new round starts, a new
  /// signal goes out), the key changes too and the hint is free to
  /// reappear — giving the player real "Got it, leave me alone for now"
  /// freedom without permanently losing a still-useful recurring reminder.
  final String Function(HintContext context)? dismissDiscriminator;

  /// A second action alongside "Got it", for a hint whose message points
  /// at a specific other screen (only `welcome_help` -> Help today). Null
  /// for every hint that's just describing something on the current screen.
  final String? actionLabel;
  final HintActionTarget? actionTarget;

  final String Function(HintContext context) message;
  final bool Function(HintContext context) isRelevant;
  final bool Function(HintContext context) isCompleted;

  const HintDefinition({
    required this.id,
    required this.scope,
    required this.audience,
    required this.priority,
    this.dismissDiscriminator,
    this.actionLabel,
    this.actionTarget,
    required this.message,
    required this.isRelevant,
    required this.isCompleted,
  });

  bool appliesTo(HintContext context) {
    switch (audience) {
      case HintAudience.everyone:
        return true;
      case HintAudience.mafia:
        return context.isCurrentMafia;
    }
  }

  /// The key checked against [HintContext.dismissedHintIds] — see
  /// [dismissDiscriminator] for what makes a dismissal permanent vs.
  /// "just for now".
  String dismissKey(HintContext context) {
    final discriminator = dismissDiscriminator;
    return discriminator == null ? id : '$id::${discriminator(context)}';
  }
}
