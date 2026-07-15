import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

import '../../domain/repositories/auth_service.dart';

/// Phase 1b target: phone number or email + display name only, no
/// corporate SSO (design pillar #3) — real phone/email verification UI is
/// a later milestone. For now `signInWithDisplayName` signs into an
/// anonymous Firebase Auth identity per display name, tracked in memory
/// for the lifetime of this instance (see `_currentDisplayName`) —
/// retyping the same name reuses the same identity within one run,
/// matching `LocalAuthService`'s name-lookup semantics.
///
/// The anonymous Firebase Auth session itself persists across app
/// restarts (normal Firebase Auth behavior — the SDK caches it in secure
/// device storage until an explicit `signOut()`), but there's nowhere
/// reliable to recover the *display name* that goes with it after a
/// restart: `_currentDisplayName` is just an in-memory field, and Firebase
/// Auth's own displayName field can't be used (see the comment on
/// `signInWithDisplayName`). `resumeSession` and `signInWithDisplayName`
/// below back that mapping with a plain Firestore doc (`users/{uid}`)
/// instead — this app's own store, not a Firebase Auth profile field, so
/// it doesn't hit that bug.
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
  FirebaseAuthService({fb.FirebaseAuth? auth, FirebaseFunctions? functions, FirebaseFirestore? firestore})
      : _auth = auth ?? fb.FirebaseAuth.instance,
        _functions = functions ?? FirebaseFunctions.instance,
        _db = firestore ?? FirebaseFirestore.instance;

  final fb.FirebaseAuth _auth;
  final FirebaseFunctions _functions;
  final FirebaseFirestore _db;

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
    // anonymous users on iOS) — see the flutterfire issue tracker. The
    // `users/{uid}` Firestore doc below is this app's own store for the
    // display name instead (see this class's doc comment).
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
    await _db.collection('users').doc(user.uid).set(
      {'displayName': displayName},
      SetOptions(merge: true),
    );
    return (id: user.uid, displayName: displayName);
  }

  @override
  Future<AppUser?> resumeSession() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    if (_currentDisplayName != null) {
      // Already resolved earlier this run (e.g. this screen was already
      // entered once) — no need to hit Firestore again.
      return (id: user.uid, displayName: _currentDisplayName!);
    }
    final doc = await _db.collection('users').doc(user.uid).get();
    final displayName = doc.data()?['displayName'] as String?;
    // No stored name means this anonymous session predates this feature,
    // or was only ever used for the debug quick-start throwaway session
    // (registerNewPlayer/proposeElimination-style callers) — either way,
    // there's nothing real to resume, so fall back to registration rather
    // than showing a blank name.
    if (displayName == null || displayName.isEmpty) return null;
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
