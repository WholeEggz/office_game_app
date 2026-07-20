import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../design/colors.dart';
import '../../design/graphics.dart';
import '../../design/spacing.dart';
import '../../design/typography.dart';
import '../../domain/models/game.dart';
import '../../domain/models/mafia_thread_entry.dart';
import '../../domain/models/observation.dart';
import '../../domain/models/player.dart';
import '../../domain/models/vote.dart';
import '../../domain/repositories/game_repository.dart';
import '../common/dossier_card.dart';
import '../common/noir_copy.dart';
import '../common/role_badge.dart';
import '../common/vote_weight_pill.dart';
import '../help/help_screen.dart';
import '../stats/track_record_screen.dart';
import 'moment_dialog.dart';

/// Runs a repository action that may throw a [StateError] from a race
/// condition or a stale view of shared state (someone else's action beat
/// this one, a window closed, etc.), turning it into a SnackBar instead of
/// an uncaught crash. Pass [message] explicitly when the repository's own
/// error text would leak information a redacted view is supposed to hide
/// (e.g. cell-structure secrecy in the elimination/recruitment target
/// pickers); everywhere else the default (the real message) is safe and
/// more useful to show verbatim.
Future<void> _runGuarded(
  BuildContext context,
  Future<void> Function() action, {
  String? message,
}) async {
  try {
    await action();
  } on StateError catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message ?? e.message)),
    );
  }
}

/// "17:00" style formatting for a time-of-day [Duration] since midnight
/// (e.g. [Game.dailyCutoffTime]).
String _formatTimeOfDay(Duration timeOfDay) {
  final hours = timeOfDay.inHours % 24;
  final minutes = timeOfDay.inMinutes % 60;
  return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
}

/// Confirms, then calls [GameRepository.leaveGame] — irreversible in
/// Phase 1a (no rejoin flow), so this is worth a real "are you sure"
/// rather than a one-tap action sitting right next to routine buttons.
Future<void> _confirmLeave(
  BuildContext context,
  GameRepository repo,
  String gameId,
  String playerId,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Leave this case?'),
      content: const Text(
        "You'll stop counting toward votes and elimination/recruitment "
        "targets. This can't be undone — there's no way to rejoin.",
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('Leave', style: TextStyle(color: AppColors.crimsonText)),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  if (!context.mounted) return;
  await _runGuarded(context, () => repo.leaveGame(gameId: gameId, playerId: playerId));
}

/// Prompts for a reason, then calls [GameRepository.reportPlayer] — shared
/// by the roster (reporting a player generally) and the observation log
/// (reporting a specific entry, [observationId] set). Recorded for later
/// review; doesn't hide anything on its own — pairs with blocking (see the
/// roster's Block/Unblock menu item) for an immediate effect.
Future<void> _showReportDialog(
  BuildContext context, {
  required GameRepository repo,
  required String gameId,
  required String reporterId,
  required String targetPlayerId,
  required String targetName,
  String? observationId,
}) async {
  final reason = await showDialog<String>(
    context: context,
    builder: (dialogContext) => _ReportDialog(targetName: targetName),
  );
  if (reason == null || reason.isEmpty) return;
  if (!context.mounted) return;
  await _runGuarded(
    context,
    () => repo.reportPlayer(
      gameId: gameId,
      reporterId: reporterId,
      targetPlayerId: targetPlayerId,
      reason: reason,
      observationId: observationId,
    ),
  );
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Report submitted.')),
  );
}

/// The report-reason prompt's content, as its own `State` so the
/// [TextEditingController] is disposed when this widget is actually removed
/// from the tree (i.e. once the dialog's dismiss animation finishes) rather
/// than the instant `showDialog` returns — disposing it eagerly races that
/// animation, since the still-closing dialog can rebuild the TextField
/// against an already-disposed controller and crash.
class _ReportDialog extends StatefulWidget {
  final String targetName;

  const _ReportDialog({required this.targetName});

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Report ${widget.targetName}'),
      content: TextField(
        controller: _reasonController,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(hintText: 'What happened?'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_reasonController.text.trim()),
          child: const Text('Submit'),
        ),
      ],
    );
  }
}

/// A single player's own view into a running game — everything here is
/// scoped to `playerId` via `GameRepository`'s redacted streams, never the
/// full roster (that's `RoleSwitcherScreen`'s debug-only job).
class GameScreen extends StatefulWidget {
  final String gameId;
  final String playerId;

  const GameScreen({super.key, required this.gameId, required this.playerId});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  bool _lastKnownUnmasked = false;
  bool _unmaskDialogShown = false;
  StreamSubscription<Game>? _momentsSubscription;
  bool _checkingMoments = false;
  // Set on every build (see `build()`) so `_checkForMoments` always has the
  // latest role to hand to `presentMoments` — a moment check can fire well
  // after this screen first mounted (e.g. a later round's outcome), and a
  // recruited player's role can genuinely change in between.
  PlayerRole? _selfRole;

  // Created once and reused for the lifetime of this screen. Calling
  // `repo.watchXyz(...)` directly inside `build()` would hand a brand-new
  // Stream to StreamBuilder on every rebuild, tearing down and rebuilding
  // the underlying subscription each time — a real source of dropped
  // updates (e.g. a mafia proposal pinging a subscription that's mid-teardown).
  late final Stream<List<Player>> _playersStream;
  late final Stream<Game> _gameStream;
  late final Stream<List<MafiaThreadEntry>> _mafiaThreadStream;
  late final Stream<List<Observation>> _observationsStream;
  late final Stream<List<Vote>> _votesStream;
  late final Stream<List<Vote>> _voteHistoryStream;
  late final Stream<Set<String>> _blockedPlayerIdsStream;

  @override
  void initState() {
    super.initState();
    final repo = context.read<GameRepository>();
    // `.asBroadcastStream()` matters here, not just style: the repository's
    // streams are single-subscription (from async* generators), which
    // allow exactly one `.listen()` ever. An unkeyed conditional widget
    // (e.g. `_MafiaSection`) can get its State torn down and recreated by
    // Flutter's list reconciliation, and the fresh State re-listening to
    // the same cached single-subscription stream throws "Stream has
    // already been listened to." Broadcasting removes that trap.
    _playersStream = repo
        .watchVisiblePlayers(gameId: widget.gameId, viewerId: widget.playerId)
        .asBroadcastStream();
    _gameStream = repo.watchGame(widget.gameId).asBroadcastStream();
    _mafiaThreadStream = repo
        .watchMafiaThread(gameId: widget.gameId, viewerId: widget.playerId)
        .asBroadcastStream();
    _observationsStream = repo
        .watchObservations(gameId: widget.gameId, viewerId: widget.playerId)
        .asBroadcastStream();
    _votesStream = repo.watchCurrentRoundVotes(widget.gameId).asBroadcastStream();
    _voteHistoryStream = repo.watchVoteHistory(widget.gameId).asBroadcastStream();
    _blockedPlayerIdsStream = repo
        .watchBlockedPlayerIds(gameId: widget.gameId, viewerId: widget.playerId)
        .asBroadcastStream();
  }

