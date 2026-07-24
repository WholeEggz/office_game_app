import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../design/colors.dart';
import '../../design/spacing.dart';
import '../../design/typography.dart';
import '../../domain/hints/hint_catalog.dart';
import '../../domain/hints/hint_context.dart';
import '../../domain/hints/hint_definition.dart';
import '../../domain/hints/hint_engine.dart';
import '../../domain/hints/static_hint_catalog.dart';
import '../../domain/models/game.dart';
import '../../domain/models/mafia_thread_entry.dart';
import '../../domain/models/observation.dart';
import '../../domain/models/player.dart';
import '../../domain/models/vote.dart';
import '../../domain/repositories/auth_service.dart';
import '../../domain/repositories/game_repository.dart';

/// Placeholder icon per hint id, swappable for hand-drawn art later —
/// callers only need to change this one mapping, everything else keys off
/// [HintDefinition.id] (or [StaticHintInfo.id] for the pre-game entries).
IconData _iconFor(String hintId) {
  switch (hintId) {
    case 'welcome_help':
      return PhosphorIconsLight.bookOpenText;
    case 'say_hello':
      return PhosphorIconsLight.handWaving;
    case 'notice_something':
      return PhosphorIconsLight.eye;
    case 'cast_first_vote':
      return PhosphorIconsLight.checkSquare;
    case 'vote_before_cutoff':
      return PhosphorIconsLight.clockCountdown;
    case 'mafia_thread_intro':
      return PhosphorIconsLight.chatsCircle;
    case 'elimination_ack_pending':
      return PhosphorIconsLight.warning;
    case 'recruitment_response_pending':
      return PhosphorIconsLight.envelopeOpen;
    case 'registration_location':
      return PhosphorIconsLight.mapPin;
    case 'case_list_location_sort':
      return PhosphorIconsLight.magnifyingGlass;
    case 'case_creation_restricted_location':
      return PhosphorIconsLight.lockKey;
    default:
      return PhosphorIconsLight.info;
  }
}

String _statusLabel(HintStatus status) {
  switch (status) {
    case HintStatus.completed:
      return 'Completed';
    case HintStatus.active:
      return 'Pending';
    case HintStatus.notYetRelevant:
      return 'Not started';
  }
}

Color _statusColor(HintStatus status) {
  switch (status) {
    case HintStatus.completed:
      return AppColors.brass;
    case HintStatus.active:
      return AppColors.sageText;
    case HintStatus.notYetRelevant:
      return AppColors.textMuted;
  }
}

/// The full tutorial progress list: every [hintCatalog] entry that applies
/// to this player, plus every [staticHintCatalog] entry (the pre-game
/// hints from registration/"Find your case"/case creation) — merged into
/// one list so "how far along am I" covers the whole journey, not just
/// what happened after joining this case. Opened from the tutorial
/// banner, or any time a player wants to check how far along they are.
class HintProgressScreen extends StatefulWidget {
  final String gameId;
  final String playerId;

  const HintProgressScreen({super.key, required this.gameId, required this.playerId});

  @override
  State<HintProgressScreen> createState() => _HintProgressScreenState();
}

class _HintProgressScreenState extends State<HintProgressScreen> {
  late final Stream<Game> _gameStream;
  late final Stream<List<Player>> _playersStream;
  late final Stream<List<Observation>> _observationsStream;
  late final Stream<List<Vote>> _votesStream;
  late final Stream<List<Vote>> _voteHistoryStream;
  late final Stream<List<MafiaThreadEntry>> _mafiaThreadStream;
  late final Stream<Set<String>> _dismissedHintIdsStream;

  /// The pre-game hints are normally dismissed once and don't change while
  /// this screen is open (dismissing one happens on a different screen,
  /// earlier in the flow) — a one-time fetch is enough, unlike the
  /// in-game hints above, which stay live via streams. Not `late final`
  /// because the debug reset button (below) needs to refresh it after
  /// clearing the static dismissal ledger.
  late Future<Set<String>> _dismissedStaticHintIds;

  Future<Set<String>> _fetchDismissedStaticHints() =>
      context.read<AuthService>().fetchDismissedHints().catchError((_) => <String>{});

