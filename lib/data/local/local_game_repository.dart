import 'dart:async';
import 'dart:math';

import 'package:uuid/uuid.dart';

import '../../domain/models/game.dart';
import '../../domain/models/game_moment.dart';
import '../../domain/models/mafia_thread_entry.dart';
import '../../domain/models/observation.dart';
import '../../domain/models/player.dart';
import '../../domain/models/vote.dart';
import '../../domain/repositories/game_repository.dart';

/// Every villager's starting vote weight (section 5) — also the value shown
/// for any player other than the viewer in [_publicView], since a real,
/// changing number would leak exactly the thing the erosion mechanic is
/// supposed to keep ambiguous (see that method's doc for why).
const _startingVoteWeight = 3;

/// Concept doc section 7: a mafia member marked inactive (sick leave,
/// vacation) is absent "for 24 hours / until end of day" — an expiring
/// real-world absence, not a standing opt-out someone has to remember to
/// undo.
const _inactivityAutoResetWindow = Duration(hours: 24);

/// Fans multiple void-event streams into one, since Phase 1a intentionally
/// has no rxdart dependency for something this small.
Stream<void> _merge(Iterable<Stream<void>> streams) {
  late final StreamController<void> controller;
  final subscriptions = <StreamSubscription<void>>[];
  controller = StreamController<void>.broadcast(
    onListen: () {
      for (final s in streams) {
        subscriptions.add(s.listen(controller.add));
      }
    },
    onCancel: () async {
      for (final sub in subscriptions) {
        await sub.cancel();
      }
      subscriptions.clear();
    },
  );
  return controller.stream;
}

class _GameRecord {
  Game game;
  final List<MafiaThreadEntry> mafiaThread = [];
  final List<Observation> observations = [];
  final List<Vote> votes = [];

  /// Every [GameMoment] ever recorded for this game, across all players —
  /// filtered per-viewer in [LocalGameRepository.fetchUnacknowledgedMoments].
  /// Kept forever (like votes, unlike the ephemeral observation log) since
  /// there's no reason a "you won" or "good catch" moment should ever
  /// silently expire before someone gets to see it.
  final List<GameMoment> moments = [];
  final Set<String> acknowledgedMomentIds = {};

  /// Player ids who've already gotten a round-scoped moment (a vote
  /// reward, a mafia hit, an unmask, a recruitment, ...) *this* round —
  /// cleared every time a round resolves. [LocalGameRepository._recordMoment]
  /// maintains this so the generic [GameMomentType.roundEnded] fallback
  /// only ever goes to players nothing more specific happened to, without
  /// every call site having to track and pass that exclusion set around
  /// by hand.
  final Set<String> notifiedThisRound = {};

  /// Pending lapse timers, keyed by proposal id — cancelled the moment a
  /// proposal is executed or the round ends first.
  final lapseTimers = <String, Timer>{};

  /// Auto-reactivation timers for mafia members marked inactive, keyed by
  /// player id — cancelled early if they reactivate themselves or leave
  /// the game first.
  final inactivityTimers = <String, Timer>{};

  /// Fires [Game.dailyCutoffTime] resolution on its own — rescheduled for
  /// the next occurrence every time a round actually resolves, by
  /// whatever means (this timer, the manual debug button, or a target
  /// acknowledging a signal).
  Timer? dailyCutoffTimer;

  final gameChanges = StreamController<void>.broadcast();
  final threadChanges = StreamController<void>.broadcast();
  final observationChanges = StreamController<void>.broadcast();
  final voteChanges = StreamController<void>.broadcast();

  /// Each viewer's own block list for this game — a per-viewer
  /// preference, not game truth, so it's keyed by viewer rather than
  /// shared. Reports aren't stored at all: nothing in Local mode ever
  /// reads them back (there's no moderator view), so [reportPlayer]
  /// exists here purely for interface parity with Firebase, which does
  /// persist them for later review.
  final Map<String, Set<String>> blockedByViewer = {};
  final blockChanges = StreamController<void>.broadcast();

  /// Normalized (trimmed, lowercased) passphrase words for a restricted
  /// case — null for an unrestricted one. Deliberately not exposed via
  /// the public [Game] model; [LocalGameRepository.verifyPassphrase] and
  /// [LocalGameRepository.addPlayer] are the only things that ever read
  /// this.
  Set<String>? passphraseWords;

  _GameRecord(this.game);
}

/// Dart's `Set` doesn't override `==` to do element-wise comparison (two
/// different `Set` instances are never `==`, even with identical
/// contents) — this is the actual passphrase-match check everywhere a
/// comparison is needed, instead of relying on `set1 == set2`.
bool _sameWords(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);

/// Trimmed + lowercased, so "Tiger", " tiger ", and "TIGER" all match —
/// same case/whitespace-insensitive treatment this codebase already gives
/// case names and player names.
Set<String> _normalizeWords(Iterable<String> words) => words
    .map((w) => w.trim().toLowerCase())
    .where((w) => w.isNotEmpty)
    .toSet();

/// Full in-memory implementation of every rule in
/// `office_game_concept_season1.md`: vote-weight erosion, elimination
/// signaling, mafia coordination with active/inactive handling,
/// recruitment, unmasking, and the 3-round observation log. Everything
/// resets when the app restarts — that's the point of Phase 1a.
class LocalGameRepository implements GameRepository {
  final _uuid = const Uuid();
  final _games = <String, _GameRecord>{};

  /// Fires whenever any game is created or changes — separate from each
  /// [_GameRecord]'s own `gameChanges`, since [watchGames] needs to react
  /// across the whole collection, including games that don't exist yet at
  /// the time it starts listening.
  final _gamesListChanges = StreamController<void>.broadcast();

  _GameRecord _record(String gameId) {
    final record = _games[gameId];
    if (record == null) throw StateError('Unknown game $gameId');
    return record;
  }

  Player _requireCurrentMafia(Game game, String playerId) {
    final player = game.playerById(playerId);
    if (player == null ||
        player.role != PlayerRole.mafia ||
        player.wasUnmasked ||
        player.hasLeft) {
      throw StateError('$playerId is not a current mafia member of ${game.id}');
    }
    return player;
  }

