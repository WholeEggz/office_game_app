import 'dart:async';

import 'package:flutter/foundation.dart';
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
import '../common/async_tap_guard.dart';
import '../common/autocomplete_field.dart';
import '../common/dossier_card.dart';
import '../game/game_screen.dart';
import '../help/help_screen.dart';
import '../stats/track_record_screen.dart';
import 'app_entry_gate.dart';
import 'case_creation_screen.dart';
import 'case_details_screen.dart';

/// Prompts for a restricted case's 3-word passphrase — returns the words
/// typed (untrimmed, unnormalized; `GameRepository.verifyPassphrase`/
/// `addPlayer` do that comparison) or null if cancelled. Order is never
/// asked for as anything other than 3 blanks side by side; verification
/// itself is set-based, so which blank each word landed in doesn't matter.
Future<List<String>?> _showPassphraseEntryDialog(BuildContext context, {required String caseName}) {
  return showDialog<List<String>>(
    context: context,
    builder: (dialogContext) => _PassphraseEntryDialog(caseName: caseName),
  );
}

/// The passphrase dialog's content, as its own `State` so its
/// `TextEditingController`s are disposed when this widget is actually
/// removed from the tree (once the dialog's dismiss animation finishes) —
/// disposing them eagerly the instant `showDialog` returns races that
/// animation and crashes (see game_screen.dart's `_ReportDialog`, which
/// hit exactly this).
class _PassphraseEntryDialog extends StatefulWidget {
  final String caseName;

  const _PassphraseEntryDialog({required this.caseName});

  @override
  State<_PassphraseEntryDialog> createState() => _PassphraseEntryDialogState();
}

class _PassphraseEntryDialogState extends State<_PassphraseEntryDialog> {
  final _controllers = List.generate(3, (_) => TextEditingController());

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('"${widget.caseName}" is restricted'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Enter the 3-word passphrase to see this case (order doesn't matter).",
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _controllers[i],
                    autofocus: i == 0,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(hintText: 'word ${i + 1}'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controllers.map((c) => c.text).toList()),
          child: const Text('Unlock'),
        ),
      ],
    );
  }
}

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
String _normalizeLocation(String value) => value.trim().toLowerCase();

/// The strongest match between [game]'s creator location and the
/// [viewer]'s own saved profile — 0 (company), 1 (city), 2 (country), or
/// 3 (no match, including when [viewer] itself is null). Blank fields
/// never count as a match on either side, so two cases that both simply
/// never recorded a location don't spuriously "match" each other.
int _locationTier(Game game, LocationProfile? viewer) {
  if (viewer == null) return 3;
  final company = _normalizeLocation(viewer.companyOrOffice);
  final city = _normalizeLocation(viewer.city);
  final country = _normalizeLocation(viewer.country);
  if (company.isNotEmpty && _normalizeLocation(game.creatorCompanyOrOffice) == company) return 0;
  if (city.isNotEmpty && _normalizeLocation(game.creatorCity) == city) return 1;
  if (country.isNotEmpty && _normalizeLocation(game.creatorCountry) == country) return 2;
  return 3;
}

