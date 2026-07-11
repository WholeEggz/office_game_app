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

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final auth = context.read<AuthService>();
    final user = await auth.signInWithDisplayName(name);
    if (!mounted) return;
    setState(() => _user = user);
  }

  Future<void> _joinAndEnter(Game game) async {
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
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GameScreen(gameId: game.id, playerId: user.id),
    ));
  }

  void _startNewCase() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CaseCreationScreen(creator: _user!),
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
        child: _user == null ? _buildRegisterForm() : _buildGameList(_user!),
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
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text('Find your case', style: AppTypography.displayMedium),
            const SizedBox(height: AppSpacing.xs),
            Text('Signed in as ${user.displayName}.', style: AppTypography.bodySmall),
            const SizedBox(height: AppSpacing.xl),
            if (games.isEmpty)
              Text('No cases open yet.', style: AppTypography.bodySmall)
            else
              for (final game in games) ...[
                _GameListTile(game: game, selfId: user.id, onTap: () => _joinAndEnter(game)),
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
                  '${game.status.name} · ${game.players.length}/${game.minPlayers} players',
                  style: AppTypography.bodySmall,
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
