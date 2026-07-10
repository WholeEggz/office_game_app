import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colors.dart';

/// Type scale from `design_spec.md` §3. Family/weight/size/line-height are
/// fixed here; color is set to a sensible default per style but callers are
/// expected to override it (e.g. brass for the vote-weight number) rather
/// than bake every color combination into the scale itself.
abstract final class AppTypography {
  static TextStyle get displayLarge => GoogleFonts.playfairDisplay(
        fontWeight: FontWeight.w700,
        fontSize: 30,
        height: 1.2,
        color: AppColors.textPrimary,
      );

  static TextStyle get displayMedium => GoogleFonts.playfairDisplay(
        fontWeight: FontWeight.w600,
        fontSize: 22,
        height: 1.25,
        color: AppColors.textPrimary,
      );

  static TextStyle get heading => GoogleFonts.inter(
        fontWeight: FontWeight.w500,
        fontSize: 18,
        height: 1.3,
        color: AppColors.textPrimary,
      );

  static TextStyle get body => GoogleFonts.inter(
        fontWeight: FontWeight.w400,
        fontSize: 16,
        height: 1.5,
        color: AppColors.textPrimary,
      );

  static TextStyle get bodySmall => GoogleFonts.inter(
        fontWeight: FontWeight.w400,
        fontSize: 14,
        height: 1.5,
        color: AppColors.textSecondary,
      );

  static TextStyle get data => GoogleFonts.jetBrainsMono(
        fontWeight: FontWeight.w500,
        fontSize: 15,
        height: 1.4,
        color: AppColors.textSecondary,
      );

  static TextStyle get dataSmall => GoogleFonts.jetBrainsMono(
        fontWeight: FontWeight.w400,
        fontSize: 13,
        height: 1.4,
        color: AppColors.textMuted,
      );

  static TextStyle get button => GoogleFonts.inter(
        fontWeight: FontWeight.w500,
        fontSize: 16,
        height: 1.2,
        color: AppColors.onBrass,
      );

  static TextTheme get textTheme => TextTheme(
        displayLarge: displayLarge,
        displayMedium: displayMedium,
        titleMedium: heading,
        bodyMedium: body,
        bodySmall: bodySmall,
        labelLarge: button,
      );
}
