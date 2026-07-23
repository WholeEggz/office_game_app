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

  // Normalized (trim+lowercase) -> first-seen display value, one map per
  // suggest* dimension — mirrors the Firebase backend's
  // locations_countries/locations_cities/locations_companies lookup
  // collections, just in-memory instead of Firestore docs.
  final _countries = <String, String>{};
  final _cities = <String, String>{};
  final _companies = <String, String>{};

  // Each identity's own saved location, keyed by uid — separate from the
  // shared suggestion directories above, which only ever accumulate
  // display values, never say who registered which one.
  final _profiles = <String, LocationProfile>{};

  // Pre-game hint dismissals (see AuthService.dismissHint), keyed by uid —
  // same per-identity storage shape as _profiles.
  final _dismissedHints = <String, Set<String>>{};

  static const _maxSuggestions = 8;

  static String _normalize(String value) => value.trim().toLowerCase();

  // The shared, in-memory sibling of the Firebase backend's
  // locations_*/{value}.display field (see saveLocationProfile's doc
  // comment) — the value suggested back is always "Title Cased" the same
  // way, regardless of how it was actually typed.
  static String _titleCase(String value) {
    final trimmed = value.trim().toLowerCase();
    if (trimmed.isEmpty) return trimmed;
    return trimmed
        .split(RegExp(r'\s+'))
        .map((word) => word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  // Overwritten (not putIfAbsent) on every call, mirroring
  // saveLocationProfile's self-healing display rewrite — so a value that
  // somehow ended up recorded with different casing before this
  // normalization existed corrects itself the next time anyone registers
  // or edits into the same normalized value.
  void _recordLocation(Map<String, String> directory, String value) {
    final normalized = _normalize(value);
    if (normalized.isEmpty) return;
    directory[normalized] = _titleCase(value);
  }

  List<String> _suggest(Map<String, String> directory, String prefix) {
    final normalized = _normalize(prefix);
    if (normalized.isEmpty) return const [];
    return directory.entries
        .where((e) => e.key.startsWith(normalized))
        .map((e) => e.value)
        .take(_maxSuggestions)
        .toList();
  }

  @override
  Stream<AppUser?> get authStateChanges => _controller.stream;

  @override
  AppUser? get currentUser => _current;

  @override
  List<AppUser> get knownUsers => List.unmodifiable(_users.values);

  @override
  Future<AppUser> signInWithDisplayName(
    String displayName, {
    required String country,
    required String city,
    required String companyOrOffice,
  }) async {
    final matches = _users.values.where((u) => u.displayName == displayName);
    final user =
        matches.isNotEmpty ? matches.first : (id: _uuid.v4(), displayName: displayName);
    _users[user.id] = user;
    _current = user;
    _controller.add(user);
    _recordLocation(_countries, country);
    _recordLocation(_cities, city);
    _recordLocation(_companies, companyOrOffice);
    _profiles[user.id] = (country: country, city: city, companyOrOffice: companyOrOffice);
    return user;
  }

  @override
  Future<List<String>> suggestCountries(String prefix) async => _suggest(_countries, prefix);

  @override
  Future<List<String>> suggestCities(String prefix) async => _suggest(_cities, prefix);

  @override
  Future<List<String>> suggestCompanies(String prefix) async => _suggest(_companies, prefix);

  @override
  Future<LocationProfile?> currentLocationProfile() async {
    final user = _current;
    if (user == null) return null;
    return _profiles[user.id];
  }

  @override
  Future<void> updateLocationProfile({
    required String country,
    required String city,
    required String companyOrOffice,
  }) async {
    final user = _current;
    if (user == null) return;
    _recordLocation(_countries, country);
    _recordLocation(_cities, city);
    _recordLocation(_companies, companyOrOffice);
    _profiles[user.id] = (country: country, city: city, companyOrOffice: companyOrOffice);
  }

  // No real auth/rules to satisfy in Local mode — the suggest* methods
  // above are plain in-memory map reads, unconditionally available.
  @override
  Future<void> ensureSignedIn() async {}

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

  @override
  Future<Set<String>> fetchDismissedHints() async {
    final user = _current;
    if (user == null) return const {};
    return Set.unmodifiable(_dismissedHints[user.id] ?? const {});
  }

  @override
  Future<void> dismissHint(String hintId) async {
    final user = _current;
    if (user == null) return;
    _dismissedHints.putIfAbsent(user.id, () => {}).add(hintId);
  }
}
