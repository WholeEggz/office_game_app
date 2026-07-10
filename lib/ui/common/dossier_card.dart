import 'package:flutter/material.dart';

import '../../design/colors.dart';
import '../../design/spacing.dart';

/// "Case file, not dashboard" (design_spec.md §1/§6): a plain surface with
/// a hairline border and no elevation, used to wrap every dossier-style
/// section (mafia coordination, observations, player roster).
class DossierCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const DossierCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.borderHairline, width: 1),
      ),
      child: child,
    );
  }
}
