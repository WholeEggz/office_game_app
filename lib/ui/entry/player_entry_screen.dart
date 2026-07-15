import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../design/colors.dart';
import '../../design/graphics.dart';
import '../../design/spacing.dart';
import '../../design/typography.dart';
import '../../domain/models/game.dart';
import '../../domain/repositories/auth_service.dart';
import '../../domain/repositories/game_repository.dart';
import '../common/dossier_card.dart';
import '../game/game_screen.dart';
import '../help/help_screen.dart';
import '../stats/track_record_screen.dart';
import 'case_creation_screen.dart';
import 'case_details_screen.dart';

/// "17:00"-style plain-date fallback for anything more than a week old —
/// mirrors game_screen.dart's `_formatTimeOfDay` in spirit (hand-rolled,
/// no `intl` dependency for one string).
String _formatAddedDate(DateTime createdAt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final createdDay = DateTime(createdAt.year, createdAt.month, createdAt.day);
  final daysAgo = today.difference(createdDay).inDays;
  if (daysAgo <= 0) return 'Added today';
  if (daysAgo == 1) return 'Added yesterday';
  if (daysAgo < 7) return 'Added $daysAgo days ago';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return 'Added ${months[createdAt.month - 1]} ${createdAt.day}';
}

/// Sort options for "Find your case" — newest-first by default so a case
/// you just created or heard about is easy to spot without hunting.
enum _SortOption {
  newest('Newest first'),
  oldest('Oldest first'),
  mostPlayers('Most players'),
  mostRounds('Most rounds');

  final String label;
  const _SortOption(this.label);

  int compare(Game a, Game b) => switch (this) {
        _SortOption.newest => b.createdAt.compareTo(a.createdAt),
        _SortOption.oldest => a.createdAt.compareTo(b.createdAt),
        _SortOption.mostPlayers => b.players.length.compareTo(a.players.length),
        _SortOption.mostRounds => b.currentRound.compareTo(a.currentRound),
      };
}

/// The real player's path: register once, then find and join a game from
/// the list — no jumping between identities like the tester flow does.
class PlayerEntryScreen extends StatefulWidget {
  const PlayerEntryScreen({super.key});

  @override
  State<PlayerEntryScreen> createState() => _PlayerEntryScreenState();
}

class _PlayerEntryScreenState extends State<PlayerEntryScreen> {
  final _nameController = TextEditingController();
  AppUser? _user;
  // True only until the initial resumeSession() check resolves — brief in
  // practice (an already-cached auth state plus one Firestore read at
  // worst), but real: without this, a returning signed-in user would
  // flash the registration form for a frame before this screen replaces
  // it with the game list.
  bool _resumingSession = true;
  _SortOption _sort = _SortOption.newest;
  final Set<GameStatus> _statusFilter = GameStatus.values.toSet();

  @override
  void initState() {
    super.initState();
    _resumeSession();
  }

  /// The "signed-in user returns" flow: checks whether this device already
  /// has an identity from a previous launch and, if so, skips registration
  /// entirely and lands straight on the game list — the same thing
  /// `_register` does, just without the user having to retype their name.
  /// Resolves to the registration form when there's nothing to resume
  /// (first launch, or a signed-out/never-registered device).
  Future<void> _resumeSession() async {
    final resumed = await context.read<AuthService>().resumeSession();
    if (!mounted) return;
    setState(() {
      _user = resumed;
      _resumingSession = false;
    });
  }

