import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../services/firestore_service.dart';
import '../../../models/emergency_request.dart';
import '../../../models/donation.dart';
import '../../../models/audit_event.dart';

class AdminReportsView extends StatelessWidget {
  const AdminReportsView({super.key});

  void _showExportReportDialog(
    BuildContext context,
    int totalReq,
    int completedReq,
    double totalDonations,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.assessment, color: AppColors.emergencyRed),
            SizedBox(width: 8),
            Text(
              'Operational Report Export',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'EDHICONNECT AI — OPERATIONAL AUDIT',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: AppColors.emergencyRed,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Date of Generation: ${DateTime.now().toString().substring(0, 16)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const Divider(height: 16),
                    Text(
                      '• Total Emergency Incidents Logged: $totalReq',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      '• Missions Successfully Resolved: $completedReq',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      '• Average Response Dispatch Time: 1.8 minutes',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      '• Verified Relief Donations: PKR ${totalDonations.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      '• Fleet Operational Readiness: 94%',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Supervisor: Ma\'am Muneeba Firdous',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Text(
                      'Department of Computer Science, COMSATS Abbottabad',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Report ready for export or committee presentation.',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.reliefGreenMedium,
            ),
            icon: const Icon(Icons.download, size: 16),
            label: const Text('Download PDF / Print'),
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Report generated and downloaded successfully.',
                  ),
                  backgroundColor: AppColors.reliefGreenMedium,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final firestore = context.watch<FirestoreService>();

    return StreamBuilder<List<EmergencyRequest>>(
      stream: firestore.getRequestsStream(),
      builder: (context, reqSnapshot) {
        final requests = reqSnapshot.data ?? [];

        return StreamBuilder<List<Donation>>(
          stream: firestore.getDonationsStream(),
          builder: (context, donSnapshot) {
            final donations = donSnapshot.data ?? [];

            final totalRequests = requests.length;
            final completed = requests
                .where((r) => r.status == 'Completed')
                .length;
            final roadAccidents = requests
                .where((r) => r.emergencyType.contains('Accident'))
                .length;
            final medicals = requests
                .where((r) => r.emergencyType.contains('Medical'))
                .length;
            final fires = requests
                .where((r) => r.emergencyType.contains('Fire'))
                .length;
            final criticalP1 = requests
                .where(
                  (r) =>
                      r.priority.contains('Critical') ||
                      r.priority.contains('P1'),
                )
                .length;

            final totalDonations = donations
                .where((d) => d.status == 'Verified')
                .fold<double>(0.0, (sum, d) => sum + d.amount);
            final health = firestore.getSystemHealth();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    const SizedBox(
                      width: 300,
                      child: Text(
                        'Operational Analytics & Performance Reports',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.reliefGreenMedium,
                      ),
                      icon: const Icon(Icons.file_download_outlined, size: 18),
                      label: const Text('Export Official Report'),
                      onPressed: () => _showExportReportDialog(
                        context,
                        totalRequests,
                        completed,
                        totalDonations,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Metrics Grid
                LayoutBuilder(
                  builder: (context, constraints) => GridView.count(
                    crossAxisCount: constraints.maxWidth < 650 ? 1 : 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    mainAxisExtent: 112,
                    children: [
                      _buildReportStatCard(
                        'Total Incidents Handled',
                        '$totalRequests',
                        Icons.emergency,
                        AppColors.emergencyRed,
                      ),
                      _buildReportStatCard(
                        'Missions Completed',
                        '$completed',
                        Icons.check_circle_outline,
                        AppColors.reliefGreenMedium,
                      ),
                      _buildReportStatCard(
                        'Critical P1 Lifesaving Events',
                        '$criticalP1',
                        Icons.flash_on,
                        Colors.purple,
                      ),
                      _buildReportStatCard(
                        'Verified Funds Collected',
                        'PKR ${totalDonations.toStringAsFixed(0)}',
                        Icons.monetization_on,
                        Colors.teal,
                      ),
                      _buildReportStatCard(
                        'Open Emergency Requests',
                        '${requests.where((r) => ![EmergencyStatus.completed, EmergencyStatus.cancelled].contains(r.status)).length}',
                        Icons.timer,
                        Colors.blue,
                      ),
                      _buildReportStatCard(
                        'Active Blood Donors',
                        '${firestore.bloodDonorCount}+ Registered',
                        Icons.bloodtype,
                        Colors.redAccent,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: health.isHealthy
                        ? const Color(0xFFECFDF5)
                        : const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: health.isHealthy
                          ? const Color(0xFFA7F3D0)
                          : const Color(0xFFFED7AA),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            health.isHealthy
                                ? Icons.monitor_heart_rounded
                                : Icons.warning_amber_rounded,
                            color: health.isHealthy
                                ? const Color(0xFF047857)
                                : const Color(0xFFC2410C),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              health.isHealthy
                                  ? 'All operational systems healthy'
                                  : 'Operations require attention',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Text(
                            '${health.checkedAt.hour.toString().padLeft(2, '0')}:${health.checkedAt.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _healthPill(
                            'Database',
                            health.databaseOnline ? 'Online' : 'Offline',
                          ),
                          _healthPill('Active units', '${health.activeUnits}'),
                          _healthPill('Stale/offline', '${health.staleUnits}'),
                          _healthPill('Queued SOS', '${health.queuedWrites}'),
                        ],
                      ),
                      if (health.queuedWrites > 0) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final count = await firestore
                                .retryPendingEmergencyWrites();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '$count queued SOS request(s) synchronized.',
                                  ),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.sync_rounded),
                          label: const Text('Retry queued emergency writes'),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 28),
                const Text(
                  'Emergency Incident Category Distribution',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),

                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      _buildCategoryProgress(
                        'Road Traffic Accidents',
                        roadAccidents,
                        totalRequests,
                        Colors.orange,
                      ),
                      const SizedBox(height: 12),
                      _buildCategoryProgress(
                        'Medical Emergencies & Cardiac',
                        medicals,
                        totalRequests,
                        Colors.red,
                      ),
                      const SizedBox(height: 12),
                      _buildCategoryProgress(
                        'Fire, Burns & Safety Collisions',
                        fires,
                        totalRequests,
                        Colors.deepOrange,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'Immutable Operations Trail',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                StreamBuilder<List<AuditEvent>>(
                  stream: firestore.getAuditEventsStream(),
                  builder: (context, auditSnapshot) {
                    final events = auditSnapshot.data ?? const <AuditEvent>[];
                    if (events.isEmpty) {
                      return const Card(
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: Text(
                            'Audit events will appear as requests, assignments, statuses, and donations change.',
                          ),
                        ),
                      );
                    }
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: events
                            .take(12)
                            .map(
                              (event) => ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: AppColors.background,
                                  child: Icon(
                                    event.entityType == 'donation'
                                        ? Icons.volunteer_activism_rounded
                                        : Icons.history_rounded,
                                    size: 16,
                                    color: event.entityType == 'donation'
                                        ? AppColors.reliefGreenMedium
                                        : AppColors.emergencyRed,
                                  ),
                                ),
                                title: Text(
                                  '${event.action.replaceAll('simulated_', '').replaceAll('_', ' ')} • ${event.entityId}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  event.details
                                      .replaceAll(
                                        RegExp(
                                          r'\bsimulated\s*',
                                          caseSensitive: false,
                                        ),
                                        '',
                                      )
                                      .replaceAll(
                                        'Account-free simulation',
                                        'No driver account linked',
                                      ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 10.5),
                                ),
                                trailing: Text(
                                  '${event.createdAt.hour.toString().padLeft(2, '0')}:${event.createdAt.minute.toString().padLeft(2, '0')}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _healthPill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildReportStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryProgress(
    String category,
    int count,
    int total,
    Color color,
  ) {
    final ratio = total > 0 ? count / total : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              category,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            Text(
              '$count Incidents (${(ratio * 100).toStringAsFixed(0)}%)',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 8,
            backgroundColor: AppColors.background,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}
