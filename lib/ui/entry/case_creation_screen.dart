import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/colors.dart';
import '../../design/spacing.dart';
import '../../design/typography.dart';
import '../../domain/repositories/auth_service.dart';
import '../../domain/repositories/game_repository.dart';
import '../common/dossier_card.dart';
import '../game/game_screen.dart';

/// Lets a real player configure a new case's settings before it exists,
/// rather than starting one instantly with hidden defaults.
class CaseCreationScreen extends StatefulWidget {
  final AppUser creator;

  const CaseCreationScreen({super.key, required this.creator});

  @override
  State<CaseCreationScreen> createState() => _CaseCreationScreenState();
}

class _CaseCreationScreenState extends State<CaseCreationScreen> {
  final _nameController = TextEditingController(text: 'The Office');
  // Fixed starting defaults only — nothing here suggests a value based on
  // what you typed elsewhere. Editing "villagers" doesn't touch "mafia" or
  // vice versa; "players" is just their sum, shown read-only.
  final _villagersController = TextEditingController(text: '6');
  final _mafiaCountController = TextEditingController(text: '2');
  final _dailyCutoffController = TextEditingController(text: '17:00');
  // Blank, not pre-filled — a hint shows an example instead, since this is
  // the creator's own flavor text, not a numeric setting with one obvious
  // default. Optional: shown to a prospective player before they join, but
  // blank is a normal case, not an error.
  final _rulesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Repaints the derived "players" total (and the validation warnings
    // below) live as any of the three editable fields change.
    _villagersController.addListener(_refreshSummary);
    _mafiaCountController.addListener(_refreshSummary);
    _dailyCutoffController.addListener(_refreshSummary);
  }

  @override
  void dispose() {
    _villagersController.removeListener(_refreshSummary);
    _mafiaCountController.removeListener(_refreshSummary);
    _dailyCutoffController.removeListener(_refreshSummary);
    _nameController.dispose();
    _villagersController.dispose();
    _mafiaCountController.dispose();
    _dailyCutoffController.dispose();
    _rulesController.dispose();
    super.dispose();
  }

