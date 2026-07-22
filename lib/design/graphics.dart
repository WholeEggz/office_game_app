/// Bespoke SVG asset paths — the wax-seal/case-file mark set proposed
/// alongside `design_spec.md` §5 to replace generic icon-library stand-ins
/// at the app's three ceremony moments and its brand mark.
abstract final class AppGraphics {
  static const villagerSeal = 'assets/graphics/villager_seal.svg';
  static const mafiaSeal = 'assets/graphics/mafia_seal.svg';
  static const appMark = 'assets/graphics/app_mark_seal_eye.svg';
  static const unmaskStampBurst = 'assets/graphics/unmask_stamp_burst.svg';
  static const redactionBar = 'assets/graphics/redaction_bar.svg';
  static const maskBespoke = 'assets/graphics/mask_bespoke.svg';
  static const fingerprintDossierMark = 'assets/graphics/fingerprint_dossier_mark.svg';
  static const votePipFilled = 'assets/graphics/vote_pip_filled.svg';
  static const votePipHollow = 'assets/graphics/vote_pip_hollow.svg';

  // Rank and badge art — cropped from a single gold-insignia sheet
  // supplied for the Profile screen's rank ladder and achievement badges
  // (see `achievements.dart`); the source sheet itself isn't kept around,
  // only these already-cropped, already-transparent pieces. Bitmap, not
  // SVG, since the source itself is a raster sheet, not vector art.
  static const rankRookie = 'assets/graphics/badges/rank_rookie.png';
  static const rankAssociate = 'assets/graphics/badges/rank_associate.png';
  static const rankDetective = 'assets/graphics/badges/rank_detective.png';
  static const rankInspector = 'assets/graphics/badges/rank_inspector.png';
  static const rankChiefInspector = 'assets/graphics/badges/rank_chief_inspector.png';
  static const rankLegend = 'assets/graphics/badges/rank_legend.png';

  static const badgeFirstCase = 'assets/graphics/badges/badge_first_case.png';
  static const badgeCaseClosed = 'assets/graphics/badges/badge_case_closed.png';
  static const badgeSharpEye = 'assets/graphics/badges/badge_sharp_eye.png';
  static const badgeBloodhound = 'assets/graphics/badges/badge_bloodhound.png';
  static const badgePerfectRead = 'assets/graphics/badges/badge_perfect_read.png';
  static const badgeOnARoll = 'assets/graphics/badges/badge_on_a_roll.png';
  static const badgeUnstoppable = 'assets/graphics/badges/badge_unstoppable.png';
  static const badgeUndercover = 'assets/graphics/badges/badge_undercover.png';
  static const badgeGhost = 'assets/graphics/badges/badge_ghost.png';
  static const badgeRecruiter = 'assets/graphics/badges/badge_recruiter.png';
  static const badgeVeteran = 'assets/graphics/badges/badge_veteran.png';
  static const badgeCenturyClub = 'assets/graphics/badges/badge_century_club.png';
}
