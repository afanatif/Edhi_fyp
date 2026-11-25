import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/emergency_request.dart';
import '../../../services/firestore_service.dart';

/// Red HQ alert: patients whose offers were refused or missed several times.
class DispatchAlertBanner extends StatelessWidget {
  final List<EmergencyRequest> requests;
  final VoidCallback onOpenMap;
  const DispatchAlertBanner({
    super.key,
    required this.requests,
    required this.onOpenMap,
  });

  @override
  Widget build(BuildContext context) {
    final service = context.watch<FirestoreService>();
    final now = service.clockNow;
    final stuck = requests
        .where(
          (r) =>
              r.dispatchAlert &&
              const [
                EmergencyStatus.pending,
                EmergencyStatus.approved,
              ].contains(r.status),
        )
        .toList();
    final asking = requests.where((r) {
      final offer = service.currentOfferForRequest(r);
      return offer != null && offer.isLive(now);
    }).length;
    if (stuck.isEmpty && asking == 0) return const SizedBox.shrink();
    final red = stuck.isNotEmpty;
    final color = red ? AppColors.emergencyRed : AppColors.statusPending;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1.4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            red ? Icons.crisis_alert_rounded : Icons.ring_volume_rounded,
            color: color,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  red
                      ? '${stuck.length} patient${stuck.length == 1 ? '' : 's'}: no driver accepted after ${stuck.map((r) => r.offerAttempts).reduce((a, b) => a > b ? a : b)} tries'
                      : '$asking offer${asking == 1 ? '' : 's'} ringing on driver phones',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w800,
                    color: color,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  red
                      ? 'Call the nearest drivers directly or assign a unit manually on the dispatch map. ${stuck.map((r) => '#${r.requestId}').take(3).join(', ')}'
                      : 'Each driver has 60 seconds. Missed offers move to the next ambulance automatically.',
                  style: const TextStyle(fontSize: 12.5),
                ),
                if (red) ...[
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: color),
                    onPressed: onOpenMap,
                    icon: const Icon(Icons.map_rounded, size: 18),
                    label: const Text('Open dispatch map'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
