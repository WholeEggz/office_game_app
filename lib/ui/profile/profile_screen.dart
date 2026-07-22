import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../design/colors.dart';
import '../../design/graphics.dart';
import '../../design/spacing.dart';
import '../../design/typography.dart';
import '../../domain/repositories/auth_service.dart';
import '../../domain/repositories/game_repository.dart';
import '../../domain/stats/achievements.dart';
import '../../domain/stats/track_record.dart';
import '../common/async_tap_guard.dart';
import '../common/autocomplete_field.dart';
import '../common/dossier_card.dart';

/// Computes [viewerId]'s track record and resolves their saved location
/// before pushing [ProfileScreen] with both already in hand, rather than
/// letting the screen fetch them internally via a FutureBuilder. Inserting
/// a large new subtree asynchronously right as this screen's own push
/// transition was finishing tripped a Flutter framework semantics
/// assertion ('!semantics.parentDataDirty') that left the screen blank —
/// rendering full content on the very first frame sidesteps that race
/// entirely.
Future<void> openProfile(
  BuildContext context, {
  required String viewerId,
  required String viewerName,
}) async {
  final repo = context.read<GameRepository>();
  final auth = context.read<AuthService>();
  final record = await computeTrackRecord(repo: repo, viewerId: viewerId);
  final profile = await auth.currentLocationProfile();
  if (!context.mounted) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ProfileScreen(
        viewerId: viewerId,
        viewerName: viewerName,
        record: record,
        initialProfile: profile,
      ),
    ),
  );
}

/// A player identity's profile: their own saved details (currently just
/// location — editable in place) plus their cross-case track record, every
/// case this [viewerId] has ever joined, aggregated into the four headline
/// numbers (concept doc section 5: "the foundation for a future ranking/
/// hierarchy system"). Always reached via [openProfile], never pushed
/// directly, so [record] and [initialProfile] are already resolved on the
/// first frame.
class ProfileScreen extends StatefulWidget {
  final String viewerId;
  final String viewerName;
  final TrackRecord record;
  final LocationProfile? initialProfile;

