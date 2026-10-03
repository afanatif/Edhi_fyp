import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../services/firestore_service.dart';
import '../../../models/donation.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/attachment_photo.dart';

class AdminDonationsView extends StatefulWidget {
  const AdminDonationsView({super.key});

  @override
  State<AdminDonationsView> createState() => _AdminDonationsViewState();
}

class _AdminDonationsViewState extends State<AdminDonationsView> {
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    final firestore = context.watch<FirestoreService>();

    return StreamBuilder<List<Donation>>(
      stream: firestore.getDonationsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Row(
                children: [
                  Expanded(child: SkeletonMetricTile()),
                  SizedBox(width: 14),
                  Expanded(child: SkeletonMetricTile()),
                  SizedBox(width: 14),
                  Expanded(child: SkeletonMetricTile()),
                ],
              ),
              SizedBox(height: 24),
              SkeletonBox(width: double.infinity, height: 40, borderRadius: 10),
              SizedBox(height: 16),
              SkeletonListView(count: 4, skeleton: SkeletonEmergencyCard()),
            ],
          );
        }
        final allDonations = snapshot.data ?? [];

        final filtered = _filter == 'All'
            ? allDonations
            : allDonations
                  .where((d) => d.status.toLowerCase() == _filter.toLowerCase())
                  .toList();

        final totalFunds = allDonations
            .where((d) => d.status == 'Verified')
            .fold<double>(0.0, (sum, d) => sum + d.amount);

        final pendingCount = allDonations
            .where((d) => d.status == 'Pending')
            .length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Summary Cards
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total Verified Funds',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'PKR ${totalFunds.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.reliefGreenMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Pending Verifications',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$pendingCount Needs Review',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total Contributions',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${allDonations.length} Records',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Filter Tabs
            Wrap(
              runSpacing: 8,
              children: ['All', 'Pending', 'Verified'].map((f) {
                final isSelected = _filter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f),
                    selected: isSelected,
                    selectedColor: AppColors.reliefGreenSoft,
                    labelStyle: TextStyle(
                      color: isSelected
                          ? AppColors.reliefGreenDark
                          : AppColors.textPrimary,
                      fontWeight: isSelected
                          ? FontWeight.w800
                          : FontWeight.normal,
                      fontSize: 12,
                    ),
                    onSelected: (val) {
                      if (val) setState(() => _filter = f);
                    },
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),

            // Donations List
            if (filtered.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Center(
                  child: Text('No donations matching current filter.'),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final d = filtered[index];
                    final isPending = d.status == 'Pending';
                    final isMonetary = d.donationType == 'monetary';

                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final parts = <Widget>[
                            CircleAvatar(
                              backgroundColor: isMonetary
                                  ? AppColors.reliefGreenSoft
                                  : Colors.blue.shade50,
                              child: Icon(
                                isMonetary
                                    ? Icons.monetization_on
                                    : Icons.inventory_2,
                                color: isMonetary
                                    ? AppColors.reliefGreenDark
                                    : Colors.blue.shade700,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: [
                                      Text(
                                        '#${d.donationId} • ${d.userName}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                        ),
                                      ),
                                      StatusBadge(status: d.status),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    d.notes,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  if (d.photoUrl.isNotEmpty)
                                    AttachmentPhoto(url: d.photoUrl),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Date: ${d.createdAt?.toString().substring(0, 16) ?? 'Recent'}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                isMonetary
                                    ? 'PKR ${d.amount.toStringAsFixed(0)}'
                                    : 'Material Relief Item',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: isMonetary
                                      ? AppColors.reliefGreenMedium
                                      : Colors.blue.shade700,
                                ),
                              ),
                            ),
                            if (isPending)
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.reliefGreenMedium,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                icon: const Icon(Icons.verified, size: 16),
                                label: const Text(
                                  'Verify & Confirm',
                                  style: TextStyle(fontSize: 12),
                                ),
                                onPressed: () {
                                  firestore.verifyDonation(d.donationId);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Donation #${d.donationId} verified and receipt generated.',
                                      ),
                                      backgroundColor:
                                          AppColors.reliefGreenMedium,
                                    ),
                                  );
                                },
                              ),
                          ];
                          if (constraints.maxWidth >= 760) {
                            return Row(children: parts);
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final part in parts)
                                if (part is! SizedBox)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: part is Expanded
                                        ? part.child
                                        : part is CircleAvatar
                                        ? Align(
                                            alignment: Alignment.centerLeft,
                                            child: part,
                                          )
                                        : part,
                                  ),
                            ],
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}
