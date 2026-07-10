/// A lightweight local identity — not a `Player`, since one identity can
/// join many `Game`s. Modeled as a record instead of a new class so the
/// domain model list stays limited to the five shapes shared with the
/// future Firebase implementation.
typedef AppUser = ({String id, String displayName});

/// Device-level identity, separate from per-game role/state (that's
/// `Player`). The local implementation has no real authentication — it's a
/// stand-in so `office_game_app` can simulate several people from one
/// device via the debug role switcher.
abstract class AuthService {
  Stream<AppUser?> get authStateChanges;

  AppUser? get currentUser;

  /// All identities created so far on this device — powers the role
  /// switcher's "jump into this player's view" list.
  List<AppUser> get knownUsers;

  /// Registers a new local identity (or returns the existing one if this
  /// display name was already used) and makes it the current user. Meant
  /// for "sign in as yourself" — the one field where resuming the same
  /// identity across games by re-typing the same name is the point.
  Future<AppUser> signInWithDisplayName(String displayName);

  /// Always registers a brand-new local identity, even if [displayName]
  /// matches an existing one, and does not change [currentUser]. Meant for
  /// adding *other* simulated players to a game — those are meant to
  /// represent different coworkers, and two of them sharing a first name
  /// is normal, not a reason to collapse them into the same identity (and
  /// therefore the same already-joined-this-game error).
  Future<AppUser> registerNewPlayer(String displayName);

  /// Debug-only: switch the current-user pointer to an identity already
  /// created via [signInWithDisplayName] or [registerNewPlayer], without
  /// creating a new one.
  Future<void> switchToUser(String userId);

  Future<void> signOut();
}
