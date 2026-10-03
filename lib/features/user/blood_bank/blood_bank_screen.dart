import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/app_user.dart';
import '../../../core/widgets/contact_actions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../services/auth_service.dart';
import '../../../services/firestore_service.dart';
import '../../../models/blood_donor.dart';
import '../../../core/widgets/skeleton_loader.dart';

class BloodBankScreen extends StatefulWidget {
  const BloodBankScreen({super.key});

  @override
  State<BloodBankScreen> createState() => _BloodBankScreenState();
}

class _BloodBankScreenState extends State<BloodBankScreen>
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
            labelColor: AppColors.emergencyRed,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.emergencyRed,
            indicatorWeight: 3,
            tabs: const [
              Tab(
                icon: Icon(Icons.emergency_share, size: 20),
                text: 'Requests',
              ),
              Tab(icon: Icon(Icons.app_registration, size: 20), text: 'Donate'),
              Tab(icon: Icon(Icons.people_outline, size: 20), text: 'Donors'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              _UrgentBloodNeedsTab(),
              _RegisterDonorTab(),
              _SearchDonorsTab(),
            ],
          ),
        ),
      ],
    );
  }
}

class _UrgentBloodNeedsTab extends StatelessWidget {
  const _UrgentBloodNeedsTab();

  Future<void> _showCreateNeedDialog(BuildContext context) async {
    final user = context.read<AuthService>().currentUser;
    if (user == null) return;
    bool submitting = false;
    String? error;
    final patientController = TextEditingController();
    final hospitalController = TextEditingController();
    final unitsController = TextEditingController(text: '2');
    final phoneController = TextEditingController(text: user.phone);
    String selectedGroup = 'O+';

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.water_drop, color: AppColors.emergencyRed),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Request blood',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomTextField(
                  controller: patientController,
                  label: 'Patient Name',
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: hospitalController,
                  label: 'Hospital & Ward',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: selectedGroup,
                        decoration: const InputDecoration(
                          labelText: 'Blood Group',
                          border: OutlineInputBorder(),
                        ),
                        items:
                            ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']
                                .map(
                                  (g) => DropdownMenuItem(
                                    value: g,
                                    child: Text(g),
                                  ),
                                )
                                .toList(),
                        onChanged: (val) =>
                            setDialogState(() => selectedGroup = val!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CustomTextField(
                        controller: unitsController,
                        label: 'Units (Bags)',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: phoneController,
                  label: 'Attendant Phone Number',
                  keyboardType: TextInputType.phone,
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error!,
                      style: const TextStyle(color: AppColors.emergencyRed),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.emergencyRed,
              ),
              onPressed: submitting
                  ? null
                  : () async {
                      final units = int.tryParse(unitsController.text.trim());
                      if (patientController.text.trim().isEmpty ||
                          hospitalController.text.trim().isEmpty ||
                          units == null ||
                          units < 1 ||
                          units > 20 ||
                          !AppUser.isValidPhone(phoneController.text)) {
                        setDialogState(
                          () => error =
                              'Enter patient, hospital, 1–20 units, and a valid mobile number.',
                        );
                        return;
                      }
                      setDialogState(() {
                        submitting = true;
                        error = null;
                      });
                      try {
                        await context
                            .read<FirestoreService>()
                            .submitUrgentBloodNeed(
                              UrgentBloodNeed(
                                id: '',
                                userId: user.id,
                                patientName: patientController.text.trim(),
                                hospital: hospitalController.text.trim(),
                                bloodGroup: selectedGroup,
                                unitsNeeded: units,
                                contact: AppUser.normalizePhone(
                                  phoneController.text,
                                ),
                                createdAt: DateTime.now(),
                              ),
                            );
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Blood request posted.'),
                            ),
                          );
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          setDialogState(() {
                            submitting = false;
                            error =
                                'Could not post request. Please try again. $e';
                          });
                        }
                      }
                    },
              child: Text(submitting ? 'Posting…' : 'Post request'),
            ),
          ],
        ),
      ),
    );
    patientController.dispose();
    hospitalController.dispose();
    unitsController.dispose();
    phoneController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final firestore = context.watch<FirestoreService>();

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.emergencyRed,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Post Need',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        onPressed: () => _showCreateNeedDialog(context),
      ),
      body: StreamBuilder<List<UrgentBloodNeed>>(
        stream: firestore.getBloodNeedsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: SkeletonListView(count: 4, skeleton: SkeletonBloodCard()),
            );
          }
          if (snapshot.hasError) {
            return const Center(
              child: Text('Unable to load blood requests. Please retry.'),
            );
          }
          final needs = snapshot.data ?? [];
          if (needs.isEmpty) {
            return const Center(
              child: Text('No urgent blood requests at this moment.'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: needs.length,
            itemBuilder: (context, index) {
              final item = needs[index];
              final owner = item.isOwnedBy(
                context.watch<AuthService>().currentUser?.id ?? '',
              );

              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.emergencyRed.withValues(alpha: 0.3),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x06000000),
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.emergencyRed,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            item.bloodGroup,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.emergencyRed.withValues(
                              alpha: 0.1,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${item.unitsNeeded} Bag(s) Required',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.emergencyRed,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Patient: ${item.patientName}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.local_hospital,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            item.hospital,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    Text(
                      'Attendant: ${item.contact}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (!owner)
                          FilledButton.icon(
                            onPressed: () => openDialer(context, item.contact),
                            icon: const Icon(
                              Icons.volunteer_activism,
                              size: 18,
                            ),
                            label: const Text('I Will Donate'),
                          ),
                        if (owner)
                          TextButton.icon(
                            icon: const Icon(Icons.cancel_outlined, size: 18),
                            label: const Text('Cancel request'),
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Cancel blood request?'),
                                  content: const Text(
                                    'This request will no longer be listed for donors.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('Keep'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Cancel request'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed != true || !context.mounted) return;
                              try {
                                await context
                                    .read<FirestoreService>()
                                    .cancelUrgentBloodNeed(
                                      item.id,
                                      context
                                          .read<AuthService>()
                                          .currentUser!
                                          .id,
                                    );
                              } catch (_) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Could not cancel. Please retry.',
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
              );
            },
          );
        },
      ),
    );
  }
}

