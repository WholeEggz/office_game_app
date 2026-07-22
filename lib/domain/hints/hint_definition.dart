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

  /// True only for a hint with no natural completion signal in game state
  /// (currently just `welcome_help`) — the banner offers an explicit
  /// dismiss action for these, recorded via `GameRepository.dismissHint`.
  final bool dismissible;

  final String Function(HintContext context) message;
  final bool Function(HintContext context) isRelevant;
  final bool Function(HintContext context) isCompleted;

  const HintDefinition({
    required this.id,
    required this.scope,
    required this.audience,
    required this.priority,
    this.dismissible = false,
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
}
