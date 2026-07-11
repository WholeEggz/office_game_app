import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../domain/models/game.dart';
import '../../domain/models/game_moment.dart';
import '../../domain/models/mafia_thread_entry.dart';
import '../../domain/models/observation.dart';
import '../../domain/models/player.dart';
import '../../domain/models/vote.dart';
import '../../domain/repositories/game_repository.dart';

/// Every villager's starting vote weight (concept doc §5) — mirrors
/// `LocalGameRepository`'s `_startingVoteWeight` and the Cloud Functions
/// side's `STARTING_VOTE_WEIGHT`.
const _startingVoteWeight = 3;

/// Phase 1b target: Firestore + Cloud Functions, per the redaction
/// architecture in `implementation_plan.md` — a true-doc/public-mirror/
/// cell-view split, since Firestore security rules can't express
/// `LocalGameRepository`'s per-viewer role redaction directly (a rule is a
/// binary allow/deny on a whole document, not a per-viewer field
/// transform). `createGame`/`addPlayer`/`watchGames`/`watchVisiblePlayers`
/// are implemented (Milestone 3); everything else still throws
/// `UnimplementedError` until Milestone 4 replaces
/// `LocalGameRepository`'s equivalent logic function-by-function.
///
/// One thing that doesn't carry over as-is from `LocalGameRepository`: the
/// 1-hour execution-window lapse there is a plain `dart:async` `Timer`,
/// which only fires while this process is running. Here it needs to be a
/// scheduled Cloud Function (or a Firestore TTL-style sweep) so a proposal
/// still lapses correctly even if every device is offline when the window
/// closes.
class FirebaseGameRepository implements GameRepository {
  FirebaseGameRepository({FirebaseFirestore? firestore, FirebaseFunctions? functions})
      : _db = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> get _games => _db.collection('games');

