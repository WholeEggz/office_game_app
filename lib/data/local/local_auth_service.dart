import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../domain/repositories/auth_service.dart';

/// No real authentication — just enough identity to let the debug role
/// switcher simulate several coworkers from one device (Phase 1a).
class LocalAuthService implements AuthService {
  final _uuid = const Uuid();
  final _users = <String, AppUser>{};
  final _controller = StreamController<AppUser?>.broadcast();
  AppUser? _current;

  @override
  Stream<AppUser?> get authStateChanges => _controller.stream;

  @override
  AppUser? get currentUser => _current;

  @override
  List<AppUser> get knownUsers => List.unmodifiable(_users.values);

  @override
  Future<AppUser> signInWithDisplayName(String displayName) async {
    final matches = _users.values.where((u) => u.displayName == displayName);
    final user =
        matches.isNotEmpty ? matches.first : (id: _uuid.v4(), displayName: displayName);
    _users[user.id] = user;
    _current = user;
    _controller.add(user);
    return user;
  }

  // No cross-restart persistence in Local mode at all (a fresh process
  // always starts with `_current` null) — this just returns whatever's
  // already current within this same run, the same "nothing new to do"
  // answer a genuine restart would give.
  @override
  Future<AppUser?> resumeSession() async => _current;

  @override
  Future<AppUser> registerNewPlayer(String displayName) async {
    final user = (id: _uuid.v4(), displayName: displayName);
    _users[user.id] = user;
    return user;
  }

  @override
  Future<void> switchToUser(String userId) async {
    final user = _users[userId];
    if (user == null) {
      throw StateError('Unknown local user $userId');
    }
    _current = user;
    _controller.add(user);
  }

  @override
  Future<void> signOut() async {
    _current = null;
    _controller.add(null);
  }
}
