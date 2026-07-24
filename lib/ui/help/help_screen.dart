import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../design/colors.dart';
import '../../design/spacing.dart';
import '../../design/typography.dart';

/// A block of prose within a [_Section] — either a plain paragraph or a
/// bullet list. Content is hand-ported from `USER_MANUAL.md` (source of
/// truth for the rules text) rather than rendered from the file directly,
/// so it can use the app's own type scale instead of a generic markdown
/// stylesheet. Keep the two in sync when either changes.
sealed class _Block {
  const _Block();
  String get searchableText;
}

class _Para extends _Block {
  final String text;
  const _Para(this.text);
  @override
  String get searchableText => text;
}

class _Bullets extends _Block {
  final List<String> items;
  const _Bullets(this.items);
  @override
  String get searchableText => items.join(' ');
}

class _Section {
  final String title;
  final List<_Block> blocks;
  _Section(this.title, this.blocks);

  late final String _searchable =
      ('$title ${blocks.map((b) => b.searchableText).join(' ')}').toLowerCase();

  bool matches(String query) => query.isEmpty || _searchable.contains(query.toLowerCase());
}

/// `**bold**` markers are the only markup this content uses — a plain
/// two-pass parse (split on bold, then highlight matches within each
/// piece) is enough, no need for a full markdown parser.
List<InlineSpan> _renderInline(String text, TextStyle base, String query) {
  final spans = <InlineSpan>[];
  final boldPattern = RegExp(r'\*\*(.+?)\*\*');
  var cursor = 0;
  for (final match in boldPattern.allMatches(text)) {
    if (match.start > cursor) {
      spans.addAll(_withHighlight(text.substring(cursor, match.start), base, query));
    }
    spans.addAll(_withHighlight(
      match.group(1)!,
      base.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
      query,
    ));
    cursor = match.end;
  }
  if (cursor < text.length) {
    spans.addAll(_withHighlight(text.substring(cursor), base, query));
  }
  return spans;
}

List<InlineSpan> _withHighlight(String text, TextStyle style, String query) {
  if (query.isEmpty) return [TextSpan(text: text, style: style)];
  final spans = <InlineSpan>[];
  final lowerText = text.toLowerCase();
  final lowerQuery = query.toLowerCase();
  var start = 0;
  int index;
  while ((index = lowerText.indexOf(lowerQuery, start)) != -1) {
    if (index > start) spans.add(TextSpan(text: text.substring(start, index), style: style));
    spans.add(TextSpan(
      text: text.substring(index, index + query.length),
      style: style.copyWith(
        backgroundColor: AppColors.brassSoft,
        color: AppColors.brass,
        fontWeight: FontWeight.w700,
      ),
    ));
    start = index + query.length;
  }
  if (start < text.length) spans.add(TextSpan(text: text.substring(start), style: style));
  return spans;
}

