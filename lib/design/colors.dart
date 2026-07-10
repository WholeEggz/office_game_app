import 'package:flutter/widgets.dart';

/// Fixed hex tokens from `design_spec.md` §2. The app is dark-only by
/// design, so none of this adapts to system light/dark mode.
abstract final class AppColors {
  // Base
  static const ink = Color(0xFF15120E);
  static const surface = Color(0xFF1E1A14);
  static const surfaceRaised = Color(0xFF241F17);
  static const borderHairline = Color(0xFF3A3226);
  static const borderStrong = Color(0xFF4E4530);

  // Text
  static const textPrimary = Color(0xFFEDE6D6);
  static const textSecondary = Color(0xFFA69B85);
  static const textMuted = Color(0xFF948972);

  // Brass — primary accent
  static const brass = Color(0xFFC9A227);
  static const brassStrong = Color(0xFFA9840F);
  static const brassSoft = Color(0xFF3A2F12);
  static const onBrass = Color(0xFF2C1D02);

  // Crimson — danger / mafia accent
  static const crimson = Color(0xFF8B2635);
  static const crimsonStrong = Color(0xFF6E1D29);
  static const crimsonSoft = Color(0xFF3A1216);
  static const crimsonText = Color(0xFFE0949C);
  static const onCrimson = Color(0xFFF5E4E6);
}
