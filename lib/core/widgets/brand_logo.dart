import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Reusable project brand mark with a graceful icon fallback for test builds.
class BrandLogo extends StatelessWidget {
  final double size;
  final bool showSurface;

  const BrandLogo({super.key, this.size = 64, this.showSurface = false});

  @override
  Widget build(BuildContext context) {
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.24),
      child: Image.asset(
        'assets/images/edhiconnect_logo_v1.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        semanticLabel: 'EdhiConnect AI emergency response logo',
        errorBuilder: (_, _, _) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.reliefGreenDark,
            borderRadius: BorderRadius.circular(size * 0.24),
          ),
          child: Icon(
            Icons.health_and_safety_rounded,
            color: Colors.white,
            size: size * 0.56,
          ),
        ),
      ),
    );

    if (!showSurface) return image;
    return Container(
      padding: EdgeInsets.all(size * 0.11),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.reliefGreenDark.withValues(alpha: 0.15),
            blurRadius: 22,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: image,
    );
  }
}
