/// One entry in [staticHintCatalog] — see that constant's doc comment.
class StaticHintInfo {
  final String id;
  final String message;

  const StaticHintInfo({required this.id, required this.message});
}

/// The pre-game counterpart to `hint_catalog.dart`'s `hintCatalog`: plain
/// id+message pairs for the onboarding screens that exist before a `Game`
/// does (registration, "Find your case", case creation) — no
/// `HintContext`, no relevant/completed predicates, since there's no game
/// state to evaluate against. `StaticHintBanner` looks up its message here
/// by id (single source of truth, so the banner and `HintProgressScreen`'s
/// merged list can never drift apart); `AuthService.dismissHint`/
/// `fetchDismissedHints` is what tracks whether a given id has been seen.
///
/// `TUTORIAL_HINTS.md` at the repo root documents each entry (id, screen,
/// file, message) — keep it in sync when adding, removing, or rewording
/// one.
const List<StaticHintInfo> staticHintCatalog = [
  StaticHintInfo(
    id: 'registration_location',
    message: "The location you enter here becomes a case's location "
        'if you start one later, so keep it accurate.',
  ),
  StaticHintInfo(
    id: 'case_list_location_sort',
    message: 'Cases near your office float to the top of this list — '
        "join one below, or start your own if you don't see it yet.",
  ),
  StaticHintInfo(
    id: 'case_creation_restricted_location',
    message: 'Mark this case Restricted if you want to control who can '
        "join with a passphrase. Its location comes from your own "
        'profile — the one you set when you registered.',
  ),
];
