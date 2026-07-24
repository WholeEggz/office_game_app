/// A lightweight local identity — not a `Player`, since one identity can
/// join many `Game`s. Modeled as a record instead of a new class so the
/// domain model list stays limited to the five shapes shared with the
/// future Firebase implementation.
typedef AppUser = ({String id, String displayName});

/// An identity's own saved country/city/companyOrOffice — separate from
/// [AppUser] since nothing besides registration and [AuthService]'s own
/// methods needs it riding along everywhere an [AppUser] does.
typedef LocationProfile = ({String country, String city, String companyOrOffice});

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
  ///
  /// [country]/[city]/[companyOrOffice] are saved alongside the identity
  /// (not part of [AppUser] itself — nothing besides registration and the
  /// suggest* methods below needs them) and folded into the shared
  /// autocomplete directories those methods read from, so a later
  /// registration typing a near-duplicate value (e.g. "Acme Corp" vs
  /// "ACME") gets nudged toward reusing the same one.
  Future<AppUser> signInWithDisplayName(
    String displayName, {
    required String country,
    required String city,
    required String companyOrOffice,
  });

  /// Already-registered countries/cities/companies starting with [prefix]
  /// (case/whitespace-insensitive), most-used first where that's known —
  /// purely a typing convenience for registration's location fields, never
  /// a hard picker; a value with no match is still accepted as free text.
  Future<List<String>> suggestCountries(String prefix);
  Future<List<String>> suggestCities(String prefix);
  Future<List<String>> suggestCompanies(String prefix);

  /// The current identity's own saved location — null if nothing's been
  /// saved (a `registerNewPlayer`-created debug identity never calls
  /// [signInWithDisplayName], so never saves one). Powers "find your
  /// case"'s company/city/country-match sort priority.
  Future<LocationProfile?> currentLocationProfile();

  /// Updates the current identity's saved location, independent of
  /// [signInWithDisplayName] — for editing an already-registered profile
  /// (ProfileScreen) without touching display name or session state. Takes
  /// the full triple even when only one field actually changed, matching
  /// [signInWithDisplayName]'s location parameters and the
  /// `saveLocationProfile` Cloud Function's signature underneath.
  Future<void> updateLocationProfile({
    required String country,
    required String city,
    required String companyOrOffice,
  });

  /// Establishes at least a minimal (e.g. anonymous) session if there
  /// isn't one already, without registering any identity or display name
  /// — needed before the registration form's location fields can query
  /// [suggestCountries]/[suggestCities]/[suggestCompanies], since those
  /// read Firestore collections gated on `isSignedIn()`, and otherwise
  /// nothing signs the device in until [signInWithDisplayName] runs (on
  /// "Continue", after the fields have already been typed into). A no-op
  /// wherever there's no real auth/rules concept to satisfy (Local mode).
  Future<void> ensureSignedIn();

  /// Checks for an identity already signed in from a previous app launch
  /// and resolves its full [AppUser] — including [AppUser.displayName],
  /// which [currentUser] alone can't reliably provide for the Firebase
  /// backend (see `FirebaseAuthService`'s implementation doc). Returns
  /// null when there's nothing to resume, in which case the caller should
  /// fall back to [signInWithDisplayName]'s registration flow. Meant to be
  /// called once, on the real player entry screen's own startup — this is
  /// the "did this device already register?" check, not a general
  /// replacement for [currentUser].
  Future<AppUser?> resumeSession();

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

  /// Hint ids the current identity has permanently dismissed on a
  /// pre-game screen (registration, "Find your case", case creation) —
  /// see `StaticHintBanner`. Player-level, not game-level, since those
  /// screens exist before any `Game`/`gameId` does, unlike
  /// `GameRepository.dismissHint`. Empty when there's no current user.
  Future<Set<String>> fetchDismissedHints();

  /// Records that the current identity dismissed pre-game hint [hintId] —
  /// see [fetchDismissedHints]. A no-op when there's no current user.
  Future<void> dismissHint(String hintId);

  /// Debug/testing convenience: clears every pre-game hint the current
  /// identity has dismissed — see [fetchDismissedHints]. A no-op when
  /// there's no current user.
  Future<void> clearDismissedHints();
}
