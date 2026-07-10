import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_game_app/design/colors.dart';
import 'package:office_game_app/design/theme.dart';

void main() {
  testWidgets('every TextField is filled brighter than a surfaceRaised container by default',
      (tester) async {
    final decoration = buildOfficeGameTheme().inputDecorationTheme;

    // Regression guard: an earlier version filled inputs with the same
    // surfaceRaised color/borderHairline border used by the cards and
    // boxed rows they typically sit inside, so fields blended into their
    // surroundings instead of reading as editable.
    expect(decoration.fillColor, AppColors.surfaceInput);
    expect(decoration.filled, isTrue);

    final enabledBorder = decoration.enabledBorder as OutlineInputBorder;
    expect(enabledBorder.borderSide.color, AppColors.borderStrong);

    final focusedBorder = decoration.focusedBorder as OutlineInputBorder;
    expect(focusedBorder.borderSide.color, AppColors.brass);
  });
}
