import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/ui/help/help_screen.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

void main() {
  // Section titles and bodies render via raw RichText (for inline bold +
  // search-highlight spans), which find.text ignores unless told to look
  // inside RichText too.
  Finder richText(String pattern) => find.textContaining(pattern, findRichText: true);

  testWidgets('every section starts expanded, showing body text with no search', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HelpScreen()));

    expect(richText('The premise'), findsOneWidget);
    // A line from that section's body — visible without tapping anything,
    // since sections start expanded.
    expect(richText('Nobody is'), findsOneWidget);
  });

  testWidgets('searching filters to only matching sections', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HelpScreen()));

    await tester.enterText(find.byType(TextField), 'recruit');
    await tester.pump();

    expect(richText('Recruiting a Witness'), findsOneWidget);
    // A section with nothing to do with recruitment shouldn't survive the filter.
    expect(richText('The Observation Log'), findsNothing);
  });

  testWidgets('a query with no matches shows an empty state', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HelpScreen()));

    await tester.enterText(find.byType(TextField), 'xyzzy_no_such_word');
    await tester.pump();

    expect(find.textContaining('No matches for'), findsOneWidget);
  });

  testWidgets('collapse all hides section bodies, expand all restores them', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HelpScreen()));
    expect(richText('Nobody is'), findsOneWidget);

    await tester.tap(find.text('Collapse all'));
    await tester.pumpAndSettle();
    expect(richText('Nobody is'), findsNothing);

    await tester.tap(find.text('Expand all'));
    await tester.pumpAndSettle();
    expect(richText('Nobody is'), findsOneWidget);
  });

  testWidgets(
      'collapse all stays collapsed after a section scrolls off-screen and back '
      '(regression: initiallyExpanded must not override a disposed/recreated tile)',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HelpScreen()));

    await tester.tap(find.text('Collapse all'));
    await tester.pumpAndSettle();

    // A section's title stays visible even while collapsed, so drag until
    // the *last* section's title appears. find.byType(Scrollable).first
    // would grab the search TextField's own internal (horizontal,
    // single-line) scrollable instead of the list, so target the ListView
    // itself. dragUntilVisible (not a fixed drag count) matters here:
    // reproducing the bug makes each newly-mounted section silently
    // re-expand as it scrolls into view, which keeps growing the list's
    // total scroll extent out from under a fixed number of drags.
    await tester.dragUntilVisible(
      richText("Today's limitations"),
      find.byType(ListView),
      const Offset(0, -300),
    );

    // A line from that very last section's body — if this section is
    // showing its content, it silently re-expanded on the way into view.
    expect(richText('Duplicate display names'), findsNothing);

    // Scroll back to the top and confirm the first section, which *was*
    // mounted the whole time, is still collapsed too.
    await tester.dragUntilVisible(
      richText('The premise'),
      find.byType(ListView),
      const Offset(0, 300),
    );
    expect(richText('Nobody is'), findsNothing);
  });

  testWidgets('clearing the search restores the full section list', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HelpScreen()));

    // The summary line ("N sections" / "N of M match ...") reflects the
    // filtered count directly, so it's a reliable check regardless of
    // which sections happen to be scrolled into view (the full,
    // 15-section list doesn't all fit on one screen).
    final summaryBefore = tester.widget<Text>(find.textContaining(' sections')).data;

    await tester.enterText(find.byType(TextField), 'recruit');
    await tester.pump();
    expect(find.textContaining('match "recruit"'), findsOneWidget);

    await tester.tap(find.byIcon(PhosphorIconsLight.x));
    await tester.pump();
    expect(find.text(summaryBefore!), findsOneWidget);
  });
}
