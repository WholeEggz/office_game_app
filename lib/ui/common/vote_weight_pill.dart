import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../design/colors.dart';
import '../../design/graphics.dart';
import '../../design/spacing.dart';
import '../../design/typography.dart';

/// Three wax-seal pips, filled for remaining weight and hollow for lost
/// weight, plus the raw number — the "erosion legible at a glance" option
/// from design_spec.md §6. Villagers start at 3 and can rise above it via
/// the deduction reward (section 5), so pips beyond 3 collapse into "+N".
class VoteWeightPill extends StatelessWidget {
  final int weight;
  static const _trackedPips = 3;

  const VoteWeightPill({super.key, required this.weight});

  @override
  Widget build(BuildContext context) {
    final filledPips = weight.clamp(0, _trackedPips);
    final overflow = weight - _trackedPips;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: AppColors.borderHairline, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _trackedPips; i++) ...[
            SvgPicture.asset(
              i < filledPips ? AppGraphics.votePipFilled : AppGraphics.votePipHollow,
              width: 10,
              height: 10,
              colorFilter: ColorFilter.mode(
                i < filledPips ? AppColors.brass : AppColors.textMuted,
                BlendMode.srcIn,
              ),
            ),
            if (i < _trackedPips - 1) const SizedBox(width: 3),
          ],
          const SizedBox(width: AppSpacing.xs),
          Text(
            overflow > 0 ? '$weight (+$overflow)' : '$weight',
            style: AppTypography.data.copyWith(color: AppColors.brass),
          ),
        ],
      ),
    );
  }
}