  /// A closed case takes no further actions of any kind (section 1 — no
  /// win/end condition existed before this; once one fires, it's final).
  void _requireGameNotEnded(Game game) {
    if (game.status == GameStatus.ended) {
      throw StateError('This case is closed');
    }
  }

  /// Checks whether [record.game] just crossed a win condition and, if so,
  /// closes it. Villagers win the instant no living mafia member remains
  /// (unmasked or left); mafia win the instant they reach parity or a
  /// majority against living villagers. "Living" excludes anyone who's
  /// [Player.hasLeft] — a departed member isn't a threat or a vote
  /// anymore, on either side. Call this after anything that can change
  /// who's mafia, who's a villager, or who's still around: unmasking,
  /// recruitment, and leaving.
  void _checkForGameEnd(_GameRecord record) {
    final game = record.game;
    if (game.status != GameStatus.active) return;
    final livingMafia = game.livingMafia.length;
    final livingVillagers = game.livingVillagers.length;
    GameWinner? winner;
    if (livingMafia == 0) {
      winner = GameWinner.villagers;
    } else if (livingMafia >= livingVillagers) {
      winner = GameWinner.mafia;
    }
    if (winner != null) {
      _replaceGame(record, game.copyWith(status: GameStatus.ended, winner: winner));
      // "Ever mafia" (not just currently-mafia) mirrors the finale
      // screen's own "THE MAFIA" list — someone unmasked earlier or who
      // left mid-game is still on the mafia side for win/loss purposes.
      for (final p in game.players) {
        final everMafia = p.role == PlayerRole.mafia || p.wasUnmasked;
        final onWinningSide =
            winner == GameWinner.mafia ? everMafia : !everMafia;
        _recordMoment(
          record,
          p.id,
          onWinningSide ? GameMomentType.finaleWin : GameMomentType.finaleLoss,
          record.game.currentRound,
          countsAsRoundActivity: false,
        );
      }
    }
  }

  void _replaceGame(_GameRecord record, Game newGame) {
    record.game = newGame;
    record.gameChanges.add(null);
    _gamesListChanges.add(null);
  }

  void _replacePlayer(_GameRecord record, String playerId, Player Function(Player) update) {
    final players = record.game.players
        .map((p) => p.id == playerId ? update(p) : p)
        .toList(growable: false);
    _replaceGame(record, record.game.copyWith(players: players));
  }

  /// [countsAsRoundActivity] marks [playerId] in [_GameRecord.notifiedThisRound]
  /// so the generic [GameMomentType.roundEnded] fallback skips them for
  /// the rest of this round — true for anything that happened *within* a
  /// round (a vote reward, a hit, a recruitment...), false for moments
  /// that aren't about "what happened this round" at all ([GameMomentType.finaleWin]/
  /// [GameMomentType.finaleLoss], [GameMomentType.joinedCase],
  /// [GameMomentType.reenteredCase]) — those shouldn't suppress an
  /// otherwise-accurate "nothing else happened" for the same round.
  void _recordMoment(
    _GameRecord record,
    String playerId,
    GameMomentType type,
    int round, {
    bool countsAsRoundActivity = true,
  }) {
    record.moments.add(GameMoment(
      id: _uuid.v4(),
      gameId: record.game.id,
      playerId: playerId,
      type: type,
      round: round,
      createdAt: DateTime.now(),
    ));
    if (countsAsRoundActivity) {
      record.notifiedThisRound.add(playerId);
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
    bool isRestricted = false,
    List<String>? passphraseWords,
  }) async {
    // A case name can be reused once the earlier case with that name has
    // ended, but two simultaneously open cases sharing a name would be
    // ambiguous in "Find your case" — same case/whitespace-insensitive
    // collision rule as player names within a single roster.
    final normalizedTag = locationTag.trim().toLowerCase();
    final nameTaken = _games.values.any((r) =>
        r.game.status != GameStatus.ended && r.game.locationTag.trim().toLowerCase() == normalizedTag);
    if (nameTaken) {
      throw StateError('A case named "$locationTag" is already open — choose a different name.');
    }
    final normalizedPassphrase = isRestricted ? _normalizeWords(passphraseWords ?? const []) : null;
    if (isRestricted && normalizedPassphrase!.length != 3) {
      throw StateError('A restricted case needs exactly 3 distinct passphrase words.');
    }
    final creator = Player(
      id: creatorId,
      name: creatorName,
      role: PlayerRole.villager,
      joinedAt: DateTime.now(),
    );
    final game = Game(
      id: _uuid.v4(),
      locationTag: locationTag,
      minPlayers: minPlayers,
      players: [creator],
      rulesDescription: rulesDescription,
      mafiaCount: mafiaCount,
      recruitmentUnlockThreshold: recruitmentUnlockThreshold,
      executionWindow: executionWindow,
      dailyCutoffTime: dailyCutoffTime,
      createdAt: DateTime.now(),
      isRestricted: isRestricted,
      creatorId: creatorId,
    );
    final record = _GameRecord(game)..passphraseWords = normalizedPassphrase;
    _games[game.id] = record;
    _recordMoment(record, creatorId, GameMomentType.joinedCase, game.currentRound,
        countsAsRoundActivity: false);
    // Covers the edge case where minPlayers is already met the moment the
    // creator joins (e.g. minPlayers: 1) — the same rule as [addPlayer]:
    // roles get drawn the instant the roster reaches minPlayers, no
    // separate manual "start" step required.
    _autoStartIfReady(record);
    _gamesListChanges.add(null);
    return record.game;
  }