/// Mirrors `USER_MANUAL.md` section-for-section (split a little finer, so
/// search results land on a more specific heading), condensed for
/// on-screen reading.
final List<_Section> _sections = [
  _Section('The premise', [
    _Para(
      "Somewhere in your office, a case has opened. A handful of people have "
      "been secretly drawn as **the Mafia** — everyone else is a **Witness**. "
      "The Mafia is quietly working to thin out the Witnesses; the Witnesses "
      "are trying to figure out who's Mafia before that happens. Nobody is "
      "ever kicked out of the game — the worst that happens to a Witness is "
      "losing influence, not losing their seat.",
    ),
    _Para(
      'There\'s no "night phase" — everything happens asynchronously through '
      'the app, at whatever pace your real workday allows.',
    ),
  ]),
  _Section('Joining a case', [
    _Bullets([
      'Open the app and choose **Continue as a player**, then enter your name.',
      '**Find your case** lists every case currently open at your location. '
          'Tap **Join** on one to enter it, or **Start a new case** to open '
          'your own.',
      "Once you've joined, that same case always shows **Enter** instead of "
          "**Join** — tapping it takes you straight back to your dashboard.",
    ]),
    _Para(
      'A case starts itself automatically the moment enough people have '
      'joined — there\'s no separate "start" step for a real player to '
      'press. The moment it starts, roles are drawn: a handful of players '
      'become Mafia, and everyone else is a Witness.',
    ),
  ]),
  _Section('Your two possible roles', [
    _Para(
      '**Witness** — the default, public role. You have nothing to hide. '
      'You vote, log observations, and watch for the day\'s elimination '
      'signal like everyone else.',
    ),
    _Para(
      '**Informant** — the hidden, Mafia role. You coordinate secretly with '
      'the other Informants through **the Wire**, and you know you\'re '
      'being hunted.',
    ),
    _Para(
      'The moment your role is set (or changes), you get a short reveal: '
      '"You are a Witness" or "You are the Informant." From then on your '
      'dashboard looks a little different depending on which one you are — '
      'Informants get an extra section (the Wire) that Witnesses never see.',
    ),
  ]),
  _Section('Vote weight — no one is ever removed', [
    _Para('Every Witness starts with **3 vote weight**. This is your influence, not your life:'),
    _Bullets([
      'When the Mafia successfully marks you, or you cast the round\'s '
          'winning vote against a fellow Witness by mistake, you lose 1 '
          'weight (down to a floor of 0 — it never goes negative).',
      "At 0 weight you're still fully in the game — you can still vote, it "
          "just doesn't add anything to the tally anymore.",
      'Correctly help unmask an Informant, and everyone who voted for them '
          'gains +1 weight as a reward.',
      'Your own weight is only ever visible to you. Nobody else can see it '
          'drop — a visible drop would otherwise be a public "confirmed not '
          'Mafia" stamp, which defeats the point of staying uncertain.',
    ]),
  ]),
  _Section('Casting votes and the daily cutoff', [
    _Para(
      'Open **The Roster** to see everyone in the case and cast your vote '
      'for whoever you suspect. Votes aren\'t secret — **Today\'s Tally** '
      'shows a running total, ranked by weight, and who voted for whom.',
    ),
    _Para(
      "You can vote (or change your vote) at any point during the day. "
      "Once the case's configured daily cutoff time arrives, the round "
      "resolves on its own — nobody has to press anything:",
    ),
    _Bullets([
      "If the highest-weighted vote landed on an Informant who hasn't been "
          "caught before, they're **unmasked**: their role flips to Witness "
          "in front of everyone, and every voter who backed them gets their "
          "+1 reward.",
      'If it landed on a Witness instead, that Witness loses 1 weight, same '
          'as a Mafia hit — a vote is never wasted, it just lands somewhere.',
    ]),
    _Para(
      "**Voting History** (below the roster) keeps a permanent count of "
      "who's voted for whom across the whole case — useful for spotting a "
      "pattern, like two players who always seem to cover for each other. "
      "It's a plain count with no weight numbers, so it can't be used to "
      "infer anyone's eroded weight.",
    ),
  ]),
  _Section('The Wire', [
    _Para(
      'Informants coordinate through a shared thread called **the Wire**, '
      'visible only to current, still-hidden Mafia members. It works in '
      'the same propose → agree → act → confirm shape for both of the '
      "Mafia's two tools: marking a Witness, and recruiting one.",
    ),
  ]),
  _Section('Marking a Witness', [
    _Bullets([
      'Any Informant **proposes an elimination method** against a target '
          '(e.g. "a note left on their monitor") — the method, not the '
          'target, is immediately shown to every Witness as a forewarning '
          '("The Wire has agreed on an elimination signal... watch for it").',
      'Every other currently-active Informant has to **accept** before it '
          'counts as agreed. An absent member (toggled "inactive") isn\'t '
          'required to accept, and doesn\'t block the others.',
      'Once agreed, an Informant has a 1-hour window to mark it '
          '**Executed** — after that, or once the round ends first, the '
          'opportunity lapses and they have to start over.',
      'Once executed, the elimination signal becomes visible to every '
          'Witness to check for on their own. The real target sees it and '
          'can confirm they found it — that confirmation ends the round '
          'early, right then, without waiting for the daily cutoff.',
    ]),
  ]),
  _Section('Recruiting a Witness', [
    _Para(
      "Recruitment is the Mafia's comeback mechanic — since Witnesses are "
      "never removed, a case that ran long enough would otherwise leave "
      "the Mafia hopelessly outnumbered.",
    ),
    _Bullets([
      'Recruitment only becomes available once the Mafia are thin relative '
          'to the Witnesses still around — the case\'s own starting ratio '
          'is the threshold (a case that starts 6 Witnesses to 2 Mafia '
          'unlocks recruitment once that same ~1:3 ratio is reached again, '
          'e.g. after an Informant is unmasked).',
      'It works exactly like marking a Witness — propose a **sign** '
          'against a target, get every active Informant to agree, then '
          '**approach** them within the window. The sign becomes visible '
          'to every Witness the same way a method does.',
      'The real target can **Accept** (they become an Informant, joining '
          'the Wire, and the round ends) or **Decline** (they stay a '
          'Witness, and the slot frees up for another attempt).',
      'Only one recruitment can be in flight across the whole case at a time.',
    ]),
  ]),
  _Section('Cell structure', [
    _Para(
      'An Informant only ever knows their own recruiter and whoever they '
      'personally recruited — never the full Mafia roster. If someone in '
      "your chain gets unmasked, the rest of the Mafia isn't automatically "
      'exposed with them. An unmasked Informant can choose to share what '
      "they know about their one or two connections later — it's their "
      'call, not something the app forces.',
    ),
  ]),
  _Section("If you're going to be away", [
    _Para(
      'Toggle yourself **inactive** on the Wire before you step away — the '
      "remaining active Informants can still act without you, and you "
      "won't block their agreement. It resets back to active on its own "
      'after 24 hours if you forget to flip it back.',
    ),
  ]),
  _Section('The Observation Log', [
    _Para(
      'Anyone can log a note — general, or specifically **about** another '
      "player — right from their dashboard. Entries show who wrote them "
      "and (if targeted) who they're about, newest at the bottom like any "
      "chat. The log is deliberately short-lived: anything older than 3 "
      "rounds is deleted for good, so it never becomes a permanent, "
      "searchable list of accusations against real coworkers.",
    ),
  ]),
  _Section('Leaving a case', [
    _Para(
      "Tap the sign-out icon and confirm to leave for good — there's no "
      "rejoin in this version. Once you've left:",
    ),
    _Bullets([
      'You show up in the roster as "(name) (left)" and can no longer '
          'vote or be voted for.',
      "Your past votes and any observations about you stay in the record — "
          "leaving doesn't erase history.",
      'If you were an Informant with a pending, unagreed proposal on the '
          'table, your leaving counts as automatic agreement from you, the '
          'same as toggling inactive would.',
      "A departure can shift the balance of the case on its own — if "
          "enough Witnesses leave and the Mafia end up at parity with who's "
          "left, the case can end right there, with no vote or recruitment "
          "needed.",
    ]),
  ]),
  _Section('How a case ends', [
    _Para("There's no fixed length — a case runs until one side clearly wins:"),
    _Bullets([
      'The Witnesses win the instant no Informant is left standing (every '
          'one has been unmasked, or has left).',
      'The Mafia win the instant they reach parity (or more) against the '
          'Witnesses still in the case.',
    ]),
    _Para(
      'Whichever happens first ends the case immediately — a finale screen '
      'replaces the whole dashboard, naming the winning side and listing '
      'everyone who was ever Mafia over the course of the case. Once a '
      "case is closed, nothing in it is actionable anymore; you can still "
      're-enter to look at the finale, but voting, coordinating, and '
      'logging are all switched off for good.',
    ),
  ]),
  _Section('Starting your own case', [
    _Para('From **Find your case**, tap **Start a new case** to configure one before it exists:'),
    _Bullets([
      '**Case name** — shown in the case list to anyone browsing.',
      '**Villagers** and **Mafia** — set each directly; players is just '
          'shown as their sum, since that\'s what the case actually needs '
          "to fill before it starts. Recruitment's unlock threshold and "
          "the Mafia's action window are both fixed sensible defaults now, "
          "not something you configure per case.",
      '**Daily vote cutoff** — the time of day the round resolves on its '
          'own, in 24-hour format (defaults to 17:00).',
    ]),
    _Para(
      "Once the roster fills to the total you've set, the case starts "
      'itself — no one needs to press a "start" button.',
    ),
  ]),
  _Section("Today's limitations", [
    _Para('This is an early, single-build prototype, not the final multi-device product:'),
    _Bullets([
      'Everything lives in memory on one running app instance — closing or '
          'restarting it resets every case.',
      "There's a separate **Tester** mode on the entry screen that lets "
          "one device switch between every player's identity in a case, "
          "for trying the whole game out solo before real multi-device "
          "play exists. It's a development stand-in, not part of the real "
          "game.",
      'Duplicate display names are currently allowed within the tester flow.',
      "Leaving a case is permanent for now — there's no way back in.",
    ]),
  ]),
];

