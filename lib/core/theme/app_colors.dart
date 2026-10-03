import 'package:flutter/material.dart';

/// AppColors defines the humanitarian-focused design palette for EdhiConnect AI.
/// Inspired by the Edhi Foundation brand identity: Deep Emergency Crimson and
/// Relief Emerald Green, paired with modern, calming neutrals and glowing accents.
class AppColors {
  AppColors._();

  // Primary Brand - Emergency Red (Urgency, Rapid Response, SOS)
  static const Color emergencyRed = Color(0xFFDC2626);
  static const Color emergencyRedDark = Color(0xFF991B1B);
  static const Color emergencyRedLight = Color(0xFFF87171);
  static const Color emergencyRedGlow = Color(0x38DC2626);
  static const Color emergencyRedVibrant = Color(0xFFEF4444);

  // Secondary Brand - Relief Green (Trust, Hope, Medical Welfare)
  static const Color reliefGreen = Color(0xFF059669);
  static const Color reliefGreenDark = Color(0xFF065F46);
  static const Color reliefGreenMedium = Color(0xFF10B981);
  static const Color reliefGreenLight = Color(0xFF34D399);
  static const Color reliefGreenSoft = Color(0xFFECFDF5);
  static const Color reliefGreenGlow = Color(0x3310B981);

  // Neutral Scales (Modern Slate)
  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceElevated = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color border = Color(0xFFE2E8F0);
  static const Color divider = Color(0xFFEDF2F7);

  // Status & Priority Colors
  static const Color statusPending = Color(0xFFD97706); // Amber
  static const Color statusPendingBg = Color(0xFFFEF3C7);
  static const Color statusApproved = Color(0xFF2563EB); // Royal Blue
  static const Color statusApprovedBg = Color(0xFFDBEAFE);
  static const Color statusAssigned = Color(0xFF7C3AED); // Purple
  static const Color statusAssignedBg = Color(0xFFEDE9FE);
  static const Color statusInProgress = Color(0xFF0284C7); // Sky Blue
  static const Color statusInProgressBg = Color(0xFFE0F2FE);
  static const Color statusCompleted = Color(0xFF16A34A); // Emerald
  static const Color statusCompletedBg = Color(0xFFDCFCE7);
  static const Color statusCancelled = Color(0xFF64748B); // Slate
  static const Color statusCancelledBg = Color(0xFFF1F5F9);

  // Role Badge Accents
  static const Color roleUser = Color(0xFF0284C7);
  static const Color roleEmployee = Color(0xFFD97706);
  static const Color roleAdmin = Color(0xFFDC2626);

  // Command Center / Tactical Dark Palette
  static const Color darkNavy = Color(0xFF0A0F1D);
  static const Color darkHudSurface = Color(0xFF131C31);
  static const Color darkHudCard = Color(0xFF1B2744);
  static const Color darkHudBorder = Color(0xFF263558);
  static const Color cyanAccent = Color(0xFF06B6D4);
  static const Color amberGlow = Color(0xFFF59E0B);

  // Curated Gradients
  static const LinearGradient emergencyGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFEF4444), Color(0xFFDC2626), Color(0xFF991B1B)],
  );

  static const LinearGradient reliefGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF10B981), Color(0xFF059669), Color(0xFF047857)],
  );

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFF1F2), Color(0xFFF0FDF4), Color(0xFFF8FAFC)],
  );

  static const LinearGradient darkHudGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0A0F1D), Color(0xFF131C31)],
  );
}
