import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/domain/hints/hint_definition.dart';
import 'package:office_game_app/domain/hints/static_hint_catalog.dart';

void main() {
  test('welcome_help is the first static hint and points at the Help screen', () {
    // "First" here just means catalog/progress-list order — the same
    // convention hint_catalog.dart uses (see StaticHintBanner call sites
    // for actual on-screen placement).
    expect(staticHintCatalog.first.id, 'welcome_help');
    expect(staticHintCatalog.first.actionTarget, HintActionTarget.help);
    expect(staticHintCatalog.first.actionLabel, isNotNull);
  });

  test('every other static hint has no secondary action', () {
    for (final info in staticHintCatalog.skip(1)) {
      expect(info.actionTarget, isNull, reason: '${info.id} should just describe its own screen');
    }
  });
}