/// Player-facing rules reference, mirroring `USER_MANUAL.md`. Every
/// section starts expanded and can be searched — matching sections stay
/// expanded (and their matched text highlighted) regardless of the
/// expand/collapse-all toggle, so a search always surfaces its answer
/// immediately rather than behind another tap.
class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final _searchController = TextEditingController();
  // Seeded expanded (per the "starts expanded" requirement) *on the
  // controller itself*, not via each tile's `initiallyExpanded` — the
  // controller's `isExpanded` is the only state that survives a section
  // scrolling off-screen and being disposed/recreated by the list below.
  late final List<ExpansibleController> _controllers =
      List.generate(_sections.length, (_) => ExpansibleController()..expand());
  String _query = '';
  bool _allExpanded = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    final query = value.trim();
    setState(() => _query = query);
    if (query.isEmpty) return;
    for (var i = 0; i < _sections.length; i++) {
      if (_sections[i].matches(query)) _controllers[i].expand();
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  void _setAllExpanded(bool expanded) {
    setState(() => _allExpanded = expanded);
    for (final controller in _controllers) {
      if (expanded) {
        controller.expand();
      } else {
        controller.collapse();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = [
      for (var i = 0; i < _sections.length; i++)
        if (_sections[i].matches(_query)) i,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('How to play')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search the rules',
                  prefixIcon:
                      Icon(PhosphorIconsLight.magnifyingGlass, color: AppColors.textSecondary),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(PhosphorIconsLight.x, color: AppColors.textSecondary),
                          onPressed: _clearSearch,
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _query.isEmpty
                          ? '${_sections.length} sections'
                          : '${visible.length} of ${_sections.length} match "$_query"',
                      style: AppTypography.dataSmall,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _setAllExpanded(!_allExpanded),
                    icon: Icon(
                      _allExpanded
                          ? PhosphorIconsLight.arrowsInLineVertical
                          : PhosphorIconsLight.arrowsOutLineVertical,
                      size: 16,
                    ),
                    label: Text(_allExpanded ? 'Collapse all' : 'Expand all'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Text('No matches for "$_query".', style: AppTypography.bodySmall),
                    )
                  // A plain (not `.builder`) ListView — a fixed 15-ish
                  // sections is small enough that eagerly building all of
                  // them costs nothing, and it means every section is
                  // always reachable by scrolling rather than only
                  // whichever ones the lazy builder has chosen to
                  // materialize so far.
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xl),
                      children: [
                        for (final index in visible)
                          _SectionTile(
                            key: ValueKey(index),
                            section: _sections[index],
                            controller: _controllers[index],
                            query: _query,
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  final _Section section;
  final ExpansibleController controller;
  final String query;

  const _SectionTile({
    super.key,
    required this.section,
    required this.controller,
    required this.query,
  });

  Widget _buildBlock(_Block block, TextStyle base) {
    if (block is _Para) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: RichText(
          text: TextSpan(style: base, children: _renderInline(block.text, base, query)),
        ),
      );
    }
    final bullets = block as _Bullets;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in bullets.items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: base.copyWith(color: AppColors.brass)),
                  Expanded(
                    child: RichText(
                      text: TextSpan(style: base, children: _renderInline(item, base, query)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final base = AppTypography.bodySmall;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppColors.borderHairline),
        ),
        child: ExpansionTile(
          controller: controller,
          // Not a hardcoded `true` — read from the controller, which is
          // the actual persistent state (survives this tile scrolling
          // off-screen and being disposed/recreated; a hardcoded literal
          // here would re-expand every off-screen section the instant it
          // scrolled back into view, regardless of what "Collapse all"
          // or an individual tap had just set).
          initiallyExpanded: controller.isExpanded,
          iconColor: AppColors.brass,
          collapsedIconColor: AppColors.textSecondary,
          textColor: AppColors.textPrimary,
          collapsedTextColor: AppColors.textPrimary,
          backgroundColor: AppColors.surface,
          collapsedBackgroundColor: AppColors.surface,
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
          childrenPadding:
              const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
          title: RichText(
            text: TextSpan(
              style: AppTypography.heading,
              children: _renderInline(section.title, AppTypography.heading, query),
            ),
          ),
          children: [for (final block in section.blocks) _buildBlock(block, base)],
        ),
      ),
    );
  }
}
