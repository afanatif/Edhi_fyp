import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../theme/app_colors.dart';

/// Progress is derived only from saved dispatch status, never map proximity.
class DispatchProgress extends StatelessWidget {
  final String status;
  const DispatchProgress({super.key, required this.status});

  static int stageFor(String status) => switch (status) {
    EmergencyStatus.pending || EmergencyStatus.approved => 0,
    EmergencyStatus.assigned => 1,
    EmergencyStatus.inProgress => 2,
    EmergencyStatus.arrived => 3,
    EmergencyStatus.completed => 4,
    _ => -1,
  };

  @override
  Widget build(BuildContext context) {
    final stage = stageFor(status);
    if (status == EmergencyStatus.cancelled) {
      return const ListTile(
        leading: Icon(Icons.cancel_outlined),
        title: Text('Request cancelled'),
        subtitle: Text('No active dispatch for this request.'),
      );
    }
    if (stage < 0) return const Text('Awaiting a dispatch status update.');
    const labels = [
      'Received',
      'Assigned',
      'On the way',
      'Arrived',
      'Completed',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Dispatch progress',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        ...List.generate(
          labels.length,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(
                  i < stage || stage == 4
                      ? Icons.check_circle
                      : i == stage
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: i <= stage
                      ? AppColors.reliefGreenMedium
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontWeight: i == stage
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                ),
                if (i == stage && stage < 4)
                  const Text(
                    'Current',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.reliefGreenDark,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (status == EmergencyStatus.approved)
          const Text(
            'Approved. Dispatch is selecting an ambulance.',
            style: TextStyle(fontSize: 12),
          ),
      ],
    );
  }
}