  void _trackUnmasking(Player self) {
    if (!self.wasUnmasked) return;
    if (_lastKnownUnmasked) return;
    _lastKnownUnmasked = true;
    if (_unmaskDialogShown) return;
    _unmaskDialogShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Unmasked',
        barrierColor: Colors.black54,
        transitionDuration: Duration.zero,
        pageBuilder: (context, _, __) =>
            Center(child: _UnmaskStamp(onDismiss: () => Navigator.of(context).pop())),
      );
    });
  }

  /// Subscribed once, the first time this screen's dashboard is built.
  /// Runs an initial check right away (catches up on anything that
  /// happened while this player wasn't looking — including, for a brand
  /// new join, the `joinedCase` moment that now carries the role reveal
  /// that used to be its own separate ceremony screen), then again on
  /// every subsequent game change — which also covers the case where the
  /// moment belongs to whoever's live in the app right now, e.g. the
  /// mafia member who just executed a recruitment themselves.
  void _startWatchingForMoments(PlayerRole selfRole) {
    _selfRole = selfRole;
    if (_momentsSubscription != null) return;
    _checkForMoments();
    _momentsSubscription = _gameStream.listen((_) => _checkForMoments());
  }

  Future<void> _checkForMoments() async {
    if (_checkingMoments) return;
    _checkingMoments = true;
    try {
      final repo = context.read<GameRepository>();
      final moments = await repo.fetchUnacknowledgedMoments(
        gameId: widget.gameId,
        playerId: widget.playerId,
      );
      if (moments.isEmpty) return;
      await repo.acknowledgeAllMoments(gameId: widget.gameId, playerId: widget.playerId);
      if (!mounted) return;
      await presentMoments(context, selectMomentsToShow(moments), selfRole: _selfRole!);
    } finally {
      _checkingMoments = false;
    }
  }

  @override
  void dispose() {
    _momentsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Player>>(
      stream: _playersStream,
      builder: (context, snapshot) {
        final players = snapshot.data;
        Player? self;
        if (players != null) {
          for (final p in players) {
            if (p.id == widget.playerId) {
              self = p;
              break;
            }
          }
        }
        // Covers both "no snapshot yet" and "publicPlayers snapshot arrived
        // but the syncPlayerViews trigger for this viewer's own doc hasn't
        // landed yet" — the latter is a real, legitimate intermediate state
        // (the trigger runs asynchronously right after addPlayer/createGame
        // resolves), not just the initial-load case, so both need the same
        // loading treatment rather than a crash.
        if (self == null) {
          return const Scaffold(
            backgroundColor: AppColors.ink,
            body: Center(child: CircularProgressIndicator(color: AppColors.brass)),
          );
        }
        _trackUnmasking(self);

        // A departed player can never legally vote/act again (the
        // repository rejects it), so their screen shouldn't offer to —
        // this replaces the whole dashboard rather than just disabling
        // pieces of it.
        if (self.hasLeft) {
          return const _LeftGameScreen();
        }

        _startWatchingForMoments(self.role);

        return _Dashboard(
          gameId: widget.gameId,
          self: self,
          players: players!,
          gameStream: _gameStream,
          mafiaThreadStream: _mafiaThreadStream,
          observationsStream: _observationsStream,
          votesStream: _votesStream,
          voteHistoryStream: _voteHistoryStream,
          blockedPlayerIdsStream: _blockedPlayerIdsStream,
        );
      },
    );
  }
}

class _LeftGameScreen extends StatelessWidget {
  const _LeftGameScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      appBar: AppBar(title: const Text('The Office Case')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(PhosphorIconsLight.signOut, size: 48, color: AppColors.textSecondary),
              const SizedBox(height: AppSpacing.lg),
              Text('You left this case', style: AppTypography.displayMedium),
              const SizedBox(height: AppSpacing.sm),
              Text(
                "You can't vote or act in it anymore, but your history "
                "stays on the record for everyone else.",
                style: AppTypography.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnmaskStamp extends StatelessWidget {
  final VoidCallback onDismiss;

  const _UnmaskStamp({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    Widget card = DossierCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            AppGraphics.unmaskStampBurst,
            width: 44,
            height: 44,
            colorFilter: const ColorFilter.mode(AppColors.brass, BlendMode.srcIn),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('UNMASKED', style: AppTypography.displayMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(
            "Your cover is blown — you're a Witness now, out in the open.",
            style: AppTypography.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
    if (!reduceMotion) {
      card = card
          .animate(onComplete: (_) => HapticFeedback.heavyImpact())
          .scale(
            begin: const Offset(1.15, 1.15),
            end: const Offset(1, 1),
            duration: AppMotion.ceremonyStamp,
            curve: Curves.easeOutBack,
          )
          .rotate(begin: -3 / 360, end: 0, duration: AppMotion.ceremonyStamp);
    }
    return GestureDetector(
      onTap: onDismiss,
      child: Padding(padding: const EdgeInsets.all(AppSpacing.xl), child: card),
    );
  }
}

class _EliminationBanner extends StatefulWidget {
  final String gameId;
  final String selfId;
  final String method;

  /// True once a mafia member has confirmed they actually carried out the
  /// method — before this, the method is only a forewarning of what to
  /// watch for (section 6), so there's nothing to reveal or confirm yet.
  final bool executed;
  final bool confirmed;

  const _EliminationBanner({
    required this.gameId,
    required this.selfId,
    required this.method,
    required this.executed,
    required this.confirmed,
  });

  @override
  State<_EliminationBanner> createState() => _EliminationBannerState();
}

class _EliminationBannerState extends State<_EliminationBanner>
    with SingleTickerProviderStateMixin {
  // Constructed eagerly in initState, not lazily here: build() has an
  // early return (when !widget.executed) that never touches this field,
  // so a lazy `late final = AnimationController(...)` would only run its
  // initializer the first time something accesses it — which could end up
  // being dispose() itself, constructing a brand-new AnimationController
  // (and its ticker, which needs an inherited-widget lookup) mid-teardown,
  // on an already-deactivated context.
  late final AnimationController _controller;
  bool _tapped = false;

  /// null = haven't tapped "I found it" yet this session; true/false is
  /// this player's own answer, told to them plainly either way — unlike
  /// role visibility elsewhere, this confirmation isn't meant to stay
  /// ambiguous.
  bool? _wasTarget;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.ceremonyWipe);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reveal() {
    if (_tapped) return;
    // Heavy, not medium — this is the danger banner (see the class doc on
    // _RecruitmentBanner for the matching "invitation" tone it's mirroring
    // against), so the tap that starts the wipe should feel like it too.
    HapticFeedback.heavyImpact();
    setState(() => _tapped = true);
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  Future<void> _acknowledge() async {
    final wasTarget = await context.read<GameRepository>().acknowledgeEliminationSignal(
          gameId: widget.gameId,
          playerId: widget.selfId,
        );
    if (!mounted) return;
    // The answer itself is the real moment here, not the tap that asked
    // for it — heavy if the hit actually landed on you, light for the
    // relief of finding out it didn't.
    (wasTarget ? HapticFeedback.heavyImpact : HapticFeedback.lightImpact)();
    setState(() => _wasTarget = wasTarget);
  }

  @override
  Widget build(BuildContext context) {
    final banner = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.crimsonSoft,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.crimson, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.executed ? "TODAY'S SIGNAL" : 'THE WIRE HAS AGREED ON A SIGNAL',
            style: AppTypography.dataSmall.copyWith(color: AppColors.crimsonText),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(widget.method, style: AppTypography.body),
          if (!widget.executed) ...[
            const SizedBox(height: AppSpacing.xs),
            Text("Watch for it — it hasn't happened yet.", style: AppTypography.dataSmall),
          ],
          if (widget.executed && _tapped) ...[
            const SizedBox(height: AppSpacing.sm),
            if (widget.confirmed || _wasTarget == true)
              Text('— confirmed received',
                  style: AppTypography.dataSmall.copyWith(color: AppColors.brass))
            else if (_wasTarget == false)
              Text("— you weren't the target", style: AppTypography.dataSmall)
            else
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _acknowledge,
                  child: const Text('I found it'),
                ),
              ),
          ],
        ],
      ),
    );

    if (!widget.executed) {
      // Nothing to reveal yet — the method itself isn't secret (section
      // 6), only whether it's actually happened.
      return banner;
    }

    return GestureDetector(
      onTap: _reveal,
      child: Stack(
        children: [
          banner,
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final progress = Curves.easeOut.transform(_controller.value);
              if (progress >= 1) return const SizedBox.shrink();
              return Positioned.fill(
                child: Align(
                  alignment: Alignment.centerRight,
                  widthFactor: 1 - progress,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.crimsonSoft,
                            border: Border.all(color: AppColors.crimson, width: 1),
                          ),
                        ),
                        SvgPicture.asset(AppGraphics.redactionBar, fit: BoxFit.cover),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          if (!_tapped)
            Positioned.fill(
              child: Center(
                child: Text("Tap to check today's signal", style: AppTypography.bodySmall),
              ),
            ),
        ],
      ),
    );
  }
}

/// Mirrors `_EliminationBanner` exactly, just brass-toned (this isn't
/// danger, it's an invitation) and with Accept/Decline in place of a
/// single passive acknowledgement — receiving the recruitment sign *is*
/// the decision, not just noticing it.
class _RecruitmentBanner extends StatefulWidget {
  final String gameId;
  final String selfId;
  final String sign;
  final bool executed;
  final bool confirmed;

