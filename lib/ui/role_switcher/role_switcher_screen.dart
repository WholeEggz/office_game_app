import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../design/colors.dart';
import '../../design/graphics.dart';
import '../../design/spacing.dart';
import '../../design/typography.dart';
import '../../domain/models/game.dart';
import '../../domain/models/player.dart';
import '../../domain/repositories/auth_service.dart';
import '../../domain/repositories/game_repository.dart';
import '../common/dossier_card.dart';
import '../game/game_screen.dart';

/// Debug-only entry point (implementation_plan.md, Phase 1a): create a
/// game, add several named players on one device, start it, and jump into
/// each player's own view. None of this exists once there's a real backend
/// with real, separate devices per player.
class RoleSwitcherScreen extends StatefulWidget {
  const RoleSwitcherScreen({super.key});

  @override
  State<RoleSwitcherScreen> createState() => _RoleSwitcherScreenState();
}

class _RoleSwitcherScreenState extends State<RoleSwitcherScreen> {
  String? _gameId;

  final _locationController = TextEditingController(text: 'Third Floor');
  final _minPlayersController = TextEditingController(text: '8');
  final _creatorNameController = TextEditingController();
  final _joinNameController = TextEditingController();

  // Stock roster for "Quick start" — so testing the rules doesn't require
  // retyping 8 names after every hot restart / app reload.
  static const _quickStartNames = [
    'Alice',
    'Ben',
    'Cara',
    'Deshawn',
    'Elena',
    'Farid',
    'Grace',
    'Hiro',
  ];

  @override
  void dispose() {
    _locationController.dispose();
    _minPlayersController.dispose();
    _creatorNameController.dispose();
    _joinNameController.dispose();
    super.dispose();
  }

  Future<void> _createGame() async {
    final name = _creatorNameController.text.trim();
    if (name.isEmpty) return;
    final auth = context.read<AuthService>();
    final repo = context.read<GameRepository>();
    try {
      final user = await auth.signInWithDisplayName(name);
      final minPlayers = int.tryParse(_minPlayersController.text.trim()) ?? 8;
      final game = await repo.createGame(
        locationTag: _locationController.text.trim().isEmpty
            ? 'The Office'
            : _locationController.text.trim(),
        minPlayers: minPlayers,
        creatorId: user.id,
        creatorName: user.displayName,
      );
      if (!mounted) return;
      setState(() => _gameId = game.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not open the case: $e')));
    }
  }

  Future<void> _quickStart() async {
    final auth = context.read<AuthService>();
    final repo = context.read<GameRepository>();
    try {
      // registerNewPlayer, not signInWithDisplayName: these stock names are
      // disposable per quick-started game, not "you" resuming an identity —
      // reusing an id by name match here is exactly what caused "already
      // joined this game" when the same stock roster got reused elsewhere.
      final creator = await auth.registerNewPlayer(_quickStartNames.first);
      final game = await repo.createGame(
        locationTag: 'Third Floor',
        minPlayers: _quickStartNames.length,
        creatorId: creator.id,
        creatorName: creator.displayName,
        // Explicit rather than relying on createGame's own conservative
        // default (1) — 2 mafia members is what actually exercises
        // multi-member-agreement testing (§4, §3.3) that a single-mafia
        // game can't.
        mafiaCount: 2,
      );
      for (final name in _quickStartNames.skip(1)) {
        final user = await auth.registerNewPlayer(name);
        await repo.addPlayer(gameId: game.id, playerId: user.id, name: user.displayName);
      }
      await repo.startGame(game.id);
      if (!mounted) return;
      setState(() => _gameId = game.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not quick-start: $e')));
    }
  }

  Future<void> _joinGame(Game game) async {
    final name = _joinNameController.text.trim();
    if (name.isEmpty) return;
    final auth = context.read<AuthService>();
    final repo = context.read<GameRepository>();
    try {
      // Always a fresh identity — two simulated coworkers can share a first
      // name, and reusing an existing id here is what used to throw
      // "already joined this game" when the typed name matched someone
      // already in it. The repository still rejects a *duplicate name in
      // this roster* on purpose (see below), just no longer confuses that
      // with "duplicate identity".
      final user = await auth.registerNewPlayer(name);
      await repo.addPlayer(gameId: game.id, playerId: user.id, name: user.displayName);
      _joinNameController.clear();
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not join: $e')));
    }
  }

  Future<void> _enterAs(Player player) async {
    final auth = context.read<AuthService>();
    try {
      await auth.switchToUser(player.id);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => GameScreen(gameId: _gameId!, playerId: player.id),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not switch player: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('The Office Case — Setup')),
      body: SafeArea(
        child: _gameId == null ? _buildSetupForm() : _buildRoster(),
      ),
    );
  }

  Widget _buildSetupForm() {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text('Open a new case', style: AppTypography.displayMedium),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'One device, several identities — switch between players to test the rules '
          'before this runs on separate phones.',
          style: AppTypography.bodySmall,
        ),
        const SizedBox(height: AppSpacing.xl),
        DossierCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _locationController,
                decoration: const InputDecoration(labelText: 'Location tag'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _minPlayersController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Minimum players to start'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _creatorNameController,
                decoration: const InputDecoration(labelText: 'Your name'),
              ),
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(
                onPressed: _createGame,
                child: const Text('Open the case'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          'Skip setup — creates and starts an 8-player game '
          '(${_quickStartNames.join(', ')}) instantly.',
          style: AppTypography.bodySmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton(
          onPressed: _quickStart,
          child: const Text('Quick start (8 players)'),
        ),
      ],
    );
  }

  Widget _buildRoster() {
    final repo = context.watch<GameRepository>();
    return StreamBuilder<Game>(
      stream: repo.watchGame(_gameId!),
      builder: (context, snapshot) {
        final game = snapshot.data;
        if (game == null) {
          return const Center(child: CircularProgressIndicator(color: AppColors.brass));
        }
        final canStart =
            game.status == GameStatus.recruiting && game.players.length >= game.minPlayers;
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            DossierCard(
              child: Row(
                children: [
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
                      ],
                    ),
                  ),
                  SvgPicture.asset(
                    AppGraphics.fingerprintDossierMark,
                    width: 24,
                    height: 24,
                    colorFilter: const ColorFilter.mode(AppColors.textSecondary, BlendMode.srcIn),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _joinNameController,
                    decoration: const InputDecoration(labelText: 'New player name'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                OutlinedButton(
                  onPressed: () => _joinGame(game),
                  child: const Text('Add & join'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (game.status == GameStatus.recruiting)
              ElevatedButton(
                onPressed: canStart ? () => repo.startGame(game.id) : null,
                child: Text(canStart
                    ? 'Start the game'
                    : 'Need ${game.minPlayers - game.players.length} more players'),
              ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Debug roster — real roles, never shown to a real player like this',
              style: AppTypography.dataSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final player in game.players)
              Container(
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.borderHairline)),
                ),
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(player.name, style: AppTypography.body),
                          Text(
                            player.wasUnmasked
                                ? 'unmasked ${player.role.name}'
                                : player.role.name,
                            style: AppTypography.dataSmall.copyWith(
                              color: player.role == PlayerRole.mafia
                                  ? AppColors.crimsonText
                                  : AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => _enterAs(player),
                      child: const Text('Enter'),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
