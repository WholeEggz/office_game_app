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
/// `LocalGameRepository`'s per-viewer role redaction directly. Milestone 3
/// built the read-only slice (createGame/addPlayer/watchGames/
/// watchVisiblePlayers); Milestone 4 adds the rest of the game-truth
/// inventory — voting, elimination/recruitment lifecycle, unmasking,
/// leaveGame/setMemberActive/sendMafiaMessage/logObservation — plus the
/// per-player moments bookkeeping, which is plain rule-gated Firestore
/// reads/writes rather than a Cloud Function (see firestore.rules'
/// `moments` comment).
///
/// Still missing, deliberately deferred to Milestone 5: the 1-hour
/// execution-window auto-lapse, the 24h mafia-inactive auto-reactivation,
/// and the daily-cutoff auto-resolve are all `dart:async Timer`s in
/// `LocalGameRepository` that only fire while that process is alive — a
/// real deployment needs Cloud Scheduler / scheduled functions instead.
/// `watchGame` (the debug role switcher's full unredacted roster) also
/// stays unimplemented — no client can safely read every player's true
/// doc under this architecture, debug-only or not; that needs its own
/// answer, not attempted here.
class FirebaseGameRepository implements GameRepository {
  FirebaseGameRepository({FirebaseFirestore? firestore, FirebaseFunctions? functions})
      : _db = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> get _games => _db.collection('games');