String? _locationTierBadge(int tier) => switch (tier) {
      0 => 'Your company',
      1 => 'Your city',
      2 => 'Your country',
      _ => null,
    };

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
  final _countryController = TextEditingController();
  final _cityController = TextEditingController();
  final _companyController = TextEditingController();
  AppUser? _user;
  // The viewer's own saved location — used purely to float cases at a
  // matching company/city/country to the top of "Find your case" (see
  // _locationTier below); null before it's resolved, or for a debug
  // identity with nothing saved, in which case every case just sorts as
  // "no match" (unchanged behavior).
  LocationProfile? _viewerProfile;
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
    final auth = context.read<AuthService>();
    final resumed = await auth.resumeSession();
    final profile = resumed == null ? null : await auth.currentLocationProfile();
    // Nothing to resume means the registration form is about to show —
    // its location fields query Firestore collections gated on
    // isSignedIn() (see ensureSignedIn's doc comment) as soon as the
    // player starts typing, well before "Continue" would otherwise
    // establish any session at all.
    if (resumed == null) await auth.ensureSignedIn();
    if (!mounted) return;
    setState(() {
      _user = resumed;
      _viewerProfile = profile;
      _resumingSession = false;
    });
  }

  /// Debug-only: signs out and resets straight back to the very first
  /// screen a cold launch shows (WelcomeScreen, via AppEntryGate — see its
  /// own doc comment), clearing the whole navigation stack so there's no
  /// stale signed-in screen left to "back" into. Exists purely so testing
  /// the registration/welcome flow repeatedly doesn't require reinstalling
  /// the app or clearing its storage by hand.
  Future<void> _debugSignOut() async {
    await context.read<AuthService>().signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AppEntryGate()),
      (route) => false,
    );
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
    _countryController.dispose();
    _cityController.dispose();
    _companyController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final name = _nameController.text.trim();
    final country = _countryController.text.trim();
    final city = _cityController.text.trim();
    final company = _companyController.text.trim();
    // All 4 fields required — location is what makes a later "find your
    // case" pass possible, so a partial profile isn't useful to collect.
    if (name.isEmpty || country.isEmpty || city.isEmpty || company.isEmpty) return;
    final auth = context.read<AuthService>();
    try {
      final user = await auth.signInWithDisplayName(
        name,
        country: country,
        city: city,
        companyOrOffice: company,
      );
      if (!mounted) return;
      setState(() {
        _user = user;
        _viewerProfile = (country: country, city: city, companyOrOffice: company);
      });
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
  /// as the direct "Enter" path below does). [passphraseWords] only
  /// matters for a not-yet-joined restricted case — already-joined cases
  /// never need it again (`addPlayer` isn't even called for them).
  Future<void> _joinAndEnter(Game game, {List<String>? passphraseWords, bool replace = false}) async {
    final user = _user!;
    final repo = context.read<GameRepository>();
    final alreadyJoined = game.players.any((p) => p.id == user.id);
    if (!alreadyJoined) {
      try {
        await repo.addPlayer(
          gameId: game.id,
          playerId: user.id,
          name: user.displayName,
          passphraseWords: passphraseWords,
        );
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

  void _openDetails(Game game, {List<String>? passphraseWords}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CaseDetailsScreen(
        game: game,
        onJoin: () => _joinAndEnter(game, passphraseWords: passphraseWords, replace: true),
      ),
    ));
  }

  /// Tapping a not-yet-joined restricted case: prompts for its 3 words,
  /// checks them with [GameRepository.verifyPassphrase] (read-only — see
  /// that method's doc), and only opens the details screen on a match.
  /// Cancelling the dialog (returns null) just does nothing, same as
  /// tapping outside any other non-committal dialog in this app.
  Future<void> _unlockRestrictedCase(Game game) async {
    final words = await _showPassphraseEntryDialog(context, caseName: game.locationTag);
    if (words == null) return;
    if (!mounted) return;
    final repo = context.read<GameRepository>();
    final matches = await repo.verifyPassphrase(gameId: game.id, words: words);
    if (!mounted) return;
    if (!matches) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incorrect passphrase.')),
      );
      return;
    }
    _openDetails(game, passphraseWords: words);
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
          if (kDebugMode && _user != null)
            IconButton(
              icon: Icon(PhosphorIconsLight.signOut, color: AppColors.textSecondary),
              tooltip: 'Sign out (debug)',
              onPressed: _debugSignOut,
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
    final auth = context.read<AuthService>();
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text('Who are you?', style: AppTypography.displayMedium),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Your name and location identify you across every case on this '
          'device, and help others find their coworkers\' cases.',
          style: AppTypography.bodySmall,
        ),
        const SizedBox(height: AppSpacing.xl),
        DossierCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Your name'),
                onSubmitted: (_) => _register(),
              ),
              const SizedBox(height: AppSpacing.lg),
              AutocompleteField(
                controller: _countryController,
                label: 'Country',
                suggest: auth.suggestCountries,
              ),
              const SizedBox(height: AppSpacing.lg),
              AutocompleteField(
                controller: _cityController,
                label: 'City',
                suggest: auth.suggestCities,
              ),
              const SizedBox(height: AppSpacing.lg),
              AutocompleteField(
                controller: _companyController,
                label: 'Company or office name',
                suggest: auth.suggestCompanies,
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
        // Cases at the viewer's own company/city/country float to the top
        // (in that order of strength) — see _locationTier — falling back
        // to the chosen sort option within each tier, same as before.
        final visible = games.where((g) => _statusFilter.contains(g.status)).toList()
          ..sort((a, b) {
            final tierCompare = _locationTier(a, _viewerProfile).compareTo(
              _locationTier(b, _viewerProfile),
            );
            return tierCompare != 0 ? tierCompare : _sort.compare(a, b);
          });
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
                  locationBadge: _locationTierBadge(_locationTier(game, _viewerProfile)),
                  // Already-joined cases still go straight back in
                  // (unchanged — TESTING.md §0.9); a not-yet-joined
                  // restricted case is gated behind its passphrase first;
                  // any other not-yet-joined case opens its details screen
                  // directly, same as before.
                  // The restricted branch deliberately doesn't await
                  // _unlockRestrictedCase itself — it opens a modal
                  // passphrase dialog almost immediately and then waits on
                  // the user to type into it, which could be a long wait
                  // with nothing wrong; tying this button's busy/disabled
                  // state to that whole span would leave it spinning the
                  // entire time (and, in tests, hang pumpAndSettle) for no
                  // real reason — the dialog's own barrier already blocks
                  // re-tapping this tile underneath it once it's up.
                  onTap: game.players.any((p) => p.id == user.id)
                      ? () => _joinAndEnter(game)
                      : (game.isRestricted
                          ? () async => unawaited(_unlockRestrictedCase(game))
                          : () async => _openDetails(game)),
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
  final String? locationBadge;
  final Future<void> Function() onTap;

  const _GameListTile({
    required this.game,
    required this.selfId,
    required this.locationBadge,
    required this.onTap,
  });

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
                Row(
                  children: [
                    if (game.isRestricted) ...[
                      Icon(PhosphorIconsLight.lock, size: 15, color: AppColors.brass),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                    Expanded(child: Text(game.locationTag, style: AppTypography.heading)),
                  ],
                ),
                if (locationBadge != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    locationBadge!,
                    style: AppTypography.dataSmall.copyWith(color: AppColors.brass),
                  ),
                ],
                const SizedBox(height: AppSpacing.xs),
                Text(
                  game.isRestricted
                      ? '${game.status.name} · round ${game.currentRound} · '
                          '${game.players.length}/${game.minPlayers} players · Restricted'
                      : '${game.status.name} · round ${game.currentRound} · '
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
          AsyncTapGuard(
            onTap: onTap,
            builder: (context, onPressed, busy) => OutlinedButton(
              onPressed: canTap ? onPressed : null,
              child: busy
                  ? asyncTapGuardSpinner
                  : Text(alreadyJoined
                      ? 'Enter'
                      : (ended ? 'Closed' : (game.isRestricted ? 'Unlock' : 'Join'))),
            ),
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