  @override
  Future<Player> addPlayer({
    required String gameId,
    required String playerId,
    required String name,
    List<String>? passphraseWords,
  }) async {
    final record = _record(gameId);
    _requireGameNotEnded(record.game);
    // Checked before anything else — a wrong or missing passphrase should
    // learn nothing about the roster (not even "that name's taken").
    if (record.game.isRestricted &&
        !_sameWords(_normalizeWords(passphraseWords ?? const []), record.passphraseWords!)) {
      throw StateError('Incorrect passphrase.');
    }
    if (record.game.playerById(playerId) != null) {
      throw StateError('$playerId has already joined this game');
    }
    // Two coworkers really can share a first name in real life, but within
    // a single roster that's confusing (who's "Bob" in the observation
    // log?) rather than useful — so names are unique per game, even though
    // identities themselves are not (case/whitespace-insensitive so "bob"
    // and " Bob " both collide with "Bob").
    final normalized = name.trim().toLowerCase();
    final nameTaken = record.game.players.any((p) => p.name.trim().toLowerCase() == normalized);
    if (nameTaken) {
      throw StateError('"$name" is already in this game');
    }
    final player = Player(
      id: playerId,
      name: name,
      role: PlayerRole.villager,
      joinedAt: DateTime.now(),
    );
    _replaceGame(record, record.game.copyWith(players: [...record.game.players, player]));
    _recordMoment(record, playerId, GameMomentType.joinedCase, record.game.currentRound,
        countsAsRoundActivity: false);
    // Real players never see a manual "start the game" button (only the
    // debug role switcher has one) — without this, a game joined entirely
    // through the real player flow would sit in `recruiting` forever, every
    // player permanently defaulted to villager, since nothing else would
    // ever call `startGame`.
    _autoStartIfReady(record);
    return player;
  }

  @override
  Future<bool> verifyPassphrase({
    required String gameId,
    required List<String> words,
  }) async {
    final record = _record(gameId);
    if (!record.game.isRestricted) return true;
    return _sameWords(_normalizeWords(words), record.passphraseWords!);
  }

  @override
  Future<List<String>?> fetchGamePassphrase({
    required String gameId,
    required String playerId,
  }) async {
    final record = _record(gameId);
    if (!record.game.isRestricted || record.game.creatorId != playerId) return null;
    return record.passphraseWords!.toList();
  }

  @override
  Future<void> leaveGame({
    required String gameId,
    required String playerId,
  }) async {
    final record = _record(gameId);
    if (record.game.playerById(playerId) == null) {
      throw StateError('$playerId is not in game $gameId');
    }
    _replacePlayer(record, playerId, (p) => p.copyWith(hasLeft: true));
    record.inactivityTimers.remove(playerId)?.cancel();
    // A departing mafia member can immediately satisfy an unagreed
    // proposal or recruitment that was only waiting on them — same
    // reasoning as setMemberActive marking someone inactive (harmless
    // no-op scan if the leaver was a villager).
    for (final entry in List.of(record.mafiaThread)) {
      if ((entry.type == MafiaThreadEntryType.proposal ||
              entry.type == MafiaThreadEntryType.recruitment) &&
          entry.agreedAt == null &&
          !entry.lapsed) {
        _maybeMarkAgreed(record, entry.id);
      }
    }
    record.threadChanges.add(null);
    // A departure can itself cross a win condition — e.g. the last
    // remaining mafia member walks away, or enough villagers leave that
    // the mafia left behind are suddenly a majority.
    _checkForGameEnd(record);
  }

  /// Draws roles the moment the roster reaches [Game.minPlayers] — a no-op
  /// if the game isn't still `recruiting` or hasn't reached that size yet.
  /// Always assigns at least one mafia member ([_activateGame]'s clamp),
  /// regardless of what [Game.mafiaCount] asks for.
  void _autoStartIfReady(_GameRecord record) {
    final game = record.game;
    if (game.status == GameStatus.recruiting && game.players.length >= game.minPlayers) {
      _activateGame(record);
    }
  }

  void _activateGame(_GameRecord record) {
    final game = record.game;
    final mafiaCount = game.mafiaCount.clamp(1, game.players.length);
    final shuffled = [...game.players]..shuffle(Random());
    final mafiaIds = shuffled.take(mafiaCount).map((p) => p.id).toSet();
    final players = game.players
        .map((p) => mafiaIds.contains(p.id) ? p.copyWith(role: PlayerRole.mafia) : p)
        .toList();
    _replaceGame(record, game.copyWith(status: GameStatus.active, players: players));
    // Covers the degenerate case of a case created with no room for any
    // villager at all (e.g. minPlayers 1) — mafia have already "won" the
    // instant there's no one left to threaten.
    _checkForGameEnd(record);
    _scheduleDailyCutoff(record);
  }

  /// Schedules (or reschedules, cancelling any timer already pending) an
  /// automatic [_resolveRound] for the next time [Game.dailyCutoffTime]
  /// comes around — "the next occurrence strictly after now," so a round
  /// that starts after today's cutoff already passed waits for tomorrow's
  /// instead of firing immediately. A no-op once the game isn't `active`
  /// (recruiting has no rounds; an ended game has nothing left to resolve).
  void _scheduleDailyCutoff(_GameRecord record) {
    record.dailyCutoffTimer?.cancel();
    final game = record.game;
    if (game.status != GameStatus.active) return;
    final now = DateTime.now();
    var next = DateTime(now.year, now.month, now.day).add(game.dailyCutoffTime);
    if (!next.isAfter(now)) {
      next = next.add(const Duration(days: 1));
    }
    record.dailyCutoffTimer = Timer(next.difference(now), () {
      // Re-check on fire, not just at scheduling time — the game may have
      // ended or the round may have already resolved by some other path
      // in the meantime.
      if (record.game.status == GameStatus.active) {
        _resolveRound(record);
      }
    });
  }

  @override
  Future<void> startGame(String gameId) async {
    final record = _record(gameId);
    final game = record.game;
    // In practice [addPlayer]/[createGame] already trigger this the moment
    // the roster reaches minPlayers, so this is usually a no-op by the
    // time anything calls it explicitly (e.g. the debug role switcher's
    // "Start the game" button) — idempotent rather than an error, since
    // "start a game that's already started" isn't a real mistake to guard
    // against, just a race between two triggers for the same rule.
    if (game.status != GameStatus.recruiting) return;
    if (game.players.length < game.minPlayers) {
      throw StateError(
        'Need at least ${game.minPlayers} players to start (have ${game.players.length})',
      );
    }
    _activateGame(record);
  }