  /// Calls [name] and translates the validation-failure codes every
  /// Cloud Function in this inventory uses ('failed-precondition',
  /// 'not-found', 'already-exists') into a [StateError] — matching
  /// `LocalGameRepository`, which throws `StateError` for every one of
  /// these same validation failures, and preserving the `on StateError`
  /// handlers already in the UI (role_switcher_screen.dart,
  /// player_entry_screen.dart) without leaking Firebase-specific
  /// exception types past this seam.
  Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> data) async {
    try {
      final result = await _functions.httpsCallable(name).call<Map<String, dynamic>>(data);
      return result.data;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'already-exists' || e.code == 'failed-precondition' || e.code == 'not-found') {
        throw StateError(e.message ?? e.code);
      }
      rethrow;
    }
  }

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
    final result = await _call('createGame', {
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
    final gameId = result['gameId'] as String;
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
    await _call('addPlayer', {'gameId': gameId, 'playerId': playerId, 'name': name});
    return Player(id: playerId, name: name, role: PlayerRole.villager, joinedAt: DateTime.now());
  }

  @override
  Future<void> leaveGame({
    required String gameId,
    required String playerId,
  }) async {
    await _call('leaveGame', {'gameId': gameId, 'playerId': playerId});
  }

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

  Vote _voteFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return Vote(
      id: doc.id,
      gameId: doc.reference.parent.parent!.id,
      voterId: data['voterId'] as String? ?? '',
      targetPlayerId: data['targetPlayerId'] as String? ?? '',
      round: (data['round'] as num?)?.toInt() ?? 1,
      weight: (data['weight'] as num?)?.toInt() ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Observation _observationFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return Observation(
      id: doc.id,
      gameId: doc.reference.parent.parent!.id,
      authorId: data['authorId'] as String? ?? '',
      targetPlayerId: data['targetPlayerId'] as String?,
      text: data['text'] as String? ?? '',
      round: (data['round'] as num?)?.toInt() ?? 1,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  MafiaThreadEntry _mafiaThreadEntryFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return MafiaThreadEntry(
      id: doc.id,
      gameId: doc.reference.parent.parent!.id,
      round: (data['round'] as num?)?.toInt() ?? 1,
      authorId: data['authorId'] as String? ?? '',
      type: MafiaThreadEntryType.values.byName(data['type'] as String? ?? 'message'),
      message: data['message'] as String?,
      proposedMethod: data['proposedMethod'] as String?,
      proposedTargetId: data['proposedTargetId'] as String?,
      acceptedByPlayerIds: (data['acceptedByPlayerIds'] as List<dynamic>?)?.cast<String>() ?? const [],
      agreedAt: (data['agreedAt'] as Timestamp?)?.toDate(),
      executedAt: (data['executedAt'] as Timestamp?)?.toDate(),
      executedByPlayerId: data['executedByPlayerId'] as String?,
      lapsed: data['lapsed'] as bool? ?? false,
      confirmedAt: (data['confirmedAt'] as Timestamp?)?.toDate(),
      recruitmentAccepted: data['recruitmentAccepted'] as bool?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  GameMoment _gameMomentFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return GameMoment(
      id: doc.id,
      gameId: doc.reference.parent.parent!.id,
      playerId: data['playerId'] as String? ?? '',
      type: GameMomentType.values.byName(data['type'] as String? ?? 'roundEnded'),
      round: (data['round'] as num?)?.toInt() ?? 1,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Wraps [stream], mapping a `permission-denied` [FirebaseException] to
  /// an empty-list emission instead of a stream error — the Firestore
  /// equivalent of `LocalGameRepository`'s "return an empty list for a
  /// viewer this isn't readable to" contract (`watchMafiaThread`'s doc:
  /// "Emits an empty list for any viewer who isn't a *current* mafia
  /// member"), since here that's enforced by a rule denial rather than an
  /// in-memory branch.
  Stream<List<T>> _emptyOnPermissionDenied<T>(Stream<List<T>> stream) {
    final controller = StreamController<List<T>>.broadcast();
    final sub = stream.listen(
      controller.add,
      onError: (Object error, StackTrace stackTrace) {
        if (error is FirebaseException && error.code == 'permission-denied') {
          controller.add(const []);
          return;
        }
        controller.addError(error, stackTrace);
      },
    );
    controller.onCancel = () => sub.cancel();
    return controller.stream;
  }

  @override
  Stream<List<MafiaThreadEntry>> watchMafiaThread({
    required String gameId,
    required String viewerId,
  }) {
    return _emptyOnPermissionDenied(
      _games.doc(gameId).collection('mafiaThread').snapshots().map(
            (snap) => snap.docs.map(_mafiaThreadEntryFromDoc).toList(),
          ),
    );
  }

  @override
  Future<void> proposeElimination({
    required String gameId,
    required String authorId,
    required String method,
    required String targetPlayerId,
  }) async {
    await _call('proposeElimination', {
      'gameId': gameId,
      'authorId': authorId,
      'method': method,
      'targetPlayerId': targetPlayerId,
    });
  }

  @override
  Future<void> acceptEliminationProposal({
    required String gameId,
    required String proposalId,
    required String playerId,
  }) async {
    await _call('acceptEliminationProposal', {
      'gameId': gameId,
      'proposalId': proposalId,
      'playerId': playerId,
    });
  }

  @override
  Future<void> executeElimination({
    required String gameId,
    required String proposalId,
    required String playerId,
  }) async {
    await _call('executeElimination', {
      'gameId': gameId,
      'proposalId': proposalId,
      'playerId': playerId,
    });
  }

  @override
  Future<bool> acknowledgeEliminationSignal({
    required String gameId,
    required String playerId,
  }) async {
    final result = await _call('acknowledgeEliminationSignal', {'gameId': gameId, 'playerId': playerId});
    return result['accepted'] as bool? ?? false;
  }

  @override
  Future<void> sendMafiaMessage({
    required String gameId,
    required String authorId,
    required String text,
  }) async {
    await _call('sendMafiaMessage', {'gameId': gameId, 'authorId': authorId, 'text': text});
  }

  @override
  Future<void> setMemberActive({
    required String gameId,
    required String playerId,
    required bool isActive,
  }) async {
    await _call('setMemberActive', {'gameId': gameId, 'playerId': playerId, 'isActive': isActive});
  }

  @override
  Future<void> logObservation({
    required String gameId,
    required String authorId,
    required String text,
    String? targetPlayerId,
  }) async {
    await _call('logObservation', {
      'gameId': gameId,
      'authorId': authorId,
      'text': text,
      'targetPlayerId': targetPlayerId,
    });
  }

  @override
  Stream<List<Observation>> watchObservations({
    required String gameId,
    required String viewerId,
  }) {
    return _emptyOnPermissionDenied(
      _games.doc(gameId).collection('observations').snapshots().map(
            (snap) => snap.docs.map(_observationFromDoc).toList(),
          ),
    );
  }

  @override
  Future<void> castVote({
    required String gameId,
    required String voterId,
    required String targetPlayerId,
  }) async {
    await _call('castVote', {'gameId': gameId, 'voterId': voterId, 'targetPlayerId': targetPlayerId});
  }

  /// Reactively re-filters `votes` by the game's *current* round, since
  /// the round advances over the life of this stream — mirrors
  /// `LocalGameRepository.watchCurrentRoundVotes`, which recomputes off
  /// both vote changes and game changes for the same reason.
  @override
  Stream<List<Vote>> watchCurrentRoundVotes(String gameId) {
    final gameRef = _games.doc(gameId);
    final controller = StreamController<List<Vote>>.broadcast();
    QuerySnapshot<Map<String, dynamic>>? votesSnap;
    int? currentRound;

    void emit() {
      final snap = votesSnap;
      if (snap == null || currentRound == null) return;
      controller.add(
        snap.docs.map(_voteFromDoc).where((v) => v.round == currentRound).toList(),
      );
    }

    final subs = <StreamSubscription>[
      gameRef.snapshots().listen((snap) {
        currentRound = (snap.data()?['currentRound'] as num?)?.toInt() ?? 1;
        emit();
      }, onError: controller.addError),
      gameRef.collection('votes').snapshots().listen((snap) {
        votesSnap = snap;
        emit();
      }, onError: controller.addError),
    ];

    controller.onCancel = () async {
      for (final sub in subs) {
        await sub.cancel();
      }
    };
    return controller.stream;
  }

  @override
  Stream<List<Vote>> watchVoteHistory(String gameId) {
    return _games.doc(gameId).collection('votes').snapshots().map(
          (snap) => snap.docs.map(_voteFromDoc).toList(),
        );
  }

  @override
  Future<void> resolveVotesForDay(String gameId) async {
    await _call('resolveVotesForDay', {'gameId': gameId});
  }

  @override
  Future<void> proposeRecruitment({
    required String gameId,
    required String recruiterId,
    required String targetPlayerId,
    required String sign,
  }) async {
    await _call('proposeRecruitment', {
      'gameId': gameId,
      'recruiterId': recruiterId,
      'targetPlayerId': targetPlayerId,
      'sign': sign,
    });
  }

  @override
  Future<void> acceptRecruitmentProposal({
    required String gameId,
    required String proposalId,
    required String playerId,
  }) async {
    await _call('acceptRecruitmentProposal', {
      'gameId': gameId,
      'proposalId': proposalId,
      'playerId': playerId,
    });
  }

  @override
  Future<void> executeRecruitment({
    required String gameId,
    required String proposalId,
    required String playerId,
  }) async {
    await _call('executeRecruitment', {
      'gameId': gameId,
      'proposalId': proposalId,
      'playerId': playerId,
    });
  }

  @override
  Future<bool> respondToRecruitment({
    required String gameId,
    required String playerId,
    required bool accept,
  }) async {
    final result = await _call('respondToRecruitment', {
      'gameId': gameId,
      'playerId': playerId,
      'accept': accept,
    });
    return result['accepted'] as bool? ?? false;
  }

  /// Plain rule-gated Firestore reads/writes, not Cloud Functions — per
  /// implementation_plan.md's Cloud Functions inventory: "per-player
  /// notification bookkeeping, not contested game state; a rule of
  /// playerId == request.auth.uid is sufficient." Filters/sorts client-side
  /// on a single equality read rather than a compound query, avoiding a
  /// composite-index requirement for what's always a small, per-player
  /// collection.
  @override
  Future<List<GameMoment>> fetchUnacknowledgedMoments({
    required String gameId,
    required String playerId,
  }) async {
    final snap = await _games
        .doc(gameId)
        .collection('moments')
        .where('playerId', isEqualTo: playerId)
        .get();
    final moments = snap.docs
        .where((doc) => doc.data()['acknowledged'] != true)
        .map(_gameMomentFromDoc)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return moments;
  }

  @override
  Future<void> acknowledgeAllMoments({
    required String gameId,
    required String playerId,
  }) async {
    final snap = await _games
        .doc(gameId)
        .collection('moments')
        .where('playerId', isEqualTo: playerId)
        .get();
    final batch = _db.batch();
    for (final doc in snap.docs) {
      if (doc.data()['acknowledged'] != true) {
        batch.update(doc.reference, {'acknowledged': true});
      }
    }
    await batch.commit();
  }

  @override
  Future<List<GameMoment>> fetchAllMoments({
    required String gameId,
    required String playerId,
  }) async {
    final snap = await _games
        .doc(gameId)
        .collection('moments')
        .where('playerId', isEqualTo: playerId)
        .get();
    final moments = snap.docs.map(_gameMomentFromDoc).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return moments;
  }

  @override
  Future<void> recordReentry({
    required String gameId,
    required String playerId,
  }) async {
    final gameRef = _games.doc(gameId);
    final gameSnap = await gameRef.get();
    final round = (gameSnap.data()?['currentRound'] as num?)?.toInt() ?? 1;
    await gameRef.collection('moments').add({
      'playerId': playerId,
      'type': 'reenteredCase',
      'round': round,
      'createdAt': FieldValue.serverTimestamp(),
      'acknowledged': false,
    });
  }
}
