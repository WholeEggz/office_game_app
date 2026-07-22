import 'hint_context.dart';
import 'hint_definition.dart';

enum HintStatus { completed, active, notYetRelevant }

/// Evaluates one [HintDefinition] against [context] — pure, no I/O, so the
/// banner and the full progress list share exactly one notion of status.
HintStatus evaluateHint(HintDefinition hint, HintContext context) {
  if (!hint.appliesTo(context)) return HintStatus.notYetRelevant;
  if (hint.isCompleted(context)) return HintStatus.completed;
  if (hint.isRelevant(context)) return HintStatus.active;
  return HintStatus.notYetRelevant;
}

/// The single hint to show in the banner: highest-[HintDefinition.priority]
/// among every hint currently [HintStatus.active] for [context]. Null if
/// nothing is active right now.
HintDefinition? topBannerHint(List<HintDefinition> catalog, HintContext context) {
  HintDefinition? best;
  for (final hint in catalog) {
    if (evaluateHint(hint, context) != HintStatus.active) continue;
    if (best == null || hint.priority > best.priority) best = hint;
  }
  return best;
}

/// Every hint in [catalog] evaluated against [context], in catalog order —
/// powers the full tutorial-progress list.
List<(HintDefinition, HintStatus)> allHintStatuses(
  List<HintDefinition> catalog,
  HintContext context,
) {
  return [for (final hint in catalog) (hint, evaluateHint(hint, context))];
}