  @override
  Stream<Game> watchGame(String gameId) async* {
    final record = _record(gameId);
    yield record.game;
    yield* record.gameChanges.stream.map((_) => record.game);
  }

  @override
  Stream<List<Game>> watchGames({required String viewerId}) async* {
    List<Game> snapshot() => _games.values
        .map((record) => record.game.copyWith(players: _visiblePlayers(record.game, viewerId)))
        .toList();
    yield snapshot();
    yield* _gamesListChanges.stream.map((_) => snapshot());
  }

  /// Only ever called for players other than the viewer (see
  /// [_visiblePlayers] — the viewer's own record is returned unredacted).
  /// A live weight number for someone else would leak role: elimination and
  /// villager-vote erosion only ever subtract from a non-mafia target (a
  /// mafia target gets unmasked instead), so a visibly lowered weight is
  /// silent proof "this player has been confirmed not mafia" — the opposite
  /// of the ambiguity the erosion system was designed to preserve (concept
  /// doc section 5/6: the *target* alone is meant to discover their own
  /// loss, not the whole roster). So every other player's weight is always
  /// shown at the untouched starting value.
  Player _publicView(Player p, {required bool revealRole}) {
    return Player(
      id: p.id,
      name: p.name,
      role: revealRole ? p.role : PlayerRole.villager,
      voteWeight: _startingVoteWeight,
      isActive: p.isActive,
      wasUnmasked: p.wasUnmasked,
      joinedAt: p.joinedAt,
      // Recruiter/recruit chain and pending recruitment offers are never
      // exposed about *other* players — cell structure (design pillar #4)
      // limits knowledge to one hop, enforced here rather than in the UI.
    );
  }

  List<Player> _visiblePlayers(Game game, String viewerId) {
    final viewer = game.playerById(viewerId);
    return game.players.map((p) {
      if (p.id == viewerId) return p;
      final knowsCellLink = viewer != null &&
          viewer.role == PlayerRole.mafia &&
          (p.id == viewer.recruiterId || viewer.recruitedPlayerIds.contains(p.id));
      final revealRole = p.wasUnmasked || p.role == PlayerRole.villager || knowsCellLink;
      return _publicView(p, revealRole: revealRole);
    }).toList();
  }

  @override
  Stream<List<Player>> watchVisiblePlayers({
    required String gameId,
    required String viewerId,
  }) async* {
    final record = _record(gameId);
    yield _visiblePlayers(record.game, viewerId);
    yield* record.gameChanges.stream.map((_) => _visiblePlayers(record.game, viewerId));
  }

  List<MafiaThreadEntry> _visibleThread(Game game, List<MafiaThreadEntry> thread, String viewerId) {
    final viewer = game.playerById(viewerId);
    if (viewer == null || viewer.role != PlayerRole.mafia || viewer.wasUnmasked) {
      return const [];
    }
    return List.unmodifiable(thread);
  }

  @override
  Stream<List<MafiaThreadEntry>> watchMafiaThread({
    required String gameId,
    required String viewerId,
  }) async* {
    final record = _record(gameId);
    List<MafiaThreadEntry> current() => _visibleThread(record.game, record.mafiaThread, viewerId);
    yield current();
    // A player's own unmasking arrives as a game change, not a thread
    // change — merge both so access is revoked the instant it happens.
    yield* _merge([record.threadChanges.stream, record.gameChanges.stream])
        .map((_) => current());
  }

  /// Marks a proposal or recruitment agreed the moment every active mafia
  /// member has accepted it, and arms the execution-window timer. Either
  /// way — section 6 — this is when the method/sign (never the target)
  /// goes in front of every villager as a forewarning, well before anyone
  /// actually executes it. No vote weight moves and no offer reaches its
  /// target yet; that's execution.
  void _maybeMarkAgreed(_GameRecord record, String proposalId) {
    final index = record.mafiaThread.indexWhere((e) => e.id == proposalId);
    if (index == -1) return;
    final entry = record.mafiaThread[index];
    if (entry.type != MafiaThreadEntryType.proposal &&
        entry.type != MafiaThreadEntryType.recruitment) {
      return;
    }
    if (entry.agreedAt != null || entry.executedAt != null || entry.lapsed) return;

    final requiredIds = record.game.activeMafia.map((p) => p.id).toSet();
    final acceptedIds = entry.acceptedByPlayerIds.toSet();
    if (requiredIds.isEmpty || !requiredIds.every(acceptedIds.contains)) return;

    record.mafiaThread[index] = entry.copyWith(agreedAt: DateTime.now());
    if (entry.type == MafiaThreadEntryType.proposal) {
      _replaceGame(
        record,
        record.game.copyWith(
          eliminationMethodDescription: entry.proposedMethod,
          eliminationSignalExecuted: false,
          eliminationSignalConfirmed: false,
        ),
      );
    } else {
      _replaceGame(
        record,
        record.game.copyWith(
          recruitmentSignDescription: entry.proposedMethod,
          recruitmentSignExecuted: false,
          recruitmentSignConfirmed: false,
        ),
      );
    }
    record.lapseTimers[proposalId] = Timer(record.game.executionWindow, () {
      _lapseIfArmed(record, proposalId);
      record.threadChanges.add(null);
    });
  }

  /// If [proposalId] is still agreed-but-not-executed, marks it lapsed —
  /// the opportunity is lost, nothing is applied. No-op otherwise (already
  /// executed, already lapsed, or never agreed).
  void _lapseIfArmed(_GameRecord record, String proposalId) {
    final index = record.mafiaThread.indexWhere((e) => e.id == proposalId);
    if (index == -1) return;
    final entry = record.mafiaThread[index];
    if (entry.agreedAt == null || entry.executedAt != null || entry.lapsed) return;
    record.mafiaThread[index] = entry.copyWith(lapsed: true);
    record.lapseTimers.remove(proposalId);
  }

