import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

import '../../domain/repositories/auth_service.dart';

/// Phase 1b target: phone number or email + display name only, no
/// corporate SSO (design pillar #3) — real phone/email verification UI is
/// a later milestone. For now `signInWithDisplayName` signs into an
/// anonymous Firebase Auth identity and attaches the display name; the
/// SDK's own local persistence is what makes retyping the same name
/// resume the same identity across app restarts, matching
/// `LocalAuthService`'s intent without needing a lookup.
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
    if (user == null) {
      final credential = await _auth.signInAnonymously();
      user = credential.user!;
    }
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
