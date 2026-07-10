import '../../domain/repositories/auth_service.dart';

/// Phase 1b target: phone number or email + display name only, no
/// corporate SSO (design pillar #3). Every method is unimplemented for now
/// — this class exists so the shape of the migration is visible without
/// inventing new architecture later.
class FirebaseAuthService implements AuthService {
  @override
  Stream<AppUser?> get authStateChanges => throw UnimplementedError();

  @override
  AppUser? get currentUser => throw UnimplementedError();

  @override
  List<AppUser> get knownUsers => throw UnimplementedError();

  @override
  Future<AppUser> signInWithDisplayName(String displayName) =>
      throw UnimplementedError();

  @override
  Future<AppUser> registerNewPlayer(String displayName) =>
      throw UnimplementedError();

  @override
  Future<void> switchToUser(String userId) => throw UnimplementedError();

  @override
  Future<void> signOut() => throw UnimplementedError();
}