  @override
  Future<void> proposeElimination({
    required String gameId,
    required String authorId,
    required String method,
    required String targetPlayerId,
  }) async {
    final record = _record(gameId);
    _requireGameNotEnded(record.game);
    _requireCurrentMafia(record.game, authorId);
    final target = record.game.playerById(targetPlayerId);
    if (target == null || target.role != PlayerRole.villager || target.hasLeft) {
      throw StateError('Elimination target must be a current villager');
    }
    final entry = MafiaThreadEntry(
      id: _uuid.v4(),
      gameId: gameId,
      round: record.game.currentRound,
      authorId: authorId,
      type: MafiaThreadEntryType.proposal,
      proposedMethod: method,
      proposedTargetId: targetPlayerId,
      acceptedByPlayerIds: [authorId],
      createdAt: DateTime.now(),
    );
    record.mafiaThread.add(entry);
    _maybeMarkAgreed(record, entry.id);
    record.threadChanges.add(null);
  }

  @override
  Future<void> acceptEliminationProposal({
    required String gameId,
    required String proposalId,
    required String playerId,
  }) async {
    final record = _record(gameId);
    _requireGameNotEnded(record.game);
    _requireCurrentMafia(record.game, playerId);
    final index = record.mafiaThread.indexWhere((e) => e.id == proposalId);
    if (index == -1) throw StateError('Unknown proposal $proposalId');
    final entry = record.mafiaThread[index];
    if (entry.agreedAt == null && !entry.acceptedByPlayerIds.contains(playerId)) {
      record.mafiaThread[index] =
          entry.copyWith(acceptedByPlayerIds: [...entry.acceptedByPlayerIds, playerId]);
    }
    _maybeMarkAgreed(record, proposalId);
    record.threadChanges.add(null);
  }

  @override
  Future<void> executeElimination({
    required String gameId,
    required String proposalId,
    required String playerId,
  }) async {
    final record = _record(gameId);
    _requireGameNotEnded(record.game);
    _requireCurrentMafia(record.game, playerId);
    final index = record.mafiaThread.indexWhere((e) => e.id == proposalId);
    if (index == -1) throw StateError('Unknown proposal $proposalId');
    var entry = record.mafiaThread[index];
    if (entry.agreedAt == null) {
      throw StateError('This proposal has not been agreed by every active member yet');
    }
    if (entry.executedAt != null) {
      throw StateError('This proposal has already been executed');
    }
    final windowClosed =
        entry.lapsed || DateTime.now().isAfter(entry.agreedAt!.add(record.game.executionWindow));
    if (windowClosed) {
      // The scheduled Timer may not have fired yet (event-loop timing), but
      // the window has practically closed either way.
      record.lapseTimers.remove(proposalId)?.cancel();
      _lapseIfArmed(record, proposalId);
      record.threadChanges.add(null);
      throw StateError('The window to execute this proposal has already closed');
    }

    record.lapseTimers.remove(proposalId)?.cancel();
    entry = entry.copyWith(executedAt: DateTime.now());
    record.mafiaThread[index] = entry;

    final target = record.game.playerById(entry.proposedTargetId!);
    if (target != null) {
      _replacePlayer(record, target.id, (p) => p.copyWith(voteWeight: max(0, p.voteWeight - 1)));
      _recordMoment(
        record,
        target.id,
        GameMomentType.targetedByMafia,
        record.game.currentRound,
      );
    }
    _replaceGame(record, record.game.copyWith(eliminationSignalExecuted: true));
    record.threadChanges.add(null);
  }

  @override
  Future<bool> acknowledgeEliminationSignal({
    required String gameId,
    required String playerId,
  }) async {
    final record = _record(gameId);
    _requireGameNotEnded(record.game);
    if (record.game.playerById(playerId) == null) {
      throw StateError('$playerId is not in game $gameId');
    }
    final index = record.mafiaThread.indexWhere((e) =>
        e.type == MafiaThreadEntryType.proposal &&
        e.executedAt != null &&
        e.confirmedAt == null &&
        e.proposedTargetId == playerId);
    if (index == -1) return false;

    record.mafiaThread[index] = record.mafiaThread[index].copyWith(confirmedAt: DateTime.now());
    _replaceGame(record, record.game.copyWith(eliminationSignalConfirmed: true));
    record.threadChanges.add(null);
    // The real target discovering the mark is, narratively, the end of
    // the day — resolve the round the same way the manual debug button
    // would, instead of waiting for someone to press it separately.
    _resolveRound(record);
    return true;
  }

  @override
  Future<void> sendMafiaMessage({
    required String gameId,
    required String authorId,
    required String text,
  }) async {
    final record = _record(gameId);
    _requireGameNotEnded(record.game);
    _requireCurrentMafia(record.game, authorId);
    record.mafiaThread.add(MafiaThreadEntry(
      id: _uuid.v4(),
      gameId: gameId,
      round: record.game.currentRound,
      authorId: authorId,
      type: MafiaThreadEntryType.message,
      message: text,
      createdAt: DateTime.now(),
    ));
    record.threadChanges.add(null);
  }

  @override
  Future<void> setMemberActive({
    required String gameId,
    required String playerId,
    required bool isActive,
  }) async {
    final record = _record(gameId);
    _requireGameNotEnded(record.game);
    _requireCurrentMafia(record.game, playerId);
    _replacePlayer(record, playerId, (p) => p.copyWith(isActive: isActive));
    record.inactivityTimers.remove(playerId)?.cancel();
    if (!isActive) {
      record.inactivityTimers[playerId] = Timer(_inactivityAutoResetWindow, () {
        _replacePlayer(record, playerId, (p) => p.copyWith(isActive: true));
        record.inactivityTimers.remove(playerId);
        record.threadChanges.add(null);
      });
    }
    // Marking someone inactive can immediately satisfy an unagreed
    // proposal or recruitment that was only waiting on them.
    for (final entry in List.of(record.mafiaThread)) {
      if ((entry.type == MafiaThreadEntryType.proposal ||
              entry.type == MafiaThreadEntryType.recruitment) &&
          entry.agreedAt == null &&
          !entry.lapsed) {
        _maybeMarkAgreed(record, entry.id);
      }
    }
    record.threadChanges.add(null);
  }

