/// 4px base grid and radii from `design_spec.md` §4.
abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class AppRadii {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 20.0;
  static const pill = 999.0;
}

/// Motion durations from `design_spec.md` §7. Everyday interaction stays
/// under 300ms; ceremony moments (role reveal, elimination discovery,
/// unmasking) get 500-900ms because they're meant to be felt.
abstract final class AppMotion {
  static const fast = Duration(milliseconds: 150);
  static const base = Duration(milliseconds: 300);
  static const ceremonySeal = Duration(milliseconds: 500);
  static const ceremonyHeadline = Duration(milliseconds: 400);
  static const ceremonyWipe = Duration(milliseconds: 500);
  static const ceremonyStamp = Duration(milliseconds: 250);
}