  /// Parses "HH:mm" (24-hour) into hours/minutes, or null if the text
  /// isn't a valid two-part, in-range 24-hour time. Shared by
  /// [_parseDailyCutoff] (what actually gets used) and [_cutoffError]
  /// (whether to warn about it).
  ({int hours, int minutes})? _tryParseCutoff(String text) {
    final parts = text.trim().split(':');
    if (parts.length != 2) return null;
    final hours = int.tryParse(parts[0]);
    final minutes = int.tryParse(parts[1]);
    if (hours == null || minutes == null) return null;
    if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59) return null;
    return (hours: hours, minutes: minutes);
  }

  /// Falls back to the concept doc's own suggested default (5:00 PM) on
  /// anything unparseable rather than rejecting the input outright — see
  /// [_cutoffError] for the warning shown alongside this fallback, so the
  /// fallback is visible instead of silent.
  Duration _parseDailyCutoff(String text) {
    final parsed = _tryParseCutoff(text);
    if (parsed == null) return const Duration(hours: 17);
    return Duration(hours: parsed.hours, minutes: parsed.minutes);
  }

  String? get _villagersError =>
      int.tryParse(_villagersController.text.trim()) == null ? 'Enter a number' : null;

  String? get _mafiaError =>
      int.tryParse(_mafiaCountController.text.trim()) == null ? 'Enter a number' : null;

  String? get _cutoffError => _tryParseCutoff(_dailyCutoffController.text) == null
      ? 'Use HH:mm — using 17:00 for now'
      : null;

  void _refreshSummary() => setState(() {});

  /// Villagers and mafia are the two directly-editable counts; "players" is
  /// just their sum, shown read-only rather than editable — matches how a
  /// real case is built (recruit some villagers, decide how many are
  /// mafia), and mirrors the actual game-start floor in
  /// `LocalGameRepository._activateGame` (`mafiaCount.clamp(1, players)`)
  /// so this preview never drifts from what creating the case will really
  /// produce.
  ({int total, int villagers, int mafia}) _expectedRoster() {
    final villagers = max(0, int.tryParse(_villagersController.text.trim()) ?? 0);
    final mafia = max(1, int.tryParse(_mafiaCountController.text.trim()) ?? 2);
    return (total: villagers + mafia, villagers: villagers, mafia: mafia);
  }

  /// No separate "villagers per mafia to unlock recruitment" setting
  /// anymore — it's derived from the case's own starting split instead
  /// (e.g. 6 villagers, 2 mafia at start -> 0.33), rather than a fixed
  /// "5" no one had a reason to pick over any other number. Might expose
  /// this as its own editable, changeable-mid-game setting later; for now
  /// it's just a sensible computed default.
  double _recruitmentUnlockThreshold() {
    final roster = _expectedRoster();
    if (roster.villagers <= 0) return 0.2;
    return roster.mafia / roster.villagers;
  }

  /// Spells out the live roster numbers instead of "this many players" —
  /// a reader can check the caption against the fields above without doing
  /// the arithmetic themselves.
  String _rosterCaption() {
    final roster = _expectedRoster();
    return 'The case starts the moment ${roster.total} players have joined; '
        '${roster.mafia} of them are drawn as mafia at random. Recruitment '
        'unlocks once mafia thin out to about this same starting ratio.';
  }

  Future<void> _create() async {
    final repo = context.read<GameRepository>();
    final roster = _expectedRoster();
    final game = await repo.createGame(
      locationTag: _nameController.text.trim().isEmpty ? 'The Office' : _nameController.text.trim(),
      minPlayers: roster.total,
      creatorId: widget.creator.id,
      creatorName: widget.creator.displayName,
      mafiaCount: roster.mafia,
      recruitmentUnlockThreshold: _recruitmentUnlockThreshold(),
      executionWindow: const Duration(hours: 1),
      dailyCutoffTime: _parseDailyCutoff(_dailyCutoffController.text),
      rulesDescription: _rulesController.text.trim(),
    );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => GameScreen(gameId: game.id, playerId: widget.creator.id),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Open a new case')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text('Case settings', style: AppTypography.displayMedium),
            const SizedBox(height: AppSpacing.xl),
            DossierCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Case name'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _EditableRosterSummary(
                    villagersController: _villagersController,
                    mafiaController: _mafiaCountController,
                    roster: _expectedRoster(),
                    villagersError: _villagersError,
                    mafiaError: _mafiaError,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(_rosterCaption(), style: AppTypography.dataSmall),
                  const SizedBox(height: AppSpacing.lg),
                  _BoxedDataField(
                    fieldKey: const ValueKey('daily_cutoff_field'),
                    label: 'DAILY VOTE CUTOFF',
                    controller: _dailyCutoffController,
                    width: 80,
                    errorText: _cutoffError,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    "Votes resolve on their own at this time each day — "
                    'no one needs to press anything.',
                    style: AppTypography.dataSmall,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    key: const ValueKey('case_rules_field'),
                    controller: _rulesController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Case rules',
                      hintText: 'e.g. players use real names and departments — or: '
                          'identities are anonymous, figure it out yourself',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Optional — shown to anyone browsing this case before they join.',
                    style: AppTypography.dataSmall,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  ElevatedButton(onPressed: _create, child: const Text('Open the case')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditableRosterSummary extends StatelessWidget {
  final TextEditingController villagersController;
  final TextEditingController mafiaController;
  final ({int total, int villagers, int mafia}) roster;
  final String? villagersError;
  final String? mafiaError;

  const _EditableRosterSummary({
    required this.villagersController,
    required this.mafiaController,
    required this.roster,
    this.villagersError,
    this.mafiaError,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: AppColors.borderHairline),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RosterFigure(
            valueKey: const ValueKey('expected_roster_total'),
            label: 'players',
            value: roster.total,
            color: AppColors.textPrimary,
          ),
          _EditableRosterFigure(
            fieldKey: const ValueKey('roster_villagers_field'),
            controller: villagersController,
            label: 'villagers',
            color: AppColors.brass,
            errorText: villagersError,
          ),
          _EditableRosterFigure(
            fieldKey: const ValueKey('roster_mafia_field'),
            controller: mafiaController,
            label: 'mafia',
            color: AppColors.crimsonText,
            errorText: mafiaError,
          ),
        ],
      ),
    );
  }
}

class _EditableRosterFigure extends StatelessWidget {
  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final Color color;
  final String? errorText;

  const _EditableRosterFigure({
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.color,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 60,
          child: TextField(
            key: fieldKey,
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: AppTypography.data.copyWith(color: color, fontSize: 22),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 4),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(label, style: AppTypography.dataSmall),
        if (errorText != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            errorText!,
            textAlign: TextAlign.center,
            style: AppTypography.dataSmall.copyWith(color: AppColors.crimsonText),
          ),
        ],
      ],
    );
  }
}

class _RosterFigure extends StatelessWidget {
  final Key valueKey;
  final String label;
  final int value;
  final Color color;

  const _RosterFigure({
    required this.valueKey,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('$value', key: valueKey, style: AppTypography.data.copyWith(color: color, fontSize: 20)),
        Text(label, style: AppTypography.dataSmall),
      ],
    );
  }
}

/// A single boxed, monospace-value setting row — same `surfaceRaised` +
/// hairline-border + `data`-typography treatment as the roster summary
/// above it (design_spec.md's rule: numbers the player needs to trust are
/// monospace, not body text), so this doesn't look like an odd default
/// Material text field next to it.
class _BoxedDataField extends StatelessWidget {
  final Key fieldKey;
  final String label;
  final TextEditingController controller;
  final double width;
  final String? errorText;

  const _BoxedDataField({
    required this.fieldKey,
    required this.label,
    required this.controller,
    required this.width,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(AppRadii.sm),
            border: Border.all(color: AppColors.borderHairline),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: AppTypography.dataSmall.copyWith(color: AppColors.textSecondary)),
              ),
              SizedBox(
                width: width,
                child: TextField(
                  key: fieldKey,
                  controller: controller,
                  textAlign: TextAlign.center,
                  style: AppTypography.data.copyWith(color: AppColors.textPrimary, fontSize: 18),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 4),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(errorText!, style: AppTypography.dataSmall.copyWith(color: AppColors.crimsonText)),
        ],
      ],
    );
  }
}