  const _RecruitmentBanner({
    required this.gameId,
    required this.selfId,
    required this.sign,
    required this.executed,
    required this.confirmed,
  });

  @override
  State<_RecruitmentBanner> createState() => _RecruitmentBannerState();
}

class _RecruitmentBannerState extends State<_RecruitmentBanner>
    with SingleTickerProviderStateMixin {
  // See the matching comment in _EliminationBannerState — constructed
  // eagerly in initState so dispose() never triggers a first-time lazy
  // initialization (and its inherited-widget lookup) mid-teardown.
  late final AnimationController _controller;
  bool _tapped = false;

  /// null = haven't answered yet this session; true/false is this
  /// player's own answer, told to them plainly either way — same design
  /// call as the elimination signal's confirmation.
  bool? _wasTarget;
  bool? _myAnswer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.ceremonyWipe);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reveal() {
    if (_tapped) return;
    // Medium, not heavy — this is the "invitation" banner (see the class
    // doc above), so the tap that starts the wipe should read as lighter
    // than the elimination banner's equivalent moment.
    HapticFeedback.mediumImpact();
    setState(() => _tapped = true);
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  Future<void> _respond(bool accept) async {
    final wasTarget = await context.read<GameRepository>().respondToRecruitment(
          gameId: widget.gameId,
          playerId: widget.selfId,
          accept: accept,
        );
    if (!mounted) return;
    // Same tiering as _EliminationBannerState._acknowledge: the answer is
    // the real moment, heavier if the sign was actually meant for you.
    (wasTarget ? HapticFeedback.heavyImpact : HapticFeedback.lightImpact)();
    setState(() {
      _wasTarget = wasTarget;
      _myAnswer = accept;
    });
  }

  @override
  Widget build(BuildContext context) {
    final banner = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.brassSoft,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.brass, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.executed ? 'A SIGN TO WATCH FOR' : 'THE WIRE IS RECRUITING',
            style: AppTypography.dataSmall.copyWith(color: AppColors.brass),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(widget.sign, style: AppTypography.body),
          if (!widget.executed) ...[
            const SizedBox(height: AppSpacing.xs),
            Text("Watch for it — it hasn't happened yet.", style: AppTypography.dataSmall),
          ],
          if (widget.executed && _tapped) ...[
            const SizedBox(height: AppSpacing.sm),
            if (widget.confirmed || _wasTarget == true)
              Text(
                _myAnswer == false ? '— you declined' : '— you\'re in',
                style: AppTypography.dataSmall.copyWith(color: AppColors.brass),
              )
            else if (_wasTarget == false)
              Text("— not you", style: AppTypography.dataSmall)
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => _respond(false),
                    child: const Text('Decline'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ElevatedButton(
                    onPressed: () => _respond(true),
                    child: const Text('Accept'),
                  ),
                ],
              ),
          ],
        ],
      ),
    );

    if (!widget.executed) {
      return banner;
    }

    return GestureDetector(
      onTap: _reveal,
      child: Stack(
        children: [
          banner,
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final progress = Curves.easeOut.transform(_controller.value);
              if (progress >= 1) return const SizedBox.shrink();
              return Positioned.fill(
                child: Align(
                  alignment: Alignment.centerRight,
                  widthFactor: 1 - progress,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.brassSoft,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      border: Border.all(color: AppColors.brass, width: 1),
                    ),
                  ),
                ),
              );
            },
          ),
          if (!_tapped)
            Positioned.fill(
              child: Center(
                child: Text('Tap to check for the sign', style: AppTypography.bodySmall),
              ),
            ),
        ],
      ),
    );
  }
}

/// The one ceremony moment the design spec never had to cover before:
/// villagers win the instant no living mafia remains, mafia win the
/// instant they reach parity or a majority — whichever crosses first ends
/// the case for good. Replaces the whole dashboard (nothing is votable,
/// proposable, or executable anymore once [Game.status] is `ended`),
/// same ceremony-over-routine treatment as role reveal and unmasking.
class _FinaleCeremonyScreen extends StatelessWidget {
  final Game game;
  final Player self;

  const _FinaleCeremonyScreen({required this.game, required this.self});