class _RegisterDonorTab extends StatefulWidget {
  const _RegisterDonorTab();

  @override
  State<_RegisterDonorTab> createState() => _RegisterDonorTabState();
}

class _RegisterDonorTabState extends State<_RegisterDonorTab> {
  String _bloodGroup = 'O+';
  final _cityController = TextEditingController(text: 'Abbottabad');
  final _phoneController = TextEditingController();
  bool _availability = true;
  bool _isSubmitting = false;

  final List<String> _bloodGroups = [
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
    'O+',
    'O-',
  ];

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthService>().currentUser;
    if (user != null) {
      _phoneController.text = user.phone;
    }
  }

  @override
  void dispose() {
    _cityController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _register() async {
    final auth = context.read<AuthService>();
    final firestore = context.read<FirestoreService>();
    final user = auth.currentUser;

    if (user == null ||
        !AppUser.isValidPhone(_phoneController.text) ||
        _cityController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please sign in and enter your city and a valid mobile number.',
          ),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final donor = BloodDonor(
      donorId: '',
      userId: user.id,
      userName: user.name,
      userPhone: AppUser.normalizePhone(_phoneController.text),
      bloodGroup: _bloodGroup,
      availability: _availability,
      city: _cityController.text.trim(),
    );

    try {
      await firestore.registerBloodDonor(donor);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not register donor. Please retry.'),
          ),
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Thank you! You are now registered in Edhi Blood Donor Network.',
          ),
          backgroundColor: AppColors.reliefGreenMedium,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.emergencyRed.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.emergencyRed.withValues(alpha: 0.2),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.favorite, color: AppColors.emergencyRed, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Be a Life Saver: Voluntary donors are alerted whenever someone in your city urgently needs matching blood.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.emergencyRed,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          const Text(
            'Select Your Blood Group',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _bloodGroups.map((g) {
              final isSelected = _bloodGroup == g;
              return ChoiceChip(
                label: Text(
                  g,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: isSelected ? Colors.white : AppColors.textPrimary,
                  ),
                ),
                selected: isSelected,
                selectedColor: AppColors.emergencyRed,
                onSelected: (val) {
                  if (val) setState(() => _bloodGroup = g);
                },
              );
            }).toList(),
          ),

          const SizedBox(height: 20),
          CustomTextField(
            controller: _cityController,
            label: 'Your City / Town',
            prefixIcon: Icons.location_city,
          ),
          const SizedBox(height: 14),
          CustomTextField(
            controller: _phoneController,
            label: 'Active Mobile Contact',
            keyboardType: TextInputType.phone,
            prefixIcon: Icons.phone,
          ),
          const SizedBox(height: 16),

          SwitchListTile(
            title: const Text(
              'Available for Immediate Donation',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'You can toggle this off if you recently donated or are unwell.',
              style: TextStyle(fontSize: 11),
            ),
            value: _availability,
            activeThumbColor: AppColors.reliefGreenMedium,
            onChanged: (val) => setState(() => _availability = val),
          ),

          const SizedBox(height: 24),
          CustomButton(
            text: 'Save & Register as Blood Donor',
            icon: Icons.bloodtype,
            color: AppColors.emergencyRed,
            isLoading: _isSubmitting,
            onPressed: _register,
          ),
        ],
      ),
    );
  }
}