  @override
  Future<void> logObservation({
    required String gameId,
    required String authorId,
    required String text,
    String? targetPlayerId,
  }) async {
    final record = _record(gameId);
    _requireGameNotEnded(record.game);
    if (record.game.playerById(authorId) == null) {
      throw StateError('$authorId is not in game $gameId');
    }
    record.observations.add(Observation(
      id: _uuid.v4(),
      gameId: gameId,
      authorId: authorId,
      targetPlayerId: targetPlayerId,
      text: text,
      round: record.game.currentRound,
      createdAt: DateTime.now(),
    ));
    record.observationChanges.add(null);
  }

  @override
  Stream<List<Observation>> watchObservations({
    required String gameId,
    required String viewerId,
  }) async* {
    final record = _record(gameId);
    List<Observation> current() => List.unmodifiable(record.observations);
    yield current();
    yield* record.observationChanges.stream.map((_) => current());
  }

  @override
  Future<void> castVote({
    required String gameId,
    required String voterId,
    required String targetPlayerId,
  }) async {
    final record = _record(gameId);
    _requireGameNotEnded(record.game);
    final voter = record.game.playerById(voterId);
    if (voter == null) throw StateError('$voterId is not in game $gameId');
    if (voter.hasLeft) throw StateError('$voterId has left this game and can no longer vote');
    final target = record.game.playerById(targetPlayerId);
    if (target == null) throw StateError('$targetPlayerId is not in game $gameId');
    if (target.hasLeft) {
      throw StateError('$targetPlayerId has left this game and can no longer be voted for');
    }
    record.votes.removeWhere(
      (v) => v.voterId == voterId && v.round == record.game.currentRound,
    );
    record.votes.add(Vote(
      id: _uuid.v4(),
      gameId: gameId,
      voterId: voterId,
      targetPlayerId: targetPlayerId,
      round: record.game.currentRound,
      weight: voter.voteWeight,
      createdAt: DateTime.now(),
    ));
    record.voteChanges.add(null);
  }

  @override
  Stream<List<Vote>> watchCurrentRoundVotes(String gameId) async* {
    final record = _record(gameId);
    List<Vote> current() =>
        record.votes.where((v) => v.round == record.game.currentRound).toList();
    yield current();
    yield* record.voteChanges.stream.map((_) => current());
  }

  @override
  Stream<List<Vote>> watchVoteHistory(String gameId) async* {
    final record = _record(gameId);
    List<Vote> current() => List.unmodifiable(record.votes);
    yield current();
    yield* record.voteChanges.stream.map((_) => current());
  }

  @override
  Future<void> resolveVotesForDay(String gameId) async {
    final record = _record(gameId);
    _requireGameNotEnded(record.game);
    _resolveRound(record);
  }

  /// Tallies the current round's votes and advances to the next one —
  /// shared by the manual debug "resolve" button and by the real target
  /// acknowledging an executed elimination signal, since that's meant to
  /// end the day the same way. Anyone [_recordMoment] already marked in
  /// [_GameRecord.notifiedThisRound] (a vote reward, a mafia hit, a
  /// recruitment...) is skipped for the generic [GameMomentType.roundEnded]
  /// fallback below, so nobody gets both a specific moment and "the round
  /// ended" for the same round.
  void _resolveRound(_GameRecord record) {
    final game = record.game;
    final currentRound = game.currentRound;
    final roundVotes = record.votes.where((v) => v.round == currentRound).toList();

    // Tally by each voter's *current* weight, not the snapshot on the Vote
    // record — a same-day elimination can erode a voter's weight after
    // they've already cast their vote.
    final tally = <String, int>{};
    for (final vote in roundVotes) {
      final liveWeight = game.playerById(vote.voterId)?.voteWeight ?? 0;
      tally[vote.targetPlayerId] = (tally[vote.targetPlayerId] ?? 0) + liveWeight;
    }

    String? winnerId;
    var bestWeight = 0;
    tally.forEach((targetId, weight) {
      if (weight > bestWeight) {
        bestWeight = weight;
        winnerId = targetId;
      }
    });

    var players = game.players;
    if (winnerId != null && bestWeight > 0) {
      final target = game.playerById(winnerId!)!;
      if (target.role == PlayerRole.mafia && !target.wasUnmasked) {
        // Correctly caught a mafia member: unmask them and reward every
        // voter who picked them (section 5, 9).
        final rewardedVoterIds = roundVotes
            .where((v) => v.targetPlayerId == winnerId)
            .map((v) => v.voterId)
            .toSet();
        players = players.map((p) {
          if (p.id == winnerId) {
            return p.copyWith(role: PlayerRole.villager, wasUnmasked: true);
          }
          if (rewardedVoterIds.contains(p.id)) {
            return p.copyWith(voteWeight: p.voteWeight + 1);
          }
          return p;
        }).toList();
        for (final voterId in rewardedVoterIds) {
          _recordMoment(record, voterId, GameMomentType.correctVoteReward, currentRound);
        }
        // Everyone else still finds out an Informant was caught this
        // round, just without personal credit — the target themselves is
        // covered by the "UNMASKED" stamp ceremony instead, not a moment.
        for (final p in game.players) {
          if (p.id == winnerId || rewardedVoterIds.contains(p.id)) continue;
          _recordMoment(record, p.id, GameMomentType.mafiaUnmaskedByOthers, currentRound);
        }
      } else {
        // Voted for a villager instead: the vote still lands, it just
        // erodes their weight the same way a mafia elimination would —
        // voting is never a no-op, only who it lands on differs.
        players = players.map((p) {
          if (p.id == winnerId) {
            return p.copyWith(voteWeight: max(0, p.voteWeight - 1));
          }
          return p;
        }).toList();
        _recordMoment(record, winnerId!, GameMomentType.targetedByVillagers, currentRound);
      }
    }

    // Every mafia member who made it through this round without being the
    // one caught — feeds the track record's survived-as-mafia count and
    // streak. `p.id == winnerId` is excluded explicitly: when the winning
    // target *was* mafia, they're deliberately left out of
    // `notifiedThisRound` above (the UNMASKED ceremony covers them instead
    // of a moment), so without this check they'd still read as
    // `role == mafia, wasUnmasked == false` here and wrongly get credited
    // with surviving the very round they were caught in.
    for (final p in game.players) {
      if (record.notifiedThisRound.contains(p.id) || p.id == winnerId) continue;
      if (p.role == PlayerRole.mafia && !p.wasUnmasked && !p.hasLeft) {
        _recordMoment(record, p.id, GameMomentType.survivedRoundAsMafia, currentRound);
      }
    }

    // The generic fallback: everyone still in the game who didn't already
    // get something more specific this round, so a round never passes
    // with zero acknowledgement for anyone.
    for (final p in game.players) {
      if (!record.notifiedThisRound.contains(p.id)) {
        _recordMoment(record, p.id, GameMomentType.roundEnded, currentRound);
      }
    }
    record.notifiedThisRound.clear();

    final nextRound = currentRound + 1;
    // Unlike observations, votes are kept forever (not just this round) —
    // the voting history is exactly what's useful for spotting mafia
    // patterns (design intent: this info matters more the longer it's
    // visible, unlike the deliberately ephemeral observation log).
    // Observation log retention (section 10): entries older than 3 rounds
    // are actually deleted, not just hidden.
    record.observations.removeWhere((o) => nextRound - o.round >= 3);

    // The round ending is the other half of the execution deadline (1 hour,
    // or the round ending — whichever is first): any proposal or
    // recruitment that was agreed but never executed this round lapses now.
    for (final entry in List.of(record.mafiaThread)) {
      if (entry.round == currentRound &&
          (entry.type == MafiaThreadEntryType.proposal ||
              entry.type == MafiaThreadEntryType.recruitment) &&
          entry.agreedAt != null &&
          entry.executedAt == null &&
          !entry.lapsed) {
        record.lapseTimers.remove(entry.id)?.cancel();
        _lapseIfArmed(record, entry.id);
      }
    }

    _replaceGame(
      record,
      game.copyWith(
        players: players,
        currentRound: nextRound,
        // A fresh round starts with no lingering signal from the last one.
        clearEliminationMethodDescription: true,
        eliminationSignalExecuted: false,
        eliminationSignalConfirmed: false,
        clearRecruitmentSignDescription: true,
        recruitmentSignExecuted: false,
        recruitmentSignConfirmed: false,
      ),
    );
    record.observationChanges.add(null);
    record.voteChanges.add(null);
    record.threadChanges.add(null);
    // Covers an unmask that just happened in this same resolution (above)
    // and, when this was reached via respondToRecruitment, a recruitment
    // acceptance that happened just before this call — both can cross a
    // win condition.
    _checkForGameEnd(record);
    // Whatever just triggered this resolution (the cutoff timer itself,
    // the manual debug button, or a target acknowledging a signal), the
    // new round gets its own fresh cutoff — a no-op if the game just
    // ended above.
    _scheduleDailyCutoff(record);
  }

