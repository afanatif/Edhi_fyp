import 'package:flutter/material.dart';
import '../../../core/widgets/stored_photo.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import 'missing_person_form.dart';
import '../../../services/auth_service.dart';
import '../../../core/widgets/contact_actions.dart';
import '../../../core/widgets/responsive_shell.dart';
import '../../../services/firestore_service.dart';
import '../../../models/missing_person_report.dart';
import '../../../core/widgets/skeleton_loader.dart';

class MissingPersonsScreen extends StatefulWidget {
  const MissingPersonsScreen({super.key});

  @override
  State<MissingPersonsScreen> createState() => _MissingPersonsScreenState();
}

class _MissingPersonsScreenState extends State<MissingPersonsScreen> {
  String _selectedFilter = 'All';

  Future<void> _showReportDialog(BuildContext context) async {
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => const MissingPersonForm(),
    );
    if (id != null && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Report #$id published.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final firestore = context.watch<FirestoreService>();

    return ResponsiveShell(
      appBar: AppBar(
        title: const Text('Missing Persons & Tracing'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'About Tracing Service',
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Edhi Tracing Bureau'),
                  content: const Text(
                    'The Edhi Missing Persons & Family Reunification Service assists families in reuniting with lost children, missing elders, and separated relatives across Pakistan. All reports are broadcasted to local rescue teams and relief centers.',
                    style: TextStyle(fontSize: 13, height: 1.5),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.emergencyRed,
        icon: const Icon(Icons.campaign, color: Colors.white),
        label: const Text(
          'Report Person',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        onPressed: () => _showReportDialog(context),
      ),
      child: StreamBuilder<List<MissingPersonReport>>(
        stream: firestore.getMissingPersonsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: SkeletonListView(
                count: 4,
                skeleton: SkeletonEmergencyCard(),
              ),
            );
          }
          final reports = snapshot.data ?? [];
          final filteredReports = reports.where((r) {
            if (_selectedFilter == 'Searching') return r.status == 'Searching';
            if (_selectedFilter == 'Found / Reunited') {
              return r.status != 'Searching';
            }
            return true;
          }).toList();

          final searchingCount = reports
              .where((r) => r.status == 'Searching')
              .length;
          final reunitedCount = reports
              .where((r) => r.status != 'Searching')
              .length;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Banner
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.emergencyRed.withValues(alpha: 0.08),
                      AppColors.reliefGreenSoft.withValues(alpha: 0.12),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.family_restroom,
                        color: AppColors.emergencyRed,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Family Reunification Portal',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Search active bulletins or report a missing relative for nation-wide coordination.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Filter Chips
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _buildFilterChip('All (${reports.length})', 'All'),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'Active Search ($searchingCount)',
                    'Searching',
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'Reunited ($reunitedCount)',
                    'Found / Reunited',
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Report Cards List
              if (filteredReports.isEmpty)
                Container(
                  padding: const EdgeInsets.all(40),
                  alignment: Alignment.center,
                  child: const Column(
                    children: [
                      Icon(
                        Icons.search_off,
                        size: 48,
                        color: AppColors.textSecondary,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'No notices found under this filter.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                )
              else
                ...filteredReports.map(
                  (report) => _buildReportCard(context, report, firestore),
                ),

              const SizedBox(height: 80), // Extra space for FAB
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: AppColors.emergencyRed.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        color: isSelected ? AppColors.emergencyRed : AppColors.textPrimary,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        fontSize: 12,
      ),
      onSelected: (sel) {
        if (sel) setState(() => _selectedFilter = value);
      },
    );
  }

  Widget _buildReportCard(
    BuildContext context,
    MissingPersonReport report,
    FirestoreService firestore,
  ) {
    final user = context.watch<AuthService>().currentUser;
    final canEdit = user != null && (user.isAdmin || report.userId == user.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (report.photoUrl.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: StoredPhoto(
                    url: report.photoUrl,
                    height: 200,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            Text(
              report.personName,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            const SizedBox(height: 4),
            Text('${report.gender} • ${report.age} years • ${report.status}'),
            const Divider(height: 24),
            Text(
              'Last seen: ${report.lastSeenLocation}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              report.lastSeenAt == null
                  ? 'Last seen time not provided'
                  : formatLastSeen(context, report.lastSeenAt!),
            ),
            const SizedBox(height: 10),
            Text(report.description),
            const SizedBox(height: 12),
            Text('Contact: ${report.contactName} • ${report.contactPhone}'),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  onPressed: () => openDialer(context, report.contactPhone),
                  icon: const Icon(Icons.call_outlined),
                  label: const Text('Call reporter'),
                ),
                if (report.isSearching && canEdit)
                  TextButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Mark found'),
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Confirm person found?'),
                          content: const Text(
                            'Only confirm after verifying the person has been found.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Back'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Confirm'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true) return;
                      try {
                        await firestore.updateMissingPersonStatus(
                          report.reportId,
                          'Found',
                        );
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Could not update report. Please retry.',
                              ),
                            ),
                          );
                        }
                      }
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
