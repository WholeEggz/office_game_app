import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../design/colors.dart';
import '../../design/spacing.dart';
import '../../design/typography.dart';
import '../../domain/repositories/game_repository.dart';
import '../../domain/stats/track_record.dart';
import '../common/dossier_card.dart';

/// Computes [viewerId]'s track record and pushes [TrackRecordScreen] with
/// it already in hand, rather than letting the screen fetch it internally
/// via a FutureBuilder. Inserting a large new subtree asynchronously right
/// as this screen's own push transition was finishing tripped a Flutter
/// framework semantics assertion ('!semantics.parentDataDirty') that left
/// the screen blank — rendering full content on the very first frame
/// sidesteps that race entirely.
Future<void> openTrackRecord(
  BuildContext context, {
  required String viewerId,
  required String viewerName,
}) async {
  final repo = context.read<GameRepository>();
  final record = await computeTrackRecord(repo: repo, viewerId: viewerId);
  if (!context.mounted) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => TrackRecordScreen(viewerId: viewerId, viewerName: viewerName, record: record),
    ),
  );
}

/// A player identity's cross-case track record — every case this
/// [viewerId] has ever joined, aggregated into the four headline numbers
/// (concept doc section 5: "the foundation for a future ranking/hierarchy
/// system"). Always reached via [openTrackRecord], never pushed directly,
/// so [record] is already resolved on the first frame.
class TrackRecordScreen extends StatefulWidget {
  final String viewerId;
  final String viewerName;
  final TrackRecord record;

  const TrackRecordScreen({
    super.key,
    required this.viewerId,
    required this.viewerName,
    required this.record,
  });

  @override
  State<TrackRecordScreen> createState() => _TrackRecordScreenState();
}

class _TrackRecordScreenState extends State<TrackRecordScreen> {
  late TrackRecord _record;

  @override
  void initState() {
    super.initState();
    _record = widget.record;
  }

  Future<void> _refresh() async {
    final repo = context.read<GameRepository>();
    final record = await computeTrackRecord(repo: repo, viewerId: widget.viewerId);
    if (!mounted) return;
    setState(() => _record = record);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Track Record'),
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
          children: _buildRecordChildren(widget.viewerName, _record),
        ),
      ),
    );
  }
}

List<Widget> _buildRecordChildren(String viewerName, TrackRecord record) {
  return [
    Text('Your record', style: AppTypography.displayMedium),
    const SizedBox(height: AppSpacing.xs),
    Text('$viewerName · every case leaves a trail.', style: AppTypography.bodySmall),
    const SizedBox(height: AppSpacing.xl),
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
