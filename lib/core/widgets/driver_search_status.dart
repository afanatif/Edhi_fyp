import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/dispatch_offer.dart';
import '../../models/emergency_request.dart';
import '../../services/firestore_service.dart';
import '../constants/app_constants.dart';
import '../theme/app_colors.dart';

/// Citizen-facing "we are asking the nearest driver" status with a countdown.
class DriverSearchStatus extends StatefulWidget {
  final EmergencyRequest request;
  const DriverSearchStatus({super.key, required this.request});

  @override
  State<DriverSearchStatus> createState() => _DriverSearchStatusState();
}

class _DriverSearchStatusState extends State<DriverSearchStatus> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    if (!const [
      EmergencyStatus.pending,
      EmergencyStatus.approved,
    ].contains(request.status)) {
      return const SizedBox.shrink();
    }
    final service = context.watch<FirestoreService>();
    final now = service.clockNow;
    final offer = service.currentOfferForRequest(request);
    final live = offer != null && offer.isLive(now);
    final left = live ? offer.remaining(now).inSeconds : 0;
    final title = live
        ? 'Asking ${offer.driverName.isEmpty ? 'the nearest driver' : offer.driverName} to accept'
        : request.offerAttempts > 0
        ? 'Moving to the next-nearest ambulance'
        : 'Finding the nearest ambulance';
    final subtitle = live
        ? '${offer.vehicleNumber} · ${offer.distanceKm.toStringAsFixed(1)} km away · $left s to answer'
        : request.dispatchAlert
        ? 'Several drivers could not take this job. Edhi Operations has been alerted and is assigning one now. For immediate help call 115.'
        : 'Each driver gets 60 seconds to accept. If they don’t, we instantly ask the next one.';
    final color = request.dispatchAlert
        ? AppColors.emergencyRed
        : AppColors.statusPending;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox.square(
                dimension: 40,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: live
                          ? left / DispatchOffer.window.inSeconds
                          : null,
                      strokeWidth: 4,
                      color: color,
                      backgroundColor: color.withValues(alpha: 0.15),
                    ),
                    Icon(Icons.local_shipping_rounded, size: 18, color: color),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w800,
                    fontSize: 15.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(subtitle, style: const TextStyle(fontSize: 12.5)),
          if (request.offerAttempts > 1) ...[
            const SizedBox(height: 6),
            Text(
              'Attempt ${request.offerAttempts}',
              style: TextStyle(
                fontSize: 11.5,
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
