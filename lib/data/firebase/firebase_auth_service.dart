import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

import '../../domain/repositories/auth_service.dart';

/// Phase 1b target: phone number or email + display name only, no
/// corporate SSO (design pillar #3) — real phone/email verification UI is
/// a later milestone. For now `signInWithDisplayName` signs into an
/// anonymous Firebase Auth identity per display name, tracked in memory
/// for the lifetime of this instance (see `_currentDisplayName`) —
/// retyping the same name reuses the same identity within one run,
/// matching `LocalAuthService`'s name-lookup semantics. Doesn't persist
/// across app restarts (there's no reliable place to store the mapping:
/// Firebase Auth's own displayName field can't be used — see the comment
/// on `signInWithDisplayName` — and this app has no other backing store),
/// so a fresh launch always establishes a fresh identity even for a name
/// used before.
///
/// The debug role switcher's multi-identity simulation
/// (`registerNewPlayer`/`switchToUser`) has no natural mapping onto real
/// Firebase Auth, which only supports one signed-in user per app instance
/// — see implementation_plan.md's "Auth and the debug switcher" section.
/// It's reproduced via a debug-gated callable (`debugMintTestUser`,
/// denied server-side for any build not pointed at the emulator) that
/// mints a fresh test identity and a custom auth token.
/// `registerNewPlayer` stores that token without signing in as *that*
/// identity (matching `LocalAuthService`: registering a player doesn't
/// change the current user) — though it does establish some throwaway
/// anonymous session if none exists yet, since every other Cloud Function
/// this app calls needs an authenticated caller and quick-start is often
/// the first thing tapped. `switchToUser` exchanges the stored token via
/// `signInWithCustomToken`.
class FirebaseAuthService implements AuthService {
  FirebaseAuthService({fb.FirebaseAuth? auth, FirebaseFunctions? functions})
      : _auth = auth ?? fb.FirebaseAuth.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  final fb.FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  final _mintedUsers = <String, ({String displayName, String customToken})>{};
  String? _currentDisplayName;

  AppUser? _toAppUser(fb.User? user) =>
      user == null ? null : (id: user.uid, displayName: user.displayName ?? '');

  @override
  Stream<AppUser?> get authStateChanges => _auth.authStateChanges().map(_toAppUser);

  @override
  AppUser? get currentUser => _toAppUser(_auth.currentUser);

  @override
  List<AppUser> get knownUsers => [
        for (final entry in _mintedUsers.entries)
          (id: entry.key, displayName: entry.value.displayName),
      ];

  @override
  Future<AppUser> signInWithDisplayName(String displayName) async {
    // Deliberately not user.updateDisplayName()/reload(): that round-trip
    // hits a firebase_auth plugin bug (native updateProfile throws a
    // generic internal-error against the Auth emulator, at least for
    // anonymous users on iOS) — see the flutterfire issue tracker. Nothing
    // in this app reads Firebase Auth's own displayName field (grep
    // confirms AuthService.currentUser has no other callers), so the
    // display name only ever needs to travel as far as this return value.
    var user = _auth.currentUser;
    // A different name than whoever's currently signed in must not reuse
    // that identity — without this check, retyping any name here just
    // returned the *existing* anonymous session's uid with a new label
    // slapped on the return value, so a second name typed in the same run
    // showed up everywhere (game lists, in-game rosters) still tagged
    // with the first name's already-joined games and player docs.
    if (user != null && _currentDisplayName != displayName) {
      await _auth.signOut();
      user = null;
    }
    if (user == null) {
      final credential = await _auth.signInAnonymously();
      user = credential.user!;
    }
    _currentDisplayName = displayName;
    return (id: user.uid, displayName: displayName);
  }

  @override
  Future<AppUser> registerNewPlayer(String displayName) async {
    // The minted identity below is deliberately not signed into (see this
    // class's doc comment), but every other Cloud Function this app calls
    // (createGame, addPlayer, ...) requires *some* authenticated caller.
    // If quick-start is the first thing tapped on a fresh launch, nothing
    // has signed in yet — without this, the createGame call right after
    // this one gets rejected as unauthenticated. A throwaway anonymous
    // session is enough; it's never the identity anything switches to.
    if (_auth.currentUser == null) {
      await _auth.signInAnonymously();
    }

    final callable = _functions.httpsCallable('debugMintTestUser');
    final result = await callable.call<Map<String, dynamic>>({'displayName': displayName});
    final uid = result.data['uid'] as String;
    final customToken = result.data['customToken'] as String;
    _mintedUsers[uid] = (displayName: displayName, customToken: customToken);
    return (id: uid, displayName: displayName);
  }

  @override
  Future<void> switchToUser(String userId) async {
    final minted = _mintedUsers[userId];
    if (minted == null) {
      throw StateError(
        'Unknown test user $userId — it must be minted via registerNewPlayer first.',
      );
    }
    await _auth.signInWithCustomToken(minted.customToken);
  }

  @override
  Future<void> signOut() => _auth.signOut();
}
