import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../design/colors.dart';
import '../../design/graphics.dart';
import '../../domain/models/player.dart';

/// A wax-seal badge — unbroken for a villager, cracked with an asymmetric
/// mask for mafia — appears at the top of the role-reveal ceremony and
/// doubles as a persistent identity marker on the main dashboard
/// (design_spec.md §6).
class RoleBadge extends StatelessWidget {
  final PlayerRole role;
  final double size;

  const RoleBadge({super.key, required this.role, this.size = 52});

  @override
  Widget build(BuildContext context) {
    final isMafia = role == PlayerRole.mafia;
    final accent = isMafia ? AppColors.crimson : AppColors.brass;
    return SvgPicture.asset(
      isMafia ? AppGraphics.mafiaSeal : AppGraphics.villagerSeal,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(accent, BlendMode.srcIn),
    );
  }
}