  /// Debug/testing convenience: clears every hint dismissal — both the
  /// per-game ledger (`GameRepository`) and the pre-game one
  /// (`AuthService`) — so the whole tutorial sequence can be replayed
  /// without starting a fresh case or identity. Doesn't touch hints whose
  /// completion is derived from real game state (e.g. having actually
  /// voted); only "Got it" dismissals are resettable this way.
  Future<void> _resetAllHints() async {
    final repo = context.read<GameRepository>();
    final auth = context.read<AuthService>();
    try {
      await repo.clearDismissedHints(gameId: widget.gameId, viewerId: widget.playerId);
      await auth.clearDismissedHints();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't reset hints — try again.")),
      );
      return;
    }
    if (!mounted) return;
    // The in-game half refreshes on its own via _dismissedHintIdsStream;
    // the static half needs a manual re-fetch since it's a one-time Future.
    // (Block body, not `=>`, matters here: an arrow body would make this
    // closure return the assigned Future itself, which setState rejects.)
    setState(() {
      _dismissedStaticHintIds = _fetchDismissedStaticHints();
    });
  }

  @override
  void initState() {
    super.initState();
    final repo = context.read<GameRepository>();
    _gameStream = repo.watchGame(widget.gameId).asBroadcastStream();
    // `Game.players` off `watchGame` is only populated via the
    // emulator-only `debugRoster` collection (see firebase_game_repository
    // .dart) — always empty against a real Firebase backend, which made
    // `game.playerById(...)` always return null and this whole screen
    // render as an empty `SizedBox.shrink()` for real players. Sourcing
    // `self` from `watchVisiblePlayers` instead — same as `game_screen
    // .dart` does — fixes that for good.
    _playersStream = repo
        .watchVisiblePlayers(gameId: widget.gameId, viewerId: widget.playerId)
        .asBroadcastStream();
    _observationsStream = repo
        .watchObservations(gameId: widget.gameId, viewerId: widget.playerId)
        .asBroadcastStream();
    _votesStream = repo.watchCurrentRoundVotes(widget.gameId).asBroadcastStream();
    _voteHistoryStream = repo.watchVoteHistory(widget.gameId).asBroadcastStream();
    _mafiaThreadStream = repo
        .watchMafiaThread(gameId: widget.gameId, viewerId: widget.playerId)
        .asBroadcastStream();
    _dismissedHintIdsStream = repo
        .watchDismissedHintIds(gameId: widget.gameId, viewerId: widget.playerId)
        .asBroadcastStream();
    _dismissedStaticHintIds = _fetchDismissedStaticHints();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Getting started')),
      body: Column(
        children: [
          if (kDebugMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                0,
              ),
              child: Center(
                child: OutlinedButton(
                  onPressed: _resetAllHints,
                  child: const Text('Reset all hint statuses (debug)'),
                ),
              ),
            ),
          Expanded(child: _buildList(context)),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    return FutureBuilder<Set<String>>(
      future: _dismissedStaticHintIds,
      builder: (context, staticDismissedSnap) {
        final dismissedStaticIds = staticDismissedSnap.data ?? const {};
        final staticEntries = [
          for (final info in staticHintCatalog)
            (
              id: info.id,
              message: info.message,
              status: dismissedStaticIds.contains(info.id)
                  ? HintStatus.completed
                  : HintStatus.active,
            ),
        ];
        return StreamBuilder<Game>(
          stream: _gameStream,
          builder: (context, gameSnap) {
            final game = gameSnap.data;
            if (game == null) {
              return const Center(child: CircularProgressIndicator(color: AppColors.brass));
            }
            return StreamBuilder<List<Player>>(
              stream: _playersStream,
              builder: (context, playersSnap) {
                final players = playersSnap.data;
                if (players == null) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.brass),
                  );
                }
                Player? self;
                for (final p in players) {
                  if (p.id == widget.playerId) {
                    self = p;
                    break;
                  }
                }
                if (self == null) return const SizedBox.shrink();
                return _HintProgressBody(
                  game: game,
                  self: self,
                  staticEntries: staticEntries,
                  observationsStream: _observationsStream,
                  votesStream: _votesStream,
                  voteHistoryStream: _voteHistoryStream,
                  mafiaThreadStream: _mafiaThreadStream,
                  dismissedHintIdsStream: _dismissedHintIdsStream,
                );
              },
            );
          },
        );
      },
    );
  }
}

/// Split out from `_HintProgressScreenState.build` purely to keep the
/// nesting depth sane once `self` needed its own `StreamBuilder<List<Player>>`
/// on top of the pre-existing four — same data, same merge logic as before.
class _HintProgressBody extends StatelessWidget {
  final Game game;
  final Player self;
  final List<({String id, String message, HintStatus status})> staticEntries;
  final Stream<List<Observation>> observationsStream;
  final Stream<List<Vote>> votesStream;
  final Stream<List<Vote>> voteHistoryStream;
  final Stream<List<MafiaThreadEntry>> mafiaThreadStream;
  final Stream<Set<String>> dismissedHintIdsStream;

  const _HintProgressBody({
    required this.game,
    required this.self,
    required this.staticEntries,
    required this.observationsStream,
    required this.votesStream,
    required this.voteHistoryStream,
    required this.mafiaThreadStream,
    required this.dismissedHintIdsStream,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Observation>>(
      stream: observationsStream,
      builder: (context, obsSnap) => StreamBuilder<List<Vote>>(
        stream: votesStream,
        builder: (context, votesSnap) => StreamBuilder<List<Vote>>(
          stream: voteHistoryStream,
          builder: (context, historySnap) => StreamBuilder<List<MafiaThreadEntry>>(
            stream: mafiaThreadStream,
            builder: (context, threadSnap) => StreamBuilder<Set<String>>(
              stream: dismissedHintIdsStream,
              builder: (context, dismissedSnap) {
                final hintContext = HintContext(
                  game: game,
                  self: self,
                  observations: obsSnap.data ?? const [],
                  currentRoundVotes: votesSnap.data ?? const [],
                  voteHistory: historySnap.data ?? const [],
                  mafiaThread: threadSnap.data ?? const [],
                  dismissedHintIds: dismissedSnap.data ?? const {},
                );
                // Every hint that applies to this player — onboarding and
                // recurring alike. A recurring one's status can cycle back
                // to Pending next round even after showing Completed here;
                // that's expected, not a bug.
                final dynamicEntries = allHintStatuses(hintCatalog, hintContext)
                    .where((e) => e.$1.appliesTo(hintContext))
                    .map((e) => (
                          id: e.$1.id,
                          message: e.$1.message(hintContext),
                          status: e.$2,
                        ));
                // Static (pre-game) entries first — they happened earlier
                // in the journey than anything below.
                final entries = [...staticEntries, ...dynamicEntries];
                return ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return _HintTile(
                      id: entry.id,
                      status: entry.status,
                      message: entry.message,
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _HintTile extends StatelessWidget {
  final String id;
  final HintStatus status;
  final String message;

  const _HintTile({required this.id, required this.status, required this.message});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.borderHairline, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_iconFor(id), size: 22, color: color),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message, style: AppTypography.bodySmall.copyWith(color: color)),
                const SizedBox(height: AppSpacing.xs),
                Text(_statusLabel(status), style: AppTypography.dataSmall.copyWith(color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