  /// True while a recruitment is anywhere in its lifecycle short of being
  /// resolved (responded to, or lapsed) — recruitment has a single slot,
  /// mirroring how elimination has a single active signal.
  bool _hasActiveRecruitment(_GameRecord record) {
    return record.mafiaThread.any((e) =>
        e.type == MafiaThreadEntryType.recruitment && !e.lapsed && e.confirmedAt == null);
  }

  @override
  Future<void> proposeRecruitment({
    required String gameId,
    required String recruiterId,
    required String targetPlayerId,
    required String sign,
  }) async {
    final record = _record(gameId);
    final game = record.game;
    _requireGameNotEnded(game);
    if (!game.recruitmentUnlocked) {
      throw StateError('Recruitment is not yet unlocked in game $gameId');
    }
    if (_hasActiveRecruitment(record)) {
      throw StateError('Only one recruitment can be in progress at a time');
    }
    _requireCurrentMafia(game, recruiterId);
    final target = game.playerById(targetPlayerId);
    if (target == null || target.role != PlayerRole.villager || target.hasLeft) {
      throw StateError('Recruitment target must be a current villager');
    }
    final entry = MafiaThreadEntry(
      id: _uuid.v4(),
      gameId: gameId,
      round: game.currentRound,
      authorId: recruiterId,
      type: MafiaThreadEntryType.recruitment,
      proposedMethod: sign,
      proposedTargetId: targetPlayerId,
      acceptedByPlayerIds: [recruiterId],
      createdAt: DateTime.now(),
    );
    record.mafiaThread.add(entry);
    _maybeMarkAgreed(record, entry.id);
    record.threadChanges.add(null);
  }

  @override
  Future<void> acceptRecruitmentProposal({
    required String gameId,
    required String proposalId,
    required String playerId,
  }) async {
    final record = _record(gameId);
    _requireGameNotEnded(record.game);
    _requireCurrentMafia(record.game, playerId);
    final index = record.mafiaThread.indexWhere((e) => e.id == proposalId);
    if (index == -1) throw StateError('Unknown proposal $proposalId');
    final entry = record.mafiaThread[index];
    if (entry.agreedAt == null && !entry.acceptedByPlayerIds.contains(playerId)) {
      record.mafiaThread[index] =
          entry.copyWith(acceptedByPlayerIds: [...entry.acceptedByPlayerIds, playerId]);
    }
    _maybeMarkAgreed(record, proposalId);
    record.threadChanges.add(null);
  }

  @override
  Future<void> executeRecruitment({
    required String gameId,
    required String proposalId,
    required String playerId,
  }) async {
    final record = _record(gameId);
    _requireGameNotEnded(record.game);
    _requireCurrentMafia(record.game, playerId);
    final index = record.mafiaThread.indexWhere((e) => e.id == proposalId);
    if (index == -1) throw StateError('Unknown proposal $proposalId');
    var entry = record.mafiaThread[index];
    if (entry.type != MafiaThreadEntryType.recruitment) {
      throw StateError('$proposalId is not a recruitment proposal');
    }
    if (entry.agreedAt == null) {
      throw StateError('This recruitment has not been agreed by every active member yet');
    }
    if (entry.executedAt != null) {
      throw StateError('This recruitment has already been executed');
    }
    final windowClosed =
        entry.lapsed || DateTime.now().isAfter(entry.agreedAt!.add(record.game.executionWindow));
    if (windowClosed) {
      record.lapseTimers.remove(proposalId)?.cancel();
      _lapseIfArmed(record, proposalId);
      record.threadChanges.add(null);
      throw StateError('The window to approach this recruit has already closed');
    }

    record.lapseTimers.remove(proposalId)?.cancel();
    entry = entry.copyWith(executedAt: DateTime.now(), executedByPlayerId: playerId);
    record.mafiaThread[index] = entry;

    // Only now does the target actually see an offer waiting for them.
    _replacePlayer(
      record,
      entry.proposedTargetId!,
      (p) => p.copyWith(pendingRecruiterId: playerId),
    );
    _replaceGame(record, record.game.copyWith(recruitmentSignExecuted: true));
    record.threadChanges.add(null);
  }

