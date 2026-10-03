import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../services/auth_service.dart';
import '../../../services/firestore_service.dart';
import '../../../models/donation.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/photo_picker_field.dart';
import '../../../core/widgets/attachment_photo.dart';
import '../../../models/selected_photo.dart';

class DonationsScreen extends StatefulWidget {
  const DonationsScreen({super.key});

  @override
  State<DonationsScreen> createState() => _DonationsScreenState();
}

class _DonationsScreenState extends State<DonationsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            labelColor: AppColors.reliefGreenDark,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.reliefGreenMedium,
            indicatorWeight: 3,
            tabs: const [
              Tab(
                icon: Icon(Icons.volunteer_activism, size: 20),
                text: 'Donate Now',
              ),
              Tab(icon: Icon(Icons.campaign, size: 20), text: 'Campaigns'),
              Tab(icon: Icon(Icons.receipt_long, size: 20), text: 'My History'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              _MakeDonationTab(),
              _CampaignsTab(),
              _DonationHistoryTab(),
            ],
          ),
        ),
      ],
    );
  }
}

class _MakeDonationTab extends StatefulWidget {
  const _MakeDonationTab();

  @override
  State<_MakeDonationTab> createState() => _MakeDonationTabState();
}

class _MakeDonationTabState extends State<_MakeDonationTab> {
  String _donationType = 'monetary'; // 'monetary', 'ration', 'clothing'
  final _amountController = TextEditingController(text: '5000');
  final _notesController = TextEditingController();
  final _pickupAddressController = TextEditingController();
  final _transactionController = TextEditingController();
  String _selectedCampaign = '';
  SelectedPhoto? _photo;
  String? _uploadedPhotoUrl;
  String _paymentMethod = 'EasyPaisa';
  bool _isSubmitting = false;