  @override
  Widget build(BuildContext context) {
    final villagersWon = game.winner == GameWinner.villagers;
    final accent = villagersWon ? AppColors.brass : AppColors.crimson;
    final icon = villagersWon ? PhosphorIconsLight.magnifyingGlass : PhosphorIconsLight.maskHappy;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    Widget badge = Icon(icon, size: 72, color: accent);
    Widget headline = Text(
      villagersWon ? 'The Villagers Win' : 'The Mafia Wins',
      style: AppTypography.displayLarge,
      textAlign: TextAlign.center,
    );

    if (!reduceMotion) {
      badge = badge
          .animate(onComplete: (_) => HapticFeedback.mediumImpact())
          .scale(
            begin: const Offset(0.85, 0.85),
            end: const Offset(1, 1),
            duration: AppMotion.ceremonySeal,
            curve: Curves.easeOutBack,
          );
      headline = headline
          .animate(delay: 150.ms)
          .fadeIn(duration: AppMotion.ceremonyHeadline)
          .slideY(begin: 0.15, end: 0, duration: AppMotion.ceremonyHeadline);
    }

    // The finale is the one moment the full mafia roster is fair game to
    // reveal, regardless of how the case ended — includes anyone who was
    // ever mafia, whether they were caught, still hidden, or left along
    // the way.
    final everMafia =
        game.players.where((p) => p.role == PlayerRole.mafia || p.wasUnmasked).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.xxl),
          badge,
          const SizedBox(height: AppSpacing.xl),
          headline,
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Case closed at round ${game.currentRound}.',
            style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xxl),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'THE MAFIA',
              style: AppTypography.dataSmall.copyWith(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final p in everMafia)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: [
                  Icon(PhosphorIconsLight.maskHappy, size: 16, color: AppColors.crimsonText),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      [
                        p.id == self.id ? '${p.name} (you)' : p.name,
                        if (p.hasLeft) '(left)',
                      ].join(' '),
                      style: AppTypography.body,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Dashboard extends StatefulWidget {
  final String gameId;
  final Player self;
  final List<Player> players;
  final Stream<Game> gameStream;
  final Stream<List<MafiaThreadEntry>> mafiaThreadStream;
  final Stream<List<Observation>> observationsStream;
  final Stream<List<Vote>> votesStream;
  final Stream<List<Vote>> voteHistoryStream;
  final Stream<Set<String>> blockedPlayerIdsStream;

  const _Dashboard({
    required this.gameId,
    required this.self,
    required this.players,
    required this.gameStream,
    required this.mafiaThreadStream,
    required this.observationsStream,
    required this.votesStream,
    required this.voteHistoryStream,
    required this.blockedPlayerIdsStream,
  });

  @override
  State<_Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<_Dashboard> {
  // Debug-only, session-local: the repository still only ever hands the UI
  // redacted player data (design pillar — redaction lives in the
  // repository, never the UI); this just chooses, locally, whether to also
  // read the real roles already sitting in `game.players` from the
  // unredacted `gameStream` this screen already subscribes to for other
  // fields (round, status, elimination/recruitment descriptions).
  bool _revealRoles = false;

  @override
  Widget build(BuildContext context) {
    final gameId = widget.gameId;
    final self = widget.self;
    final players = widget.players;
    final repo = context.watch<GameRepository>();
    final isCurrentMafia = self.role == PlayerRole.mafia && !self.wasUnmasked;

    return Scaffold(
      appBar: AppBar(
        title: const Text('The Office Case'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Center(child: VoteWeightPill(weight: self.voteWeight)),
          ),
          IconButton(
            icon: Icon(PhosphorIconsLight.chartBar, color: AppColors.textSecondary),
            tooltip: 'Track record',
            onPressed: () => openTrackRecord(context, viewerId: self.id, viewerName: self.name),
          ),
          IconButton(
            icon: Icon(PhosphorIconsLight.bookOpenText, color: AppColors.textSecondary),
            tooltip: 'How to play',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HelpScreen()),
            ),
          ),
          IconButton(
            icon: Icon(PhosphorIconsLight.signOut, color: AppColors.textSecondary),
            tooltip: 'Leave this case',
            onPressed: () => _confirmLeave(context, repo, gameId, self.id),
          ),
        ],
      ),
      body: StreamBuilder<Game>(
        stream: widget.gameStream,
        builder: (context, snapshot) {
          final game = snapshot.data;
          if (game == null) {
            return const Center(child: CircularProgressIndicator(color: AppColors.brass));
          }
          if (game.status == GameStatus.ended) {
            return _FinaleCeremonyScreen(game: game, self: self);
          }
          final realRolesById = {for (final p in game.players) p.id: p.role};
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Row(
                children: [
                  RoleBadge(role: self.role, size: 44),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(self.name, style: AppTypography.heading),
                        Text(noirRoleLabel(self.role), style: AppTypography.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                self.id == game.creatorId
                    ? '${game.locationTag} · round ${game.currentRound} · '
                        '${game.status.name} · Admin'
                    : '${game.locationTag} · round ${game.currentRound} · ${game.status.name}',
                style: AppTypography.dataSmall,
              ),
              if (self.id == game.creatorId && game.isRestricted) ...[
                const SizedBox(height: AppSpacing.md),
                _AdminPassphraseCard(gameId: gameId, playerId: self.id),
              ],
              // Both debug-only controls below were previously rendered
              // unconditionally in every build — a real release would
              // have let any player flip a switch to see every hidden
              // role, or manually force a round to resolve early. Now
              // gated behind kDebugMode, matching main.dart's existing
              // pattern for the same class of dev-only affordance.
              if (kDebugMode) ...[
                const SizedBox(height: AppSpacing.md),
                // Bypasses the repository's role redaction locally so a
                // solo playtester can check everyone's real role without
                // switching over to the tester flow.
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  activeColor: AppColors.crimson,
                  value: _revealRoles,
                  onChanged: (value) => setState(() => _revealRoles = value),
                  title: Text(
                    'Reveal roles (debug)',
                    style: AppTypography.bodySmall.copyWith(color: AppColors.crimsonText),
                  ),
                  subtitle: Text(
                    'Temporary, for testing only — real players never see this.',
                    style: AppTypography.dataSmall,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              // Every section below gets a stable Key. Without one, an
              // unkeyed list matches children by position — when a
              // conditional section (e.g. this banner) appears or
              // disappears, everything after it shifts index, Flutter sees
              // a type mismatch at each shifted position, and tears down
              // and recreates that section's State from scratch. For a
              // StreamBuilder fed a single-subscription stream, that
              // recreation used to crash with "Stream has already been
              // listened to"; even now that the streams are broadcast, an
              // unwanted teardown would still silently drop in-progress
              // typed text in the message/observation fields.
              if (game.eliminationMethodDescription != null)
                Padding(
                  key: const ValueKey('elimination_banner'),
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  child: _EliminationBanner(
                    gameId: gameId,
                    selfId: self.id,
                    method: game.eliminationMethodDescription!,
                    executed: game.eliminationSignalExecuted,
                    confirmed: game.eliminationSignalConfirmed,
                  ),
                ),
              if (game.recruitmentSignDescription != null)
                Padding(
                  key: const ValueKey('recruitment_banner'),
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  child: _RecruitmentBanner(
                    gameId: gameId,
                    selfId: self.id,
                    sign: game.recruitmentSignDescription!,
                    executed: game.recruitmentSignExecuted,
                    confirmed: game.recruitmentSignConfirmed,
                  ),
                ),
              if (isCurrentMafia)
                Padding(
                  key: const ValueKey('mafia_section'),
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  child: _MafiaSection(
                    gameId: gameId,
                    self: self,
                    players: players,
                    recruitmentUnlocked: game.recruitmentUnlocked,
                    threadStream: widget.mafiaThreadStream,
                  ),
                ),
              Padding(
                key: const ValueKey('roster_section'),
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: _PlayerRosterSection(
                  gameId: gameId,
                  self: self,
                  players: players,
                  votesStream: widget.votesStream,
                  revealRoles: _revealRoles,
                  realRolesById: realRolesById,
                  blockedPlayerIdsStream: widget.blockedPlayerIdsStream,
                ),
              ),
              Padding(
                key: const ValueKey('voting_history_section'),
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: _VotingHistorySection(
                  self: self,
                  players: players,
                  voteHistoryStream: widget.voteHistoryStream,
                ),
              ),
              Padding(
                key: const ValueKey('observation_section'),
                padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                child: _ObservationSection(
                  gameId: gameId,
                  self: self,
                  players: players,
                  observationsStream: widget.observationsStream,
                  blockedPlayerIdsStream: widget.blockedPlayerIdsStream,
                ),
              ),
              Center(
                child: Text(
                  "Today's votes resolve on their own around "
                  '${_formatTimeOfDay(game.dailyCutoffTime)} — '
                  'no one has to press anything.',
                  style: AppTypography.dataSmall.copyWith(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ),
              if (kDebugMode) ...[
                const SizedBox(height: AppSpacing.sm),
                Center(
                  key: const ValueKey('resolve_button'),
                  child: OutlinedButton(
                    onPressed: () => _runGuarded(context, () => repo.resolveVotesForDay(gameId)),
                    child: const Text("Resolve today's votes (debug)"),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Shown only to a restricted case's creator (its admin) — lets them look
/// the passphrase back up to repeat it to a coworker, since the only other
/// place it's ever shown is the one-time reveal dialog at case creation.
class _AdminPassphraseCard extends StatefulWidget {
  final String gameId;
  final String playerId;

  const _AdminPassphraseCard({required this.gameId, required this.playerId});

  @override
  State<_AdminPassphraseCard> createState() => _AdminPassphraseCardState();
}

class _AdminPassphraseCardState extends State<_AdminPassphraseCard> {
  Future<List<String>?>? _wordsFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _wordsFuture ??= context.read<GameRepository>().fetchGamePassphrase(
          gameId: widget.gameId,
          playerId: widget.playerId,
        );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>?>(
      future: _wordsFuture,
      builder: (context, snapshot) {
        final words = snapshot.data;
        if (words == null || words.isEmpty) return const SizedBox.shrink();
        return DossierCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(PhosphorIconsLight.lock, size: 20, color: AppColors.textSecondary),
                  const SizedBox(width: AppSpacing.sm),
                  Text('Case pass', style: AppTypography.heading),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Share with a new joiner: ${words.join(' · ')}',
                style: AppTypography.body,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PlayerRosterSection extends StatelessWidget {
  final String gameId;
  final Player self;
  final List<Player> players;
  final Stream<List<Vote>> votesStream;
  final bool revealRoles;
  final Map<String, PlayerRole> realRolesById;
  final Stream<Set<String>> blockedPlayerIdsStream;

  const _PlayerRosterSection({
    required this.gameId,
    required this.self,
    required this.players,
    required this.votesStream,
    required this.revealRoles,
    required this.realRolesById,
    required this.blockedPlayerIdsStream,
  });

  String _nameFor(String playerId) {
    final match = players.where((p) => p.id == playerId);
    return match.isNotEmpty ? match.first.name : 'someone';
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<GameRepository>();
    return DossierCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsLight.magnifyingGlass, size: 20, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.sm),
              Text('The Roster', style: AppTypography.heading),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          StreamBuilder<List<Vote>>(
            stream: votesStream,
            builder: (context, voteSnapshot) {
              final votes = voteSnapshot.data ?? const [];
              final myVotes = votes.where((v) => v.voterId == self.id);
              final myVoteTargetId = myVotes.isNotEmpty ? myVotes.first.targetPlayerId : null;

              // Tally by target: total weight behind them (what actually
              // decides the outcome) plus who cast those votes, sorted
              // strongest-first so the summary reads like a leaderboard.
              final voterNamesByTarget = <String, List<String>>{};
              final weightByTarget = <String, int>{};
              for (final vote in votes) {
                voterNamesByTarget.putIfAbsent(vote.targetPlayerId, () => []).add(
                      vote.voterId == self.id ? 'you' : _nameFor(vote.voterId),
                    );
                weightByTarget[vote.targetPlayerId] =
                    (weightByTarget[vote.targetPlayerId] ?? 0) + vote.weight;
              }
              final rankedTargets = weightByTarget.keys.toList()
                ..sort((a, b) => weightByTarget[b]!.compareTo(weightByTarget[a]!));

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("TODAY'S TALLY",
                      style: AppTypography.dataSmall.copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: AppSpacing.xs),
                  if (rankedTargets.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Text('No votes cast yet this round.', style: AppTypography.bodySmall),
                    )
                  else
                    for (final targetId in rankedTargets)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_nameFor(targetId)} — ${weightByTarget[targetId]} '
                              '${weightByTarget[targetId] == 1 ? "vote" : "votes"}',
                              style: AppTypography.data.copyWith(color: AppColors.brass),
                            ),
                            Text(
                              'from ${voterNamesByTarget[targetId]!.join(', ')}',
                              style: AppTypography.dataSmall,
                            ),
                          ],
                        ),
                      ),
                  const SizedBox(height: AppSpacing.xs),
                  const Divider(color: AppColors.borderHairline, height: AppSpacing.lg),
                  // Blocked state only ever changes the Report/Block menu's
                  // own label below — it's the viewer's own preference,
                  // never game truth, so it doesn't touch voting or
                  // anything else about this list (see watchBlockedPlayerIds'
                  // doc comment).
                  StreamBuilder<Set<String>>(
                    stream: blockedPlayerIdsStream,
                    builder: (context, blockedSnapshot) {
                      final blockedIds = blockedSnapshot.data ?? const <String>{};
                      return Column(
                        children: [
                          for (final player in players)
                            Container(
                              decoration: BoxDecoration(
                                color: myVoteTargetId == player.id ? AppColors.brassSoft : null,
                                border: const Border(
                                    bottom: BorderSide(color: AppColors.borderHairline)),
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.sm,
                                horizontal: AppSpacing.xs,
                              ),
                              child: Row(
                                children: [
                                  if (myVoteTargetId == player.id)
                                    Padding(
                                      padding: const EdgeInsets.only(right: AppSpacing.xs),
                                      child: Icon(PhosphorIconsLight.checkCircle,
                                          size: 16, color: AppColors.brass),
                                    ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          [
                                            player.id == self.id
                                                ? '${player.name} (you)'
                                                : player.name,
                                            if (player.hasLeft) '(left)',
                                          ].join(' '),
                                          style: AppTypography.body.copyWith(
                                            color: player.hasLeft
                                                ? AppColors.textMuted
                                                : myVoteTargetId == player.id
                                                    ? AppColors.brass
                                                    : AppColors.textPrimary,
                                            fontWeight: myVoteTargetId == player.id
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                          ),
                                        ),
                                        if (revealRoles)
                                          Text(
                                            (realRolesById[player.id] ?? PlayerRole.villager).name,
                                            style: AppTypography.dataSmall.copyWith(
                                              color: realRolesById[player.id] == PlayerRole.mafia
                                                  ? AppColors.crimsonText
                                                  : AppColors.textMuted,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  // Only self's weight is real (repository
                                  // redacts everyone else's to the starting
                                  // value) — showing a pill for other
                                  // players would just be a misleadingly
                                  // constant "3" for everyone, so it's
                                  // dropped entirely rather than displayed
                                  // as if meaningful.
                                  if (player.id == self.id)
                                    VoteWeightPill(weight: player.voteWeight),
                                  const SizedBox(width: AppSpacing.sm),
                                  if (player.id != self.id && !player.hasLeft)
                                    TextButton(
                                      onPressed: () => _runGuarded(
                                        context,
                                        () => repo.castVote(
                                          gameId: gameId,
                                          voterId: self.id,
                                          targetPlayerId: player.id,
                                        ),
                                      ),
                                      child: Text(myVoteTargetId == player.id ? 'Voted' : 'Vote'),
                                    ),
                                  // Available regardless of hasLeft — you
                                  // might still want to report or block
                                  // someone after they've left the case.
                                  if (player.id != self.id)
                                    PopupMenuButton<String>(
                                      icon: Icon(PhosphorIconsLight.dotsThreeVertical,
                                          size: 18, color: AppColors.textSecondary),
                                      tooltip: 'Report or block ${player.name}',
                                      onSelected: (value) {
                                        if (value == 'report') {
                                          _showReportDialog(
                                            context,
                                            repo: repo,
                                            gameId: gameId,
                                            reporterId: self.id,
                                            targetPlayerId: player.id,
                                            targetName: player.name,
                                          );
                                        } else if (value == 'block') {
                                          _runGuarded(
                                            context,
                                            () => repo.blockPlayer(
                                              gameId: gameId,
                                              viewerId: self.id,
                                              blockedPlayerId: player.id,
                                            ),
                                          );
                                        } else if (value == 'unblock') {
                                          _runGuarded(
                                            context,
                                            () => repo.unblockPlayer(
                                              gameId: gameId,
                                              viewerId: self.id,
                                              blockedPlayerId: player.id,
                                            ),
                                          );
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: 'report',
                                          child: Text('Report'),
                                        ),
                                        PopupMenuItem(
                                          value: blockedIds.contains(player.id)
                                              ? 'unblock'
                                              : 'block',
                                          child: Text(blockedIds.contains(player.id)
                                              ? 'Unblock'
                                              : 'Block'),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _VotingHistorySection extends StatelessWidget {
  final Player self;
  final List<Player> players;
  final Stream<List<Vote>> voteHistoryStream;

  const _VotingHistorySection({
    required this.self,
    required this.players,
    required this.voteHistoryStream,
  });

  String _nameFor(String playerId) {
    final match = players.where((p) => p.id == playerId);
    return match.isNotEmpty ? match.first.name : 'someone';
  }

  @override
  Widget build(BuildContext context) {
    return DossierCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsLight.clockCounterClockwise,
                  size: 20, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.sm),
              Text('Voting History', style: AppTypography.heading),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Every vote cast so far, across all rounds — worth tracking for patterns.',
            style: AppTypography.dataSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          StreamBuilder<List<Vote>>(
            stream: voteHistoryStream,
            builder: (context, snapshot) {
              final votes = snapshot.data ?? const [];
              if (votes.isEmpty) {
                return Text('No votes cast yet.', style: AppTypography.bodySmall);
              }

              // voterId -> targetId -> times voted for them. Deliberately a
              // plain count, not a weight sum: a voter's own weight only
              // ever drops when they've been confirmed not-mafia, so
              // summing it here would quietly out that voter the same way
              // a per-player weight stat would (see _publicView's doc for
              // the same reasoning applied to the roster).
              final byVoter = <String, Map<String, int>>{};
              for (final vote in votes) {
                final targets = byVoter.putIfAbsent(vote.voterId, () => {});
                targets[vote.targetPlayerId] = (targets[vote.targetPlayerId] ?? 0) + 1;
              }
              final voterIds = byVoter.keys.toList()
                ..sort((a, b) => _nameFor(a).compareTo(_nameFor(b)));

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final voterId in voterIds)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            voterId == self.id ? 'You' : _nameFor(voterId),
                            style: AppTypography.body,
                          ),
                          for (final entry in byVoter[voterId]!.entries.toList()
                            ..sort((a, b) => b.value.compareTo(a.value)))
                            Padding(
                              padding: const EdgeInsets.only(left: AppSpacing.md, top: 2),
                              child: Text(
                                '→ ${_nameFor(entry.key)}: ${entry.value} '
                                '${entry.value == 1 ? "time" : "times"}',
                                style: AppTypography.dataSmall,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MafiaSection extends StatefulWidget {
  final String gameId;
  final Player self;
  final List<Player> players;
  final bool recruitmentUnlocked;
  final Stream<List<MafiaThreadEntry>> threadStream;

  const _MafiaSection({
    required this.gameId,
    required this.self,
    required this.players,
    required this.recruitmentUnlocked,
    required this.threadStream,
  });

  @override
  State<_MafiaSection> createState() => _MafiaSectionState();
}

class _MafiaSectionState extends State<_MafiaSection> {
  final _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _proposeElimination(GameRepository repo, List<Player> villagers) async {
    final result = await showDialog<({String targetId, String method})>(
      context: context,
      builder: (context) => _ProposeEliminationDialog(villagers: villagers),
    );
    if (result == null) return;
    if (!mounted) return;
    // The roster this section works from is redacted (cell structure —
    // design pillar #4), so a "villager at weight 0" here might actually
    // already be secretly mafia, or already have a pending recruitment
    // offer from someone else — this section has no way to know in
    // advance. When the repository rejects the action for one of those
    // reasons, the message stays generic rather than repeating *why* —
    // doing so would leak exactly the hidden information the redaction
    // exists to protect.
    await _runGuarded(
      context,
      () => repo.proposeElimination(
        gameId: widget.gameId,
        authorId: widget.self.id,
        method: result.method,
        targetPlayerId: result.targetId,
      ),
      message: 'That lead went cold — try someone else.',
    );
  }

  Future<void> _proposeRecruitment(GameRepository repo, List<Player> villagers) async {
    final result = await showDialog<({String targetId, String sign})>(
      context: context,
      builder: (context) => _ProposeRecruitmentDialog(villagers: villagers),
    );
    if (result == null) return;
    if (!mounted) return;
    await _runGuarded(
      context,
      () => repo.proposeRecruitment(
        gameId: widget.gameId,
        recruiterId: widget.self.id,
        targetPlayerId: result.targetId,
        sign: result.sign,
      ),
      message: 'That lead went cold — try someone else.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<GameRepository>();
    final villagers =
        widget.players.where((p) => p.role == PlayerRole.villager && !p.hasLeft).toList();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.crimson, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SvgPicture.asset(
                AppGraphics.maskBespoke,
                width: 20,
                height: 20,
                colorFilter: const ColorFilter.mode(AppColors.crimson, BlendMode.srcIn),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text('The Wire', style: AppTypography.heading),
              const Spacer(),
              Text('Active', style: AppTypography.bodySmall),
              Switch(
                value: widget.self.isActive,
                activeColor: AppColors.brass,
                onChanged: (value) => _runGuarded(
                  context,
                  () => repo.setMemberActive(
                    gameId: widget.gameId,
                    playerId: widget.self.id,
                    isActive: value,
                  ),
                ),
              ),
            ],
          ),
          StreamBuilder<List<MafiaThreadEntry>>(
            stream: widget.threadStream,
            builder: (context, snapshot) {
              final entries = snapshot.data ?? const [];
              if (entries.isEmpty) {
                return Text('No coordination yet this round.', style: AppTypography.bodySmall);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Oldest first, newest last — same convention as any
                  // chat app, so the latest message sits right above the
                  // composer below instead of jumping to the top.
                  for (final entry in entries)
                    Padding(
                      // A new message/proposal is appended after every
                      // earlier entry, so without a stable key here,
                      // Flutter's unkeyed reconciliation would reuse each
                      // element in place by position and a
                      // `_MafiaThreadEntryTileState` (and its live
                      // countdown Timer) could end up silently reattached
                      // to a *different* entry as the list grows.
                      key: ValueKey(entry.id),
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: SizedBox(
                        width: double.infinity,
                        child: _MafiaThreadEntryTile(
                          gameId: widget.gameId,
                          self: widget.self,
                          players: widget.players,
                          entry: entry,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: const InputDecoration(hintText: 'Message the wire'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                icon: Icon(PhosphorIconsLight.paperPlaneTilt, color: AppColors.brass),
                onPressed: () {
                  final text = _messageController.text.trim();
                  if (text.isEmpty) return;
                  _runGuarded(
                    context,
                    () => repo.sendMafiaMessage(
                      gameId: widget.gameId,
                      authorId: widget.self.id,
                      text: text,
                    ),
                  );
                  _messageController.clear();
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ElevatedButton(
            onPressed: villagers.isEmpty ? null : () => _proposeElimination(repo, villagers),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.crimson,
              foregroundColor: AppColors.onCrimson,
            ),
            child: const Text('Propose elimination method'),
          ),
          if (widget.recruitmentUnlocked) ...[
            const SizedBox(height: AppSpacing.lg),
            Text('Recruitment unlocked',
                style: AppTypography.dataSmall.copyWith(color: AppColors.brass)),
            const SizedBox(height: AppSpacing.xs),
            // A second listener on the same broadcast thread stream, just
            // to know whether a recruitment is already in flight — one at
            // a time, mirroring elimination's single active signal.
            StreamBuilder<List<MafiaThreadEntry>>(
              stream: widget.threadStream,
              builder: (context, snapshot) {
                final hasActiveRecruitment = (snapshot.data ?? const []).any((e) =>
                    e.type == MafiaThreadEntryType.recruitment &&
                    !e.lapsed &&
                    e.confirmedAt == null);
                return OutlinedButton(
                  onPressed: villagers.isEmpty || hasActiveRecruitment
                      ? null
                      : () => _proposeRecruitment(repo, villagers),
                  child: Text(hasActiveRecruitment
                      ? 'Recruitment already in progress'
                      : 'Propose recruitment'),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Mirrors `_executionWindow` in `LocalGameRepository` — kept as a separate
/// constant here purely so the countdown display doesn't need a repository
/// round-trip just to know the window length. If that value changes, this
/// one has to change with it.
const _executionWindowUiCopy = Duration(hours: 1);

class _MafiaThreadEntryTile extends StatefulWidget {
  final String gameId;
  final Player self;
  final List<Player> players;
  final MafiaThreadEntry entry;

  const _MafiaThreadEntryTile({
    required this.gameId,
    required this.self,
    required this.players,
    required this.entry,
  });

  @override
  State<_MafiaThreadEntryTile> createState() => _MafiaThreadEntryTileState();
}

class _MafiaThreadEntryTileState extends State<_MafiaThreadEntryTile> {
  Timer? _ticker;

  bool get _isArmed {
    final entry = widget.entry;
    return entry.agreedAt != null && entry.executedAt == null && !entry.lapsed;
  }

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _MafiaThreadEntryTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  // A live countdown only makes sense while the proposal is armed
  // (agreed, not yet executed, window still open) — start/stop the
  // per-second tick as that state changes instead of always running one.
  void _syncTicker() {
    if (_isArmed && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!_isArmed && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  String _nameFor(String playerId) {
    final match = widget.players.where((p) => p.id == playerId);
    return match.isNotEmpty ? match.first.name : 'someone';
  }

  String _formatRemaining(Duration remaining) {
    if (remaining.isNegative) return '0:00';
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  bool get _isRecruitment => widget.entry.type == MafiaThreadEntryType.recruitment;

  Future<void> _accept(GameRepository repo) {
    final entry = widget.entry;
    return _runGuarded(
      context,
      () => _isRecruitment
          ? repo.acceptRecruitmentProposal(
              gameId: widget.gameId,
              proposalId: entry.id,
              playerId: widget.self.id,
            )
          : repo.acceptEliminationProposal(
              gameId: widget.gameId,
              proposalId: entry.id,
              playerId: widget.self.id,
            ),
    );
  }

  Future<void> _execute(GameRepository repo) {
    final entry = widget.entry;
    return _runGuarded(
      context,
      () => _isRecruitment
          ? repo.executeRecruitment(
              gameId: widget.gameId,
              proposalId: entry.id,
              playerId: widget.self.id,
            )
          : repo.executeElimination(
              gameId: widget.gameId,
              proposalId: entry.id,
              playerId: widget.self.id,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<GameRepository>();
    final entry = widget.entry;
    final self = widget.self;

    if (entry.type == MafiaThreadEntryType.message) {
      final author = entry.authorId == self.id ? 'You' : _nameFor(entry.authorId);
      return Text('$author: ${entry.message}', style: AppTypography.bodySmall);
    }

    final isPending = entry.agreedAt == null;
    final isLive = isPending || _isArmed;
    final accepted = entry.acceptedByPlayerIds.contains(self.id);
    final target = _nameFor(entry.proposedTargetId!);

    final String stateLabel;
    if (entry.lapsed) {
      stateLabel = 'Lapsed';
    } else if (entry.confirmedAt != null && _isRecruitment) {
      stateLabel = entry.recruitmentAccepted == true ? 'Recruited' : 'Declined';
    } else if (entry.executedAt != null) {
      stateLabel = _isRecruitment ? 'Approached' : 'Applied';
    } else if (_isArmed) {
      stateLabel = 'Agreed';
    } else {
      stateLabel = _isRecruitment ? 'Recruiting' : 'Proposed';
    }

    final headline = '$stateLabel: ${entry.proposedMethod} → $target';

    // Only a still-live entry (pending acceptance, or agreed and counting
    // down) gets the solid fill that visually demands a decision. Applied
    // and lapsed entries are historical records — bordered outline only,
    // muted for a lapsed (missed) one.
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: isLive ? AppColors.crimsonSoft : Colors.transparent,
        border: isLive
            ? null
            : Border.all(
                color: entry.lapsed ? AppColors.textMuted : AppColors.crimson,
                width: 1,
              ),
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headline,
            style: AppTypography.body.copyWith(
              color: entry.lapsed ? AppColors.textMuted : AppColors.crimsonText,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (isPending)
            Text('${entry.acceptedByPlayerIds.length} accepted', style: AppTypography.dataSmall),
          if (_isArmed)
            Text(
              '${_isRecruitment ? "Approach" : "Execute"} within '
              '${_formatRemaining(entry.agreedAt!.add(_executionWindowUiCopy).difference(DateTime.now()))}',
              style: AppTypography.dataSmall.copyWith(color: AppColors.crimsonText),
            ),
          if (entry.executedAt != null && entry.confirmedAt == null)
            Text(
              _isRecruitment ? 'Awaiting response' : 'Awaiting confirmation',
              style: AppTypography.dataSmall,
            )
          else if (entry.confirmedAt != null && !_isRecruitment)
            Text('Confirmed received', style: AppTypography.dataSmall),
          if (isPending && !accepted)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _accept(repo),
                child: const Text('Accept'),
              ),
            ),
          if (_isArmed)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _execute(repo),
                child: Text(_isRecruitment ? 'Approached' : 'Executed'),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProposeEliminationDialog extends StatefulWidget {
  final List<Player> villagers;

  const _ProposeEliminationDialog({required this.villagers});

  @override
  State<_ProposeEliminationDialog> createState() => _ProposeEliminationDialogState();
}

class _ProposeEliminationDialogState extends State<_ProposeEliminationDialog> {
  String? _targetId;
  final _methodController = TextEditingController();

  @override
  void dispose() {
    _methodController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceRaised,
      title: const Text('Propose an elimination method'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            value: _targetId,
            hint: const Text('Target'),
            items: [
              for (final v in widget.villagers)
                DropdownMenuItem(value: v.id, child: Text(v.name)),
            ],
            onChanged: (value) => setState(() => _targetId = value),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _methodController,
            decoration: const InputDecoration(hintText: 'e.g. a note left on their monitor'),
            // The Propose button's enabled state reads this controller, so
            // typing has to trigger a rebuild too — not just the dropdown.
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _targetId == null || _methodController.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop((
                    targetId: _targetId!,
                    method: _methodController.text.trim(),
                  )),
          child: const Text('Propose'),
        ),
      ],
    );
  }
}

class _ProposeRecruitmentDialog extends StatefulWidget {
  final List<Player> villagers;

  const _ProposeRecruitmentDialog({required this.villagers});

  @override
  State<_ProposeRecruitmentDialog> createState() => _ProposeRecruitmentDialogState();
}

class _ProposeRecruitmentDialogState extends State<_ProposeRecruitmentDialog> {
  String? _targetId;
  final _signController = TextEditingController();

  @override
  void dispose() {
    _signController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceRaised,
      title: const Text('Propose a recruitment'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Any current villager is fair game — this is about a real '
            'conversation, not just picking whoever has the least to lose.',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String>(
            value: _targetId,
            hint: const Text('Target'),
            items: [
              for (final v in widget.villagers)
                DropdownMenuItem(value: v.id, child: Text(v.name)),
            ],
            onChanged: (value) => setState(() => _targetId = value),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _signController,
            decoration: const InputDecoration(hintText: 'e.g. a specific pen left on their desk'),
            // The Propose button's enabled state reads this controller, so
            // typing has to trigger a rebuild too — not just the dropdown.
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _targetId == null || _signController.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop((
                    targetId: _targetId!,
                    sign: _signController.text.trim(),
                  )),
          child: const Text('Propose'),
        ),
      ],
    );
  }
}

class _ObservationSection extends StatefulWidget {
  final String gameId;
  final Player self;
  final List<Player> players;
  final Stream<List<Observation>> observationsStream;
  final Stream<Set<String>> blockedPlayerIdsStream;

  const _ObservationSection({
    required this.gameId,
    required this.self,
    required this.players,
    required this.observationsStream,
    required this.blockedPlayerIdsStream,
  });

  @override
  State<_ObservationSection> createState() => _ObservationSectionState();
}

class _ObservationSectionState extends State<_ObservationSection> {
  final _textController = TextEditingController();
  String? _targetId;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  String _nameFor(String playerId) {
    final match = widget.players.where((p) => p.id == playerId);
    return match.isNotEmpty ? match.first.name : 'someone';
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<GameRepository>();
    return DossierCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsLight.eye, size: 20, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.sm),
              Text('Observation Log', style: AppTypography.heading),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('Kept for 3 rounds, then destroyed.', style: AppTypography.dataSmall),
          const SizedBox(height: AppSpacing.sm),
          StreamBuilder<List<Observation>>(
            stream: widget.observationsStream,
            builder: (context, snapshot) {
              final observations = snapshot.data ?? const [];
              return StreamBuilder<Set<String>>(
                stream: widget.blockedPlayerIdsStream,
                builder: (context, blockedSnapshot) {
                  final blockedIds = blockedSnapshot.data ?? const <String>{};
                  final visible =
                      observations.where((o) => !blockedIds.contains(o.authorId)).toList();
                  if (visible.isEmpty) {
                    return Text(
                      observations.isEmpty
                          ? 'Nothing logged yet.'
                          : 'Nothing to show — every entry here is from a blocked player.',
                      style: AppTypography.bodySmall,
                    );
                  }
                  return Column(
                    children: [
                      // Oldest first, newest last — same convention as any
                      // chat app, so the latest note sits right above the
                      // composer below.
                      for (final o in visible)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  o.targetPlayerId == null
                                      ? '${_nameFor(o.authorId)}: ${o.text}'
                                      : '${_nameFor(o.authorId)} about '
                                          '${_nameFor(o.targetPlayerId!)}: ${o.text}',
                                  style: AppTypography.bodySmall
                                      .copyWith(color: AppColors.textPrimary),
                                ),
                              ),
                              Visibility(
                                visible: o.authorId != widget.self.id,
                                maintainSize: true,
                                maintainAnimation: true,
                                maintainState: true,
                                child: IconButton(
                                  icon: Icon(PhosphorIconsLight.flag,
                                      size: 16, color: AppColors.textMuted),
                                  tooltip: 'Report this entry',
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => _showReportDialog(
                                    context,
                                    repo: context.read<GameRepository>(),
                                    gameId: widget.gameId,
                                    reporterId: widget.self.id,
                                    targetPlayerId: o.authorId,
                                    targetName: _nameFor(o.authorId),
                                    observationId: o.id,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String?>(
            value: _targetId,
            hint: const Text('General observation'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('General observation')),
              for (final p in widget.players.where((p) => p.id != widget.self.id))
                DropdownMenuItem<String?>(value: p.id, child: Text('About ${p.name}')),
            ],
            onChanged: (value) => setState(() => _targetId = value),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _textController,
                  decoration: const InputDecoration(hintText: 'What did you notice?'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                icon: Icon(PhosphorIconsLight.paperPlaneTilt, color: AppColors.brass),
                onPressed: () {
                  final text = _textController.text.trim();
                  if (text.isEmpty) return;
                  _runGuarded(
                    context,
                    () => repo.logObservation(
                      gameId: widget.gameId,
                      authorId: widget.self.id,
                      text: text,
                      targetPlayerId: _targetId,
                    ),
                  );
                  _textController.clear();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