  @override
  Future<bool> respondToRecruitment({
    required String gameId,
    required String playerId,
    required bool accept,
  }) async {
    final record = _record(gameId);
    _requireGameNotEnded(record.game);
    if (record.game.playerById(playerId) == null) {
      throw StateError('$playerId is not in game $gameId');
    }
    final target = record.game.playerById(playerId)!;
    // Mirrors acknowledgeEliminationSignal: everyone sees the same "did
    // this happen to you?" prompt, but it's a silent no-op for anyone who
    // wasn't actually the one approached — the sign is public, the target
    // never is (section 6).
    if (target.pendingRecruiterId == null) {
      return false;
    }
    final recruiterId = target.pendingRecruiterId!;

    final entryIndex = record.mafiaThread.indexWhere((e) =>
        e.type == MafiaThreadEntryType.recruitment &&
        e.proposedTargetId == playerId &&
        e.executedAt != null &&
        e.confirmedAt == null);
    if (entryIndex != -1) {
      record.mafiaThread[entryIndex] = record.mafiaThread[entryIndex].copyWith(
        confirmedAt: DateTime.now(),
        recruitmentAccepted: accept,
      );
    }

    final players = record.game.players.map((p) {
      if (p.id == playerId) {
        return accept
            ? p.copyWith(
                role: PlayerRole.mafia,
                recruiterId: recruiterId,
                clearPendingRecruiterId: true,
              )
            : p.copyWith(clearPendingRecruiterId: true);
      }
      if (accept && p.id == recruiterId) {
        return p.copyWith(recruitedPlayerIds: [...p.recruitedPlayerIds, playerId]);
      }
      return p;
    }).toList();
    if (accept) {
      // The recruiter here is whoever actually executed the approach
      // (recorded on the target's pendingRecruiterId), not necessarily
      // whoever originally proposed it — same distinction the Wire itself
      // already makes.
      final round = record.game.currentRound;
      _recordMoment(record, recruiterId, GameMomentType.recruitmentExecuted, round);
      _recordMoment(record, playerId, GameMomentType.recruitedSwitchSides, round);
    }
    _replaceGame(
      record,
      record.game.copyWith(players: players, recruitmentSignConfirmed: true),
    );
    record.threadChanges.add(null);
    // Mirrors acknowledgeEliminationSignal: the real target responding is
    // narratively the end of the day, so resolve the round the same way.
    _resolveRound(record);
    return true;
  }

  @override
  Future<List<GameMoment>> fetchUnacknowledgedMoments({
    required String gameId,
    required String playerId,
  }) async {
    final record = _record(gameId);
    return record.moments
        .where((m) => m.playerId == playerId && !record.acknowledgedMomentIds.contains(m.id))
        .toList();
  }

  @override
  Future<void> acknowledgeAllMoments({
    required String gameId,
    required String playerId,
  }) async {
    final record = _record(gameId);
    for (final m in record.moments) {
      if (m.playerId == playerId) {
        record.acknowledgedMomentIds.add(m.id);
      }
    }
  }

  @override
  Future<List<GameMoment>> fetchAllMoments({
    required String gameId,
    required String playerId,
  }) async {
    final record = _record(gameId);
    return record.moments.where((m) => m.playerId == playerId).toList();
  }

  @override
  Future<void> recordReentry({
    required String gameId,
    required String playerId,
  }) async {
    final record = _record(gameId);
    _recordMoment(record, playerId, GameMomentType.reenteredCase, record.game.currentRound,
        countsAsRoundActivity: false);
  }

  // Deliberately not gated by _requireGameNotEnded: reporting/blocking are
  // safety actions, not gameplay actions — there's no reason a case ending
  // should stop someone from reporting something they noticed right at
  // the end, or from blocking a player whose name they still see in that
  // now-closed case's history.

  @override
  Future<void> reportPlayer({
    required String gameId,
    required String reporterId,
    required String targetPlayerId,
    required String reason,
    String? observationId,
  }) async {
    final record = _record(gameId);
    if (record.game.playerById(reporterId) == null) {
      throw StateError('$reporterId is not in game $gameId');
    }
    if (record.game.playerById(targetPlayerId) == null) {
      throw StateError('$targetPlayerId is not in game $gameId');
    }
    // Nothing stores or reads this back in Local mode — no moderator view
    // exists for a single-device, no-backend session. This method exists
    // purely so the interface behaves identically to Firebase's, which
    // does persist reports for later review.
  }

  @override
  Future<void> blockPlayer({
    required String gameId,
    required String viewerId,
    required String blockedPlayerId,
  }) async {
    final record = _record(gameId);
    record.blockedByViewer.putIfAbsent(viewerId, () => {}).add(blockedPlayerId);
    record.blockChanges.add(null);
  }

  @override
  Future<void> unblockPlayer({
    required String gameId,
    required String viewerId,
    required String blockedPlayerId,
  }) async {
    final record = _record(gameId);
    record.blockedByViewer[viewerId]?.remove(blockedPlayerId);
    record.blockChanges.add(null);
  }

  @override
  Stream<Set<String>> watchBlockedPlayerIds({
    required String gameId,
    required String viewerId,
  }) async* {
    final record = _record(gameId);
    Set<String> current() => Set.unmodifiable(record.blockedByViewer[viewerId] ?? const {});
    yield current();
    yield* record.blockChanges.stream.map((_) => current());
  }
}