  @override
  Future<Game> createGame({
    required String locationTag,
    required int minPlayers,
    required String creatorId,
    required String creatorName,
    int mafiaCount = 1,
    double recruitmentUnlockThreshold = 0.2,
    Duration executionWindow = const Duration(hours: 1),
    Duration dailyCutoffTime = const Duration(hours: 17),
    String rulesDescription = '',
  }) async {
    final callable = _functions.httpsCallable('createGame');
    final result = await callable.call<Map<String, dynamic>>({
      'locationTag': locationTag,
      'minPlayers': minPlayers,
      'creatorId': creatorId,
      'creatorName': creatorName,
      'mafiaCount': mafiaCount,
      'recruitmentUnlockThreshold': recruitmentUnlockThreshold,
      'executionWindowSeconds': executionWindow.inSeconds,
      'dailyCutoffSeconds': dailyCutoffTime.inSeconds,
      'rulesDescription': rulesDescription,
    });
    final gameId = result.data['gameId'] as String;
    // Callers only ever use the returned game's `id` (case creation and the
    // debug role switcher both immediately navigate on it) — constructing
    // this from the known request params avoids a read-after-write race
    // against the callable's own Firestore commit.
    return Game(
      id: gameId,
      locationTag: locationTag,
      minPlayers: minPlayers,
      players: [
        Player(id: creatorId, name: creatorName, role: PlayerRole.villager, joinedAt: DateTime.now()),
      ],
      rulesDescription: rulesDescription,
      mafiaCount: mafiaCount,
      recruitmentUnlockThreshold: recruitmentUnlockThreshold,
      executionWindow: executionWindow,
      dailyCutoffTime: dailyCutoffTime,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<Player> addPlayer({
    required String gameId,
    required String playerId,
    required String name,
  }) async {
    final callable = _functions.httpsCallable('addPlayer');
    try {
      await callable.call<Map<String, dynamic>>({
        'gameId': gameId,
        'playerId': playerId,
        'name': name,
      });
    } on FirebaseFunctionsException catch (e) {
      // Preserves GameRepository.addPlayer's documented StateError contract
      // (role_switcher_screen.dart and player_entry_screen.dart both catch
      // `on StateError` specifically) without leaking Firebase-specific
      // exception types past this seam.
      if (e.code == 'already-exists' || e.code == 'failed-precondition' || e.code == 'not-found') {
        throw StateError(e.message ?? e.code);
      }
      rethrow;
    }
    return Player(id: playerId, name: name, role: PlayerRole.villager, joinedAt: DateTime.now());
  }

  @override
  Future<void> leaveGame({
    required String gameId,
    required String playerId,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> startGame(String gameId) => throw UnimplementedError();

  @override
  Stream<Game> watchGame(String gameId) => throw UnimplementedError();

  @override
  Stream<List<Game>> watchGames({required String viewerId}) {
    final controller = StreamController<List<Game>>.broadcast();
    final gamesById = <String, Game>{};
    final playerSubs = <String, StreamSubscription<List<Player>>>{};
    late final StreamSubscription<QuerySnapshot<Map<String, dynamic>>> gamesSub;

    void emit() => controller.add(gamesById.values.toList());

    gamesSub = _games.snapshots().listen((snapshot) {
      final seenIds = <String>{};
      for (final doc in snapshot.docs) {
        seenIds.add(doc.id);
        final existingPlayers = gamesById[doc.id]?.players ?? const <Player>[];
        gamesById[doc.id] = _gameFromDoc(doc, players: existingPlayers);
        playerSubs.putIfAbsent(doc.id, () {
          return watchVisiblePlayers(gameId: doc.id, viewerId: viewerId).listen((players) {
            final current = gamesById[doc.id];
            if (current == null) return;
            gamesById[doc.id] = current.copyWith(players: players);
            emit();
          });
        });
      }
      for (final staleId in gamesById.keys.where((id) => !seenIds.contains(id)).toList()) {
        gamesById.remove(staleId);
        unawaited(playerSubs.remove(staleId)?.cancel());
      }
      emit();
    });

    controller.onCancel = () async {
      await gamesSub.cancel();
      for (final sub in playerSubs.values) {
        await sub.cancel();
      }
    };
    return controller.stream;
  }

  /// Composes `publicPlayers` + the viewer's own true doc (for their own
  /// unredacted entry) + `cellViews/{viewerId}` (for cell-linked role
  /// reveals) into the same `List<Player>` shape
  /// `LocalGameRepository._visiblePlayers` produces — no UI code changes,
  /// matching the seam this whole architecture is built around.
  @override
  Stream<List<Player>> watchVisiblePlayers({
    required String gameId,
    required String viewerId,
  }) {
    final gameRef = _games.doc(gameId);
    final controller = StreamController<List<Player>>.broadcast();

    QuerySnapshot<Map<String, dynamic>>? publicSnap;
    DocumentSnapshot<Map<String, dynamic>>? selfSnap;
    DocumentSnapshot<Map<String, dynamic>>? cellViewSnap;

    void emit() {
      final public = publicSnap;
      if (public == null) return;
      final knownRoles = (cellViewSnap?.data()?['knownRoles'] as Map<String, dynamic>?) ?? const {};
      final selfData = (selfSnap?.exists ?? false) ? selfSnap!.data() : null;

      final players = public.docs.map((doc) {
        if (doc.id == viewerId && selfData != null) {
          return _playerFromTrueDoc(viewerId, selfData);
        }
        final revealedRole = knownRoles[doc.id] as String?;
        return _playerFromPublicDoc(doc.id, doc.data(), roleOverride: revealedRole);
      }).toList();
      controller.add(players);
    }

    final subs = <StreamSubscription>[
      gameRef.collection('publicPlayers').snapshots().listen((snap) {
        publicSnap = snap;
        emit();
      }),
      gameRef.collection('players').doc(viewerId).snapshots().listen((snap) {
        selfSnap = snap;
        emit();
      }),
      gameRef.collection('cellViews').doc(viewerId).snapshots().listen((snap) {
        cellViewSnap = snap;
        emit();
      }),
    ];

    controller.onCancel = () async {
      for (final sub in subs) {
        await sub.cancel();
      }
    };
    return controller.stream;
  }

  Game _gameFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc, {required List<Player> players}) {
    final data = doc.data();
    return Game(
      id: doc.id,
      locationTag: data['locationTag'] as String? ?? '',
      status: GameStatus.values.byName(data['status'] as String? ?? 'recruiting'),
      minPlayers: (data['minPlayers'] as num?)?.toInt() ?? 1,
      players: players,
      currentRound: (data['currentRound'] as num?)?.toInt() ?? 1,
      rulesDescription: data['rulesDescription'] as String? ?? '',
      mafiaCount: (data['mafiaCount'] as num?)?.toInt() ?? 1,
      recruitmentUnlockThreshold: (data['recruitmentUnlockThreshold'] as num?)?.toDouble() ?? 0.2,
      executionWindow: Duration(seconds: (data['executionWindowSeconds'] as num?)?.toInt() ?? 3600),
      dailyCutoffTime: Duration(seconds: (data['dailyCutoffSeconds'] as num?)?.toInt() ?? 17 * 3600),
      eliminationMethodDescription: data['eliminationMethodDescription'] as String?,
      eliminationSignalExecuted: data['eliminationSignalExecuted'] as bool? ?? false,
      eliminationSignalConfirmed: data['eliminationSignalConfirmed'] as bool? ?? false,
      recruitmentSignDescription: data['recruitmentSignDescription'] as String?,
      recruitmentSignExecuted: data['recruitmentSignExecuted'] as bool? ?? false,
      recruitmentSignConfirmed: data['recruitmentSignConfirmed'] as bool? ?? false,
      winner: (data['winner'] as String?) == null
          ? null
          : GameWinner.values.byName(data['winner'] as String),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// The viewer's own record — unredacted, straight from the true doc.
  Player _playerFromTrueDoc(String id, Map<String, dynamic> data) {
    return Player(
      id: id,
      name: data['name'] as String? ?? '',
      role: PlayerRole.values.byName(data['role'] as String? ?? 'villager'),
      voteWeight: (data['voteWeight'] as num?)?.toInt() ?? _startingVoteWeight,
      isActive: data['isActive'] as bool? ?? true,
      recruiterId: data['recruiterId'] as String?,
      recruitedPlayerIds: (data['recruitedPlayerIds'] as List<dynamic>?)?.cast<String>() ?? const [],
      wasUnmasked: data['wasUnmasked'] as bool? ?? false,
      pendingRecruiterId: data['pendingRecruiterId'] as String?,
      hasLeft: data['hasLeft'] as bool? ?? false,
      joinedAt: (data['joinedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Any other player's record — from the redacted `publicPlayers` mirror,
  /// with [roleOverride] applying a cell-link reveal from `cellViews` when
  /// present. Recruiter/recruit chain and pending recruitment offers are
  /// never exposed about *other* players, same as
  /// `LocalGameRepository._publicView`.
  Player _playerFromPublicDoc(String id, Map<String, dynamic>? data, {String? roleOverride}) {
    final safeData = data ?? const <String, dynamic>{};
    return Player(
      id: id,
      name: safeData['name'] as String? ?? '',
      role: PlayerRole.values.byName(roleOverride ?? safeData['role'] as String? ?? 'villager'),
      voteWeight: _startingVoteWeight,
      isActive: safeData['isActive'] as bool? ?? true,
      wasUnmasked: safeData['wasUnmasked'] as bool? ?? false,
      hasLeft: safeData['hasLeft'] as bool? ?? false,
      joinedAt: (safeData['joinedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  @override
  Stream<List<MafiaThreadEntry>> watchMafiaThread({
    required String gameId,
    required String viewerId,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> proposeElimination({
    required String gameId,
    required String authorId,
    required String method,
    required String targetPlayerId,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> acceptEliminationProposal({
    required String gameId,
    required String proposalId,
    required String playerId,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> executeElimination({
    required String gameId,
    required String proposalId,
    required String playerId,
  }) =>
      throw UnimplementedError();

  @override
  Future<bool> acknowledgeEliminationSignal({
    required String gameId,
    required String playerId,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> sendMafiaMessage({
    required String gameId,
    required String authorId,
    required String text,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> setMemberActive({
    required String gameId,
    required String playerId,
    required bool isActive,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> logObservation({
    required String gameId,
    required String authorId,
    required String text,
    String? targetPlayerId,
  }) =>
      throw UnimplementedError();

  @override
  Stream<List<Observation>> watchObservations({
    required String gameId,
    required String viewerId,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> castVote({
    required String gameId,
    required String voterId,
    required String targetPlayerId,
  }) =>
      throw UnimplementedError();

  @override
  Stream<List<Vote>> watchCurrentRoundVotes(String gameId) =>
      throw UnimplementedError();

  @override
  Stream<List<Vote>> watchVoteHistory(String gameId) => throw UnimplementedError();

  @override
  Future<void> resolveVotesForDay(String gameId) => throw UnimplementedError();

  @override
  Future<void> proposeRecruitment({
    required String gameId,
    required String recruiterId,
    required String targetPlayerId,
    required String sign,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> acceptRecruitmentProposal({
    required String gameId,
    required String proposalId,
    required String playerId,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> executeRecruitment({
    required String gameId,
    required String proposalId,
    required String playerId,
  }) =>
      throw UnimplementedError();

  @override
  Future<bool> respondToRecruitment({
    required String gameId,
    required String playerId,
    required bool accept,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<GameMoment>> fetchUnacknowledgedMoments({
    required String gameId,
    required String playerId,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> acknowledgeAllMoments({
    required String gameId,
    required String playerId,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<GameMoment>> fetchAllMoments({
    required String gameId,
    required String playerId,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> recordReentry({
    required String gameId,
    required String playerId,
  }) =>
      throw UnimplementedError();
}
