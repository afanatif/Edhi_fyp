import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../constants/app_constants.dart';

class StatusBadge extends StatelessWidget {
  final String status;
  final double fontSize;

  const StatusBadge({super.key, required this.status, this.fontSize = 12});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    IconData icon;

    switch (status) {
      case EmergencyStatus.pending:
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFD97706);
        icon = Icons.hourglass_top_rounded;
        break;
      case EmergencyStatus.approved:
        bg = const Color(0xFFDBEAFE);
        fg = const Color(0xFF2563EB);
        icon = Icons.verified_rounded;
        break;
      case EmergencyStatus.assigned:
        bg = const Color(0xFFEDE9FE);
        fg = const Color(0xFF7C3AED);
        icon = Icons.directions_car_rounded;
        break;
      case EmergencyStatus.inProgress:
        bg = const Color(0xFFE0F2FE);
        fg = const Color(0xFF0284C7);
        icon = Icons.near_me_rounded;
        break;
      case EmergencyStatus.arrived:
        bg = const Color(0xFFCCFBF1);
        fg = const Color(0xFF0F766E);
        icon = Icons.local_hospital_rounded;
        break;
      case EmergencyStatus.completed:
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF16A34A);
        icon = Icons.check_circle_rounded;
        break;
      case EmergencyStatus.cancelled:
      default:
        bg = const Color(0xFFF1F5F9);
        fg = const Color(0xFF64748B);
        icon = Icons.cancel_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: fg.withValues(alpha: 0.25), width: 1),
        boxShadow: [
          BoxShadow(
            color: fg.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: fontSize + 2, color: fg),
          const SizedBox(width: 5),
          Text(
            status,
            style: GoogleFonts.inter(
              color: fg,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class PriorityBadge extends StatelessWidget {
  final String priority;
  final double fontSize;

  const PriorityBadge({super.key, required this.priority, this.fontSize = 11});

  @override
  Widget build(BuildContext context) {
    final isCritical =
        priority.contains('P1') || priority.toLowerCase().contains('critical');
    final isUrgent =
        priority.contains('P2') || priority.toLowerCase().contains('urgent');

    final bg = isCritical
        ? const Color(0xFFFEE2E2)
        : isUrgent
        ? const Color(0xFFFEF3C7)
        : const Color(0xFFF1F5F9);

    final fg = isCritical
        ? AppColors.emergencyRed
        : isUrgent
        ? const Color(0xFFD97706)
        : const Color(0xFF475569);

    final icon = isCritical
        ? Icons.local_fire_department_rounded
        : isUrgent
        ? Icons.warning_rounded
        : Icons.info_outline_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.3), width: 1),
        boxShadow: isCritical
            ? [
                BoxShadow(
                  color: AppColors.emergencyRed.withValues(alpha: 0.18),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: fontSize + 3, color: fg),
          const SizedBox(width: 4),
          Text(
            priority.toUpperCase(),
            style: GoogleFonts.outfit(
              color: fg,
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}