  const ProfileScreen({
    super.key,
    required this.viewerId,
    required this.viewerName,
    required this.record,
    required this.initialProfile,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late TrackRecord _record;
  LocationProfile? _profile;
  late final TextEditingController _countryController;
  late final TextEditingController _cityController;
  late final TextEditingController _companyController;
  bool _editingCountry = false;
  bool _editingCity = false;
  bool _editingCompany = false;

  @override
  void initState() {
    super.initState();
    _record = widget.record;
    _profile = widget.initialProfile;
    _countryController = TextEditingController(text: _profile?.country ?? '');
    _cityController = TextEditingController(text: _profile?.city ?? '');
    _companyController = TextEditingController(text: _profile?.companyOrOffice ?? '');
  }

  @override
  void dispose() {
    _countryController.dispose();
    _cityController.dispose();
    _companyController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final repo = context.read<GameRepository>();
    final auth = context.read<AuthService>();
    final record = await computeTrackRecord(repo: repo, viewerId: widget.viewerId);
    final profile = await auth.currentLocationProfile();
    if (!mounted) return;
    setState(() {
      _record = record;
      _profile = profile;
      _countryController.text = profile?.country ?? '';
      _cityController.text = profile?.city ?? '';
      _companyController.text = profile?.companyOrOffice ?? '';
      _editingCountry = false;
      _editingCity = false;
      _editingCompany = false;
    });
  }

  /// Saves whichever field's checkmark was tapped, alongside the other
  /// two fields' current (last-saved, if not also being edited) values —
  /// `updateLocationProfile` takes the full triple, matching
  /// `signInWithDisplayName`'s location parameters and the
  /// `saveLocationProfile` Cloud Function underneath.
  Future<void> _saveLocation() async {
    final country = _countryController.text.trim();
    final city = _cityController.text.trim();
    final company = _companyController.text.trim();
    if (country.isEmpty || city.isEmpty || company.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Country, city, and company are all required.')),
      );
      return;
    }
    final auth = context.read<AuthService>();
    try {
      await auth.updateLocationProfile(country: country, city: city, companyOrOffice: company);
      if (!mounted) return;
      setState(() {
        _profile = (country: country, city: city, companyOrOffice: company);
        _editingCountry = false;
        _editingCity = false;
        _editingCompany = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: Icon(PhosphorIconsLight.arrowClockwise, color: AppColors.textSecondary),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(widget.viewerName, style: AppTypography.displayMedium),
            const SizedBox(height: AppSpacing.xs),
            Text('Your profile and every case you\'ve been part of.', style: AppTypography.bodySmall),
            const SizedBox(height: AppSpacing.xl),
            DossierCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your details', style: AppTypography.heading),
                  const SizedBox(height: AppSpacing.sm),
                  _LocationRow(
                    label: 'Country',
                    value: _profile?.country,
                    controller: _countryController,
                    editing: _editingCountry,
                    suggest: auth.suggestCountries,
                    onEdit: () => setState(() => _editingCountry = true),
                    onCancel: () => setState(() {
                      _countryController.text = _profile?.country ?? '';
                      _editingCountry = false;
                    }),
                    onSave: _saveLocation,
                  ),
                  _LocationRow(
                    label: 'City',
                    value: _profile?.city,
                    controller: _cityController,
                    editing: _editingCity,
                    suggest: auth.suggestCities,
                    onEdit: () => setState(() => _editingCity = true),
                    onCancel: () => setState(() {
                      _cityController.text = _profile?.city ?? '';
                      _editingCity = false;
                    }),
                    onSave: _saveLocation,
                  ),
                  _LocationRow(
                    label: 'Company or office',
                    value: _profile?.companyOrOffice,
                    controller: _companyController,
                    editing: _editingCompany,
                    suggest: auth.suggestCompanies,
                    onEdit: () => setState(() => _editingCompany = true),
                    onCancel: () => setState(() {
                      _companyController.text = _profile?.companyOrOffice ?? '';
                      _editingCompany = false;
                    }),
                    onSave: _saveLocation,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            _RankAndBadgesCard(record: _record),
            const SizedBox(height: AppSpacing.xl),
            ..._buildRecordChildren(_record),
          ],
        ),
      ),
    );
  }
}

/// A single "Your details" row: a read-only label + value with a pencil
/// button, or (while [editing]) an [AutocompleteField] with save/cancel
/// buttons — reused identically across country/city/company.
class _LocationRow extends StatelessWidget {
  final String label;
  final String? value;
  final TextEditingController controller;
  final bool editing;
  final Future<List<String>> Function(String prefix) suggest;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final Future<void> Function() onSave;

  const _LocationRow({
    required this.label,
    required this.value,
    required this.controller,
    required this.editing,
    required this.suggest,
    required this.onEdit,
    required this.onCancel,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    if (!editing) {
      final display = (value == null || value!.isEmpty) ? 'Not set' : value!;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTypography.bodySmall),
                  Text(display, style: AppTypography.dataSmall),
                ],
              ),
            ),
            IconButton(
              icon: Icon(PhosphorIconsLight.pencilSimple, color: AppColors.textSecondary),
              tooltip: 'Edit $label',
              onPressed: onEdit,
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: AutocompleteField(controller: controller, label: label, suggest: suggest)),
          const SizedBox(width: AppSpacing.xs),
          AsyncTapGuard(
            onTap: onSave,
            builder: (context, onPressed, busy) => IconButton(
              icon: busy
                  ? asyncTapGuardSpinner
                  : Icon(PhosphorIconsLight.check, color: AppColors.brass),
              tooltip: 'Save',
              onPressed: onPressed,
            ),
          ),
          IconButton(
            icon: Icon(PhosphorIconsLight.x, color: AppColors.textSecondary),
            tooltip: 'Cancel',
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

/// A flat, full-saturation image rendered at reduced opacity reads as
/// "dim", not "locked" — this desaturates it to grey first so a locked
/// rank/badge's gold icon actually looks inert, the way a real medal
/// would if it hadn't been struck yet.
const _greyscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0, 0, 0, 1, 0,
]);

