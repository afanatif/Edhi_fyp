import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

enum ButtonVariant { primary, secondary, outline, text }

class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final ButtonVariant variant;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double? height;

  const CustomButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.variant = ButtonVariant.primary,
    Color? color,
    Color? backgroundColor,
    this.foregroundColor,
    this.height = 52,
  }) : backgroundColor = backgroundColor ?? color;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return SizedBox(
        height: height,
        child: Center(
          child: SizedBox(
            height: 24,
            width: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(
                variant == ButtonVariant.outline
                    ? AppColors.emergencyRed
                    : Colors.white,
              ),
            ),
          ),
        ),
      );
    }

    final effectiveOnPressed = isLoading ? null : onPressed;

    switch (variant) {
      case ButtonVariant.primary:
        return SizedBox(
          height: height,
          width: double.infinity,
          child: ElevatedButton(
            onPressed: effectiveOnPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: backgroundColor ?? AppColors.emergencyRed,
              foregroundColor: foregroundColor ?? Colors.white,
            ),
            child: _buildContent(),
          ),
        );

      case ButtonVariant.secondary:
        return SizedBox(
          height: height,
          width: double.infinity,
          child: ElevatedButton(
            onPressed: effectiveOnPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: backgroundColor ?? AppColors.reliefGreenMedium,
              foregroundColor: foregroundColor ?? Colors.white,
            ),
            child: _buildContent(),
          ),
        );

      case ButtonVariant.outline:
        return SizedBox(
          height: height,
          width: double.infinity,
          child: OutlinedButton(
            onPressed: effectiveOnPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: foregroundColor ?? AppColors.textPrimary,
              side: BorderSide(
                color: backgroundColor ?? AppColors.border,
                width: 1.5,
              ),
            ),
            child: _buildContent(),
          ),
        );

      case ButtonVariant.text:
        return TextButton(
          onPressed: effectiveOnPressed,
          style: TextButton.styleFrom(
            foregroundColor: foregroundColor ?? AppColors.reliefGreenMedium,
          ),
          child: _buildContent(),
        );
    }
  }

  Widget _buildContent() {
    if (icon == null) {
      return Text(text);
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// SosPulsingButton is the primary emergency action widget on the home dashboard.
class SosPulsingButton extends StatefulWidget {
  final VoidCallback onTap;
  final double size;

  const SosPulsingButton({super.key, required this.onTap, this.size = 175.0});

  @override
  State<SosPulsingButton> createState() => _SosPulsingButtonState();
}

class _SosPulsingButtonState extends State<SosPulsingButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _wave1;
  late Animation<double> _wave2;
  late Animation<double> _pulse;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    _wave1 = Tween<double>(begin: 1.0, end: 1.45).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.85, curve: Curves.easeOutCubic),
      ),
    );

    _wave2 = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _pulse = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeInOut),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final opacity1 = (1.0 - (_wave1.value - 1.0) / 0.45).clamp(0.0, 0.4);
        final opacity2 = (1.0 - (_wave2.value - 1.0) / 0.25).clamp(0.0, 0.5);

        return SizedBox(
          width: widget.size * 1.5,
          height: widget.size * 1.5,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer Ripple Wave
              Transform.scale(
                scale: _wave1.value,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.emergencyRedVibrant.withValues(
                        alpha: opacity1,
                      ),
                      width: 2.5,
                    ),
                  ),
                ),
              ),

              // Mid Ripple Wave
              Transform.scale(
                scale: _wave2.value,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.emergencyRedLight.withValues(
                      alpha: opacity2 * 0.2,
                    ),
                    border: Border.all(
                      color: AppColors.emergencyRedLight.withValues(
                        alpha: opacity2,
                      ),
                      width: 1.5,
                    ),
                  ),
                ),
              ),

              // Core Tactile Pulsing Button
              Transform.scale(
                scale: (_isPressed ? 0.94 : _pulse.value),
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.emergencyRed.withValues(alpha: 0.45),
                        blurRadius: 32,
                        spreadRadius: 6,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.3),
                        blurRadius: 10,
                        spreadRadius: -4,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: GestureDetector(
                    onTapDown: (_) => setState(() => _isPressed = true),
                    onTapUp: (_) {
                      setState(() => _isPressed = false);
                      widget.onTap();
                    },
                    onTapCancel: () => setState(() => _isPressed = false),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                          width: 4,
                        ),
                        gradient: AppColors.emergencyGradient,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.emergency_rounded,
                                color: Colors.white,
                                size: 26,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'SOS',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 36,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.5,
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withValues(alpha: 0.35),
                                    offset: const Offset(0, 2),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'DISPATCH RESCUE',
                                style: GoogleFonts.inter(
                                  color: Colors.white.withValues(alpha: 0.95),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