  /// At least one status stays selected — an empty filter would just read
  /// as a confusing "no cases" screen rather than an intentional choice.
  void _toggleStatusFilter(GameStatus status) {
    setState(() {
      if (_statusFilter.contains(status)) {
        if (_statusFilter.length > 1) _statusFilter.remove(status);
      } else {
        _statusFilter.add(status);
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final auth = context.read<AuthService>();
    try {
      final user = await auth.signInWithDisplayName(name);
      if (!mounted) return;
      setState(() => _user = user);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not sign in: $e')));
    }
  }

  /// [replace] swaps the current route for `GameScreen` instead of
  /// pushing on top of it — used when this is called from
  /// `CaseDetailsScreen`, so that screen's own frame doesn't linger on
  /// the back stack once you're actually in the case (back from
  /// `GameScreen` should return straight to "Find your case", the same
  /// as the direct "Enter" path below does).
  Future<void> _joinAndEnter(Game game, {bool replace = false}) async {
    final user = _user!;
    final repo = context.read<GameRepository>();
    final alreadyJoined = game.players.any((p) => p.id == user.id);
    if (!alreadyJoined) {
      try {
        await repo.addPlayer(gameId: game.id, playerId: user.id, name: user.displayName);
      } on StateError catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
        return;
      }
    } else {
      await repo.recordReentry(gameId: game.id, playerId: user.id);
    }
    if (!mounted) return;
    final route = MaterialPageRoute(
      builder: (_) => GameScreen(gameId: game.id, playerId: user.id),
    );
    if (replace) {
      Navigator.of(context).pushReplacement(route);
    } else {
      Navigator.of(context).push(route);
    }
  }

  void _startNewCase() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CaseCreationScreen(creator: _user!),
    ));
  }

  void _openDetails(Game game) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          CaseDetailsScreen(game: game, onJoin: () => _joinAndEnter(game, replace: true)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Join a case'),
        actions: [
          if (_user case final user?)
            IconButton(
              icon: Icon(PhosphorIconsLight.chartBar, color: AppColors.textSecondary),
              tooltip: 'Track record',
              onPressed: () =>
                  openTrackRecord(context, viewerId: user.id, viewerName: user.displayName),
            ),
          IconButton(
            icon: Icon(PhosphorIconsLight.bookOpenText, color: AppColors.textSecondary),
            tooltip: 'How to play',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HelpScreen()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _resumingSession
            ? const Center(child: CircularProgressIndicator())
            : (_user == null ? _buildRegisterForm() : _buildGameList(_user!)),
      ),
    );
  }

  Widget _buildRegisterForm() {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text('Who are you?', style: AppTypography.displayMedium),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Your name identifies you across every case on this device.',
          style: AppTypography.bodySmall,
        ),
        const SizedBox(height: AppSpacing.xl),
        DossierCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Your name'),
                onSubmitted: (_) => _register(),
              ),
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(onPressed: _register, child: const Text('Continue')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGameList(AppUser user) {
    final repo = context.watch<GameRepository>();
    return StreamBuilder<List<Game>>(
      stream: repo.watchGames(viewerId: user.id),
      builder: (context, snapshot) {
        final games = snapshot.data ?? const [];
        final visible = games.where((g) => _statusFilter.contains(g.status)).toList()
          ..sort(_sort.compare);
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text('Find your case', style: AppTypography.displayMedium),
            const SizedBox(height: AppSpacing.xs),
            Text('Signed in as ${user.displayName}.', style: AppTypography.bodySmall),
            const SizedBox(height: AppSpacing.xl),
            if (games.isNotEmpty) ...[
              _CaseListControls(
                sort: _sort,
                statusFilter: _statusFilter,
                onSortChanged: (value) => setState(() => _sort = value),
                onStatusToggled: _toggleStatusFilter,
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (games.isEmpty)
              Text('No cases open yet.', style: AppTypography.bodySmall)
            else if (visible.isEmpty)
              Text('No cases match these filters.', style: AppTypography.bodySmall)
            else
              for (final game in visible) ...[
                _GameListTile(
                  game: game,
                  selfId: user.id,
                  // Already-joined cases still go straight back in
                  // (unchanged — TESTING.md §0.9); a case you haven't
                  // joined opens its details screen first instead of
                  // joining immediately.
                  onTap: game.players.any((p) => p.id == user.id)
                      ? () => _joinAndEnter(game)
                      : () => _openDetails(game),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            const SizedBox(height: AppSpacing.xl),
            Text(
              "Don't see your case? Start a new one instead.",
              style: AppTypography.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(onPressed: _startNewCase, child: const Text('Start a new case')),
          ],
        );
      },
    );
  }
}

class _GameListTile extends StatelessWidget {
  final Game game;
  final String selfId;
  final VoidCallback onTap;

  const _GameListTile({required this.game, required this.selfId, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final alreadyJoined = game.players.any((p) => p.id == selfId);
    final ended = game.status == GameStatus.ended;
    // A closed case can still be entered by someone who was already in it
    // (to see the finale), but there's nothing to join anymore.
    final canTap = alreadyJoined || !ended;
    return DossierCard(
      child: Row(
        children: [
          SvgPicture.asset(
            AppGraphics.fingerprintDossierMark,
            width: 24,
            height: 24,
            colorFilter: const ColorFilter.mode(AppColors.textSecondary, BlendMode.srcIn),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(game.locationTag, style: AppTypography.heading),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${game.status.name} · round ${game.currentRound} · '
                  '${game.players.length}/${game.minPlayers} players',
                  style: AppTypography.bodySmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _formatAddedDate(game.createdAt),
                  style: AppTypography.dataSmall,
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: canTap ? onTap : null,
            child: Text(alreadyJoined ? 'Enter' : (ended ? 'Closed' : 'Join')),
          ),
        ],
      ),
    );
  }
}

/// The sort menu + status filter pills sitting above the case list —
/// kept as its own widget so `_PlayerEntryScreenState.build` doesn't have
/// to thread the toggle/selection logic inline.
class _CaseListControls extends StatelessWidget {
  final _SortOption sort;
  final Set<GameStatus> statusFilter;
  final ValueChanged<_SortOption> onSortChanged;
  final ValueChanged<GameStatus> onStatusToggled;

  const _CaseListControls({
    required this.sort,
    required this.statusFilter,
    required this.onSortChanged,
    required this.onStatusToggled,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final status in GameStatus.values)
              _StatusFilterPill(
                status: status,
                selected: statusFilter.contains(status),
                onTap: () => onStatusToggled(status),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        PopupMenuButton<_SortOption>(
          initialValue: sort,
          onSelected: onSortChanged,
          itemBuilder: (context) => [
            for (final option in _SortOption.values)
              PopupMenuItem(value: option, child: Text(option.label)),
          ],
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(PhosphorIconsLight.sortAscending, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.xs),
              Text('Sort: ${sort.label}', style: AppTypography.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

/// A single toggleable status filter, styled as a pill in the same hand-
/// built idiom as `VoteWeightPill` rather than a stock Material chip, so
/// it reads as part of this app's own look rather than a default widget.
class _StatusFilterPill extends StatelessWidget {
  final GameStatus status;
  final bool selected;
  final VoidCallback onTap;

  const _StatusFilterPill({required this.status, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: selected ? AppColors.brassSoft : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(
            color: selected ? AppColors.brass : AppColors.borderHairline,
            width: 1,
          ),
        ),
        child: Text(
          status.name,
          style: AppTypography.bodySmall.copyWith(
            color: selected ? AppColors.brass : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}