/// "Rank & badges" — sits between "Your details" and the track record
/// stats: a horizontally scrolling rank ladder (see `achievements.dart`'s
/// `Rank`, gated purely on [TrackRecord.casesPlayed]) followed by a
/// horizontally scrolling row of every badge in [allBadges], unlocked or
/// not — locked ones stay visible (dimmed and desaturated) so there's
/// something visible to chase, rather than only ever showing what's
/// already earned.
class _RankAndBadgesCard extends StatelessWidget {
  final TrackRecord record;

  const _RankAndBadgesCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final rank = Rank.forCasesPlayed(record.casesPlayed);
    final next = rank.next;
    return DossierCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Rank & badges', style: AppTypography.heading),
          const SizedBox(height: AppSpacing.xs),
          Text(
            next == null
                ? '${rank.label} — top rank reached.'
                : '${rank.label} · ${record.casesPlayed}/${next.minCasesPlayed} cases to ${next.label}',
            style: AppTypography.dataSmall,
          ),
          const SizedBox(height: AppSpacing.md),
          // A fixed-height SizedBox around these rows used to hold a
          // guessed pixel height for "icon + up to 2 lines of label" —
          // fragile by construction: it overflowed as soon as a label
          // actually wrapped to 2 lines (e.g. "Chief Inspector"), and
          // again at any larger accessibility text-scale setting even for
          // labels that fit at the default scale (see
          // profile_screen_badges_test.dart). A SingleChildScrollView
          // around a plain Row has no height of its own to guess — it
          // just sizes to whatever its tallest tile actually needs, at
          // any text scale. Only 6 ranks, so building them all eagerly
          // (no lazy ListView) costs nothing.
          SingleChildScrollView(
            key: const ValueKey('rank_ladder_list'),
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final tier in Rank.values) ...[
                  _RankTile(rank: tier, reached: record.casesPlayed >= tier.minCasesPlayed, current: tier == rank),
                  if (tier != Rank.values.last) const SizedBox(width: AppSpacing.sm),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Badges', style: AppTypography.body),
          const SizedBox(height: AppSpacing.sm),
          // Same reasoning as the rank ladder above — only 12 badges, so
          // eagerly building them all is still cheap.
          SingleChildScrollView(
            key: const ValueKey('badges_list'),
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final badge in allBadges) ...[
                  _BadgeTile(def: badge, unlocked: badge.isUnlocked(record)),
                  if (badge != allBadges.last) const SizedBox(width: AppSpacing.sm),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One stop on the horizontally scrolling rank ladder — [current] gets a
/// brass border and full-size art; every other already-[reached] tier
/// still renders in color (a trail of "already climbed" ranks behind the
/// active one), while anything still ahead is desaturated and dimmed.
class _RankTile extends StatelessWidget {
  final Rank rank;
  final bool reached;
  final bool current;

  const _RankTile({required this.rank, required this.reached, required this.current});

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(_imageForRank(rank), width: 56, height: 56, fit: BoxFit.contain);
    return Container(
      width: 84,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: current ? AppColors.brassSoft : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: current ? AppColors.brass : AppColors.borderHairline, width: current ? 2 : 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          reached ? image : Opacity(opacity: 0.45, child: ColorFiltered(colorFilter: _greyscale, child: image)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            rank.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall.copyWith(
              color: current ? AppColors.brass : (reached ? AppColors.textSecondary : AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// One card in the horizontally scrolling badge row — locked badges stay
/// visible (dimmed/desaturated, per the design decision to always show
/// the full set) with a small lock glyph, rather than being hidden until
/// earned.
class _BadgeTile extends StatelessWidget {
  final BadgeDef def;
  final bool unlocked;

  const _BadgeTile({required this.def, required this.unlocked});

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(_imageForBadge(def.id), width: 72, height: 72, fit: BoxFit.contain);
    return Tooltip(
      message: def.description,
      child: Container(
        width: 100,
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: unlocked ? AppColors.brassSoft : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: unlocked ? AppColors.brass : AppColors.borderHairline, width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                unlocked ? image : Opacity(opacity: 0.4, child: ColorFiltered(colorFilter: _greyscale, child: image)),
                if (!unlocked)
                  Icon(PhosphorIconsLight.lockSimple, size: 20, color: AppColors.textMuted),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              def.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmall.copyWith(
                color: unlocked ? AppColors.brass : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _imageForRank(Rank rank) => switch (rank) {
      Rank.rookie => AppGraphics.rankRookie,
      Rank.associate => AppGraphics.rankAssociate,
      Rank.detective => AppGraphics.rankDetective,
      Rank.inspector => AppGraphics.rankInspector,
      Rank.chiefInspector => AppGraphics.rankChiefInspector,
      Rank.legend => AppGraphics.rankLegend,
    };

String _imageForBadge(BadgeId id) => switch (id) {
      BadgeId.firstCase => AppGraphics.badgeFirstCase,
      BadgeId.caseClosed => AppGraphics.badgeCaseClosed,
      BadgeId.sharpEye => AppGraphics.badgeSharpEye,
      BadgeId.bloodhound => AppGraphics.badgeBloodhound,
      BadgeId.perfectRead => AppGraphics.badgePerfectRead,
      BadgeId.onARoll => AppGraphics.badgeOnARoll,
      BadgeId.unstoppable => AppGraphics.badgeUnstoppable,
      BadgeId.undercover => AppGraphics.badgeUndercover,
      BadgeId.ghost => AppGraphics.badgeGhost,
      BadgeId.recruiter => AppGraphics.badgeRecruiter,
      BadgeId.veteran => AppGraphics.badgeVeteran,
      BadgeId.centuryClub => AppGraphics.badgeCenturyClub,
    };

List<Widget> _buildRecordChildren(TrackRecord record) {
  return [
    Text('Track record', style: AppTypography.heading),
    const SizedBox(height: AppSpacing.lg),
    if (record.casesPlayed == 0)
      Text(
        "Nothing on file yet — this fills in once your first case's first "
        'round resolves.',
        style: AppTypography.bodySmall,
      )
    else ...[
      // Two explicit rows rather than a GridView.count with a fixed
      // childAspectRatio — a fixed aspect ratio is a fixed-height
      // container around text, which clips instead of growing under
      // system text scaling (design_spec.md §9). CrossAxisAlignment
      // .stretch matches each row's two tiles to the taller one's
      // natural height instead — wrapped in IntrinsicHeight because a
      // bare Row directly inside a ListView gets unbounded (infinite)
      // height, and stretch needs a real height to stretch children to.
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _StatTile(
                icon: PhosphorIconsLight.magnifyingGlass,
                label: 'Correct unmasks',
                value: '${record.correctUnmasks}',
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _StatTile(
                icon: PhosphorIconsLight.maskHappy,
                label: 'Survived as Informant',
                value: '${record.survivedAsMafiaCount}',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _StatTile(
                icon: PhosphorIconsLight.target,
                label: 'Vote accuracy',
                value: record.voteAccuracy == null
                    ? '—'
                    : '${(record.voteAccuracy! * 100).round()}%',
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _StatTile(
                icon: PhosphorIconsLight.fire,
                label: 'Current streak',
                value: '${record.currentStreak}',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      DossierCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Case history', style: AppTypography.heading),
            const SizedBox(height: AppSpacing.sm),
            _HistoryRow(
              label: 'Cases played',
              value:
                  '${record.casesPlayed} (${record.casesAsWitness} as Witness, '
                  '${record.casesAsInformant} as Informant)',
            ),
            _HistoryRow(
              label: 'Cases closed',
              value: '${record.casesWon} won · ${record.casesLost} lost',
            ),
            _HistoryRow(label: 'Votes cast', value: '${record.votesCast}'),
          ],
        ),
      ),
    ],
  ];
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatTile({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return DossierCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(height: AppSpacing.sm),
          // Bumped past the data style's usual 15px — this is the one
          // place a stat is the headline of the card rather than a
          // supporting number next to a label (unlike the vote-weight
          // pill), so it earns the extra size while staying in the same
          // JetBrains Mono "this is data" family.
          Text(value, style: AppTypography.data.copyWith(fontSize: 28, color: AppColors.brass)),
          const SizedBox(height: AppSpacing.xs),
          Text(label, style: AppTypography.bodySmall),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final String label;
  final String value;

  const _HistoryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: AppTypography.bodySmall)),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(value, style: AppTypography.dataSmall, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}