class _SearchDonorsTab extends StatefulWidget {
  const _SearchDonorsTab();

  @override
  State<_SearchDonorsTab> createState() => _SearchDonorsTabState();
}

class _SearchDonorsTabState extends State<_SearchDonorsTab> {
  String _filterGroup = 'All';
  final _searchCityController = TextEditingController();

  final List<String> _filters = [
    'All',
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
    'O+',
    'O-',
  ];

  @override
  void dispose() {
    _searchCityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final firestore = context.watch<FirestoreService>();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _filters.map((g) {
                    final isSelected = _filterGroup == g;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(g),
                        selected: isSelected,
                        selectedColor: AppColors.emergencyRed.withValues(
                          alpha: 0.15,
                        ),
                        labelStyle: TextStyle(
                          color: isSelected
                              ? AppColors.emergencyRed
                              : AppColors.textPrimary,
                          fontWeight: isSelected
                              ? FontWeight.w800
                              : FontWeight.normal,
                          fontSize: 12,
                        ),
                        onSelected: (val) => setState(() => _filterGroup = g),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<BloodDonor>>(
            stream: firestore.getBloodDonorsStream(bloodGroup: _filterGroup),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: SkeletonListView(
                    count: 4,
                    skeleton: SkeletonBloodCard(),
                  ),
                );
              }
              if (snapshot.hasError) {
                return const Center(
                  child: Text('Unable to load donors. Please retry.'),
                );
              }
              final donors = snapshot.data ?? [];
              if (donors.isEmpty) {
                return const Center(
                  child: Text('No donors found matching criteria.'),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                itemCount: donors.length,
                itemBuilder: (context, index) {
                  final d = donors[index];

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: AppColors.emergencyRed,
                          child: Text(
                            d.bloodGroup,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d.userName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                d.city,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              Text(
                                d.userPhone,
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                d.availability ? 'Available' : 'Busy',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: d.availability
                                      ? AppColors.reliefGreenDark
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton.filledTonal(
                          tooltip: 'Call donor',
                          icon: const Icon(Icons.call_outlined, size: 20),
                          onPressed: d.userPhone.isEmpty
                              ? null
                              : () => openDialer(context, d.userPhone),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
