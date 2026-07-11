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
/// `registerNewPlayer` stores that token without signing in (matching
/// `LocalAuthService`: registering a player doesn't change the current
/// user); `switchToUser` exchanges the stored token via
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
    var user = _auth.currentUser;
    if (user == null) {
      final credential = await _auth.signInAnonymously();
      user = credential.user!;
    }
    await user.updateDisplayName(displayName);
    await user.reload();
    return _toAppUser(_auth.currentUser)!;
  }

  @override
  Future<AppUser> registerNewPlayer(String displayName) async {
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