  final List<double> _quickAmounts = [1000, 2500, 5000, 10000];

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    _pickupAddressController.dispose();
    _transactionController.dispose();
    super.dispose();
  }

  void _processDonation() async {
    if (_isSubmitting) return;
    final auth = context.read<AuthService>();
    final firestore = context.read<FirestoreService>();
    final user = auth.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to donate.')),
      );
      return;
    }
    if (_donationType != 'monetary' &&
        _pickupAddressController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter the address for volunteer pickup.'),
        ),
      );
      return;
    }

    final amount = double.tryParse(_amountController.text) ?? 0.0;
    if (_donationType == 'monetary' && amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid donation amount.')),
      );
      return;
    }
    if (_donationType == 'monetary' &&
        _transactionController.text.trim().length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter the transaction/reference ID from your payment receipt.',
          ),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final details = [
      if (_selectedCampaign.isNotEmpty) _selectedCampaign,
      if (_donationType == 'monetary')
        'via $_paymentMethod'
      else
        'Pickup: ${_pickupAddressController.text.trim()}',
    ];
    final noteText = '[${details.join(' · ')}] ${_notesController.text.trim()}'
        .trim();

    final donation = Donation(
      donationId: '',
      userId: user.id,
      userName: user.name,
      amount: _donationType == 'monetary' ? amount : 0.0,
      donationType: _donationType,
      status: 'Pending',
      notes: noteText,
      campaign: _selectedCampaign,
      paymentMethod: _donationType == 'monetary' ? _paymentMethod : '',
      transactionReference: _donationType == 'monetary'
          ? _transactionController.text.trim()
          : '',
      paymentStatus: _donationType == 'monetary'
          ? 'AwaitingVerification'
          : 'NotApplicable',
    );

    try {
      var submittedDonation = donation;
      if (_donationType == 'clothing' && _photo != null) {
        _uploadedPhotoUrl ??= await firestore.uploadDonationPhoto(
          _photo!.bytes,
          _photo!.contentType,
        );
        submittedDonation = donation.copyWith(photoUrl: _uploadedPhotoUrl);
      }
      final donationId = await firestore.submitDonation(submittedDonation);
      if (mounted) _showReceiptDialog(donationId, submittedDonation);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.toString().replaceFirst('Invalid argument(s): ', ''),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showReceiptDialog(String donationId, Donation donation) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.reliefGreenSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.check_circle,
                color: AppColors.reliefGreenMedium,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Donation Receipt',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
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
                    'OFFICIAL EDHI FOUNDATION RECEIPT',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: AppColors.reliefGreenDark,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Receipt No: #$donationId',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Donor: ${donation.userName}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  Text(
                    'Date: ${DateTime.now().toString().substring(0, 16)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Category: ${donation.donationType.toUpperCase()}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        donation.amount > 0
                            ? 'PKR ${donation.amount.toStringAsFixed(0)}'
                            : 'Material In-Kind',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.reliefGreenMedium,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'May Allah reward your contribution. Edhi Foundation ensures 100% transparent utilization.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.reliefGreenMedium,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Save & Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      absorbing: _isSubmitting,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.reliefGreenDark,
                    AppColors.reliefGreenMedium,
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.favorite,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edhi Relief & Sadaqah Fund',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Your support keeps ambulances running and food reaching thousands.',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Donation Category Switcher
            const Text(
              'Donation Type',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildTypeChip('monetary', '💰 Money', Icons.payments),
                const SizedBox(width: 8),
                _buildTypeChip('ration', '📦 Food / Ration', Icons.inventory_2),
                const SizedBox(width: 8),
                _buildTypeChip('clothing', '👕 Clothes', Icons.checkroom),
              ],
            ),

            const SizedBox(height: 20),

            // Campaign Selector
            const Text(
              'Relief campaign (optional)',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _selectedCampaign,
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text(
                        'No campaign',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    ...[
                      'Flood Relief 2026',
                      'Emergency Ambulance Fuel Fund',
                      'Winter Warmth & Shelter Drive',
                      'Daily Langar & Ration Drive',
                      'General Medical Fund',
                    ].map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Text(c, style: const TextStyle(fontSize: 13)),
                      ),
                    ),
                  ],
                  onChanged: (val) => setState(() => _selectedCampaign = val!),
                ),
              ),
            ),

            const SizedBox(height: 20),

            if (_donationType == 'monetary') ...[
              const Text(
                'Amount (PKR)',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 8),
              CustomTextField(
                controller: _amountController,
                label: 'Donation Amount (PKR)',
                keyboardType: TextInputType.number,
                prefixIcon: Icons.currency_exchange,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: _quickAmounts.map((amt) {
                  final isSelected =
                      _amountController.text == amt.toStringAsFixed(0);
                  return ChoiceChip(
                    label: Text('PKR ${amt.toStringAsFixed(0)}'),
                    selected: isSelected,
                    selectedColor: AppColors.reliefGreenSoft,
                    labelStyle: TextStyle(
                      color: isSelected
                          ? AppColors.reliefGreenDark
                          : AppColors.textPrimary,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.normal,
                      fontSize: 12,
                    ),
                    onSelected: (selected) {
                      if (selected) {
                        setState(
                          () => _amountController.text = amt.toStringAsFixed(0),
                        );
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Text(
                'Payment Channel',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildPaymentOption('EasyPaisa'),
                  const SizedBox(width: 8),
                  _buildPaymentOption('JazzCash'),
                  const SizedBox(width: 8),
                  _buildPaymentOption('Bank Transfer'),
                ],
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _transactionController,
                label: 'Payment Transaction / Reference ID',
                prefixIcon: Icons.verified_user_outlined,
              ),
              const SizedBox(height: 6),
              const Text(
                'Payments remain pending until the Edhi account webhook or an administrator verifies the reference. Never share your PIN or OTP.',
                style: TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
              ),
            ] else ...[
              const Text(
                'Pickup Location',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 8),
              CustomTextField(
                controller: _pickupAddressController,
                label: 'Address for Volunteer Pickup',
                prefixIcon: Icons.location_on_outlined,
              ),
              if (_donationType == 'clothing') ...[
                const SizedBox(height: 16),
                PhotoPickerField(
                  label: 'Clothing photo (optional)',
                  value: _photo,
                  enabled: !_isSubmitting,
                  onChanged: (photo) => setState(() {
                    _photo = photo;
                    _uploadedPhotoUrl = null;
                  }),
                ),
              ],
            ],

            const SizedBox(height: 16),
            const Text(
              'Special Notes / Dedication (Optional)',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 8),
            CustomTextField(
              controller: _notesController,
              label: 'e.g. In memory of loved ones, Zakat intent',
              maxLines: 2,
              prefixIcon: Icons.note_alt_outlined,
            ),

            const SizedBox(height: 24),

            CustomButton(
              text: _donationType == 'monetary'
                  ? 'Donate & Generate Receipt'
                  : 'Request In-Kind Pickup',
              icon: Icons.favorite,
              color: AppColors.reliefGreenMedium,
              isLoading: _isSubmitting,
              onPressed: _processDonation,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeChip(String type, String label, IconData icon) {
    final isSelected = _donationType == type;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _donationType = type),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.reliefGreenSoft : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? AppColors.reliefGreenMedium
                  : AppColors.border,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected
                    ? AppColors.reliefGreenDark
                    : AppColors.textSecondary,
                size: 20,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? AppColors.reliefGreenDark
                      : AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentOption(String name) {
    final isSelected = _paymentMethod == name;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _paymentMethod = name),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.reliefGreenSoft : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? AppColors.reliefGreenMedium
                  : AppColors.border,
            ),
          ),
          child: Center(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                color: isSelected
                    ? AppColors.reliefGreenDark
                    : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CampaignsTab extends StatelessWidget {
  const _CampaignsTab();

  @override
  Widget build(BuildContext context) {
    final campaigns = [
      {
        'title': 'Flood Relief 2026',
        'desc':
            'Emergency rescue boats, food packages, and medical camps in affected regions.',
        'raised': 750000.0,
        'goal': 1000000.0,
        'progress': 0.75,
      },
      {
        'title': 'Emergency Ambulance Fuel Fund',
        'desc':
            'Keeping 50+ regional ambulances operational 24/7 with fuel and maintenance.',
        'raised': 450000.0,
        'goal': 800000.0,
        'progress': 0.56,
      },
      {
        'title': 'Winter Warmth & Shelter Drive',
        'desc':
            'Thermal blankets, jackets, and heated shelter accommodation for the homeless.',
        'raised': 300000.0,
        'goal': 500000.0,
        'progress': 0.60,
      },
    ];

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: campaigns.length,
      itemBuilder: (context, index) {
        final c = campaigns[index];
        final progress = c['progress'] as double;

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      c['title'] as String,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.reliefGreenSoft,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${(progress * 100).toInt()}% Funded',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.reliefGreenDark,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                c['desc'] as String,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: AppColors.border,
                  valueColor: const AlwaysStoppedAnimation(
                    AppColors.reliefGreenMedium,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Raised: PKR ${(c['raised'] as double).toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Target: PKR ${(c['goal'] as double).toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DonationHistoryTab extends StatelessWidget {
  const _DonationHistoryTab();

  @override
  Widget build(BuildContext context) {
    final firestore = context.watch<FirestoreService>();

    return StreamBuilder<List<Donation>>(
      stream: firestore.getDonationsStream(
        userId: context.watch<AuthService>().currentUser?.id ?? '',
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: SkeletonListView(
              count: 4,
              skeleton: SkeletonEmergencyCard(),
            ),
          );
        }
        final donations = snapshot.data ?? [];
        if (donations.isEmpty) {
          return const Center(child: Text('No recorded donations yet.'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: donations.length,
          itemBuilder: (context, index) {
            final don = donations[index];
            final isMonetary = don.donationType == 'monetary';

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppColors.reliefGreenSoft,
                    child: Icon(
                      isMonetary ? Icons.monetization_on : Icons.inventory_2,
                      color: AppColors.reliefGreenDark,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              isMonetary
                                  ? 'PKR ${don.amount.toStringAsFixed(0)}'
                                  : 'In-Kind ${don.donationType.toUpperCase()}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                            StatusBadge(status: don.status),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          don.notes,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (don.photoUrl.isNotEmpty)
                          AttachmentPhoto(url: don.photoUrl),
                        const SizedBox(height: 4),
                        Text(
                          'ID: #${don.donationId} • ${don.createdAt?.toString().substring(0, 16) ?? 'Recent'}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
