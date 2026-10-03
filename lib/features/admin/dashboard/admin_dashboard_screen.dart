import 'package:flutter/material.dart';
import '../../../core/widgets/edhi_center_card.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/responsive_shell.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../services/auth_service.dart';
import '../../../services/firestore_service.dart';
import '../../../models/emergency_request.dart';
import '../manage_requests/admin_dispatch_map_view.dart';
import '../donations/admin_donations_view.dart';
import '../blood_bank/admin_blood_bank_view.dart';
import '../reports/admin_reports_view.dart';
import '../users/admin_users_view.dart';
import '../fleet/registered_drivers_panel.dart';
import '../missing_persons/admin_missing_persons_view.dart';
import '../../../models/employee.dart';
import '../../../models/edhi_center.dart';
import '../../../services/location_service.dart';
import '../../../core/widgets/simulated_fleet_dialog.dart';
import '../../../core/widgets/skeleton_loader.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _selectedTabIndex = 0;
  String _fleetSearchQuery = '';
  String _fleetStatusFilter = 'All';
  int _fleetSubTab = 0; // 0: Fleet & Drivers, 1: Edhi Center Depots

  int get _adminNavigationIndex {
    if (_selectedTabIndex == 0) return 0;
    if (_selectedTabIndex == 1) return 1;
    if (_selectedTabIndex == 2 ||
        _selectedTabIndex == 3 ||
        _selectedTabIndex == 7) {
      return 2;
    }
    if (_selectedTabIndex == 4) return 3;
    return 4;
  }

  void _selectAdminDestination(int index) {
    setState(() {
      switch (index) {
        case 0:
          _selectedTabIndex = 0;
          break;
        case 1:
          _selectedTabIndex = 1;
          break;
        case 2:
          if (_selectedTabIndex != 2 &&
              _selectedTabIndex != 3 &&
              _selectedTabIndex != 7) {
            _selectedTabIndex = 2;
          }
          break;
        case 3:
          _selectedTabIndex = 4;
          break;
        case 4:
          if (_selectedTabIndex != 5 && _selectedTabIndex != 6) {
            _selectedTabIndex = 5;
          }
          break;
      }
    });
  }

  Future<void> _confirmDatabaseWipe(
    BuildContext context,
    FirestoreService firestore,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(
          Icons.warning_amber_rounded,
          color: AppColors.emergencyRed,
          size: 34,
        ),
        title: Text(
          'Permanently wipe all data?',
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'This deletes requests, ambulances, centers, donations, and reports. This action cannot be undone.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(color: AppColors.textSecondary),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep data'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Wipe everything'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    await firestore.wipeAllDataFromFirestore();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Database cleared.'),
        backgroundColor: AppColors.reliefGreenMedium,
      ),
    );
  }

  void _showAssignDialog(BuildContext context, EmergencyRequest req) {
    final firestore = context.read<FirestoreService>();
    final drivers = firestore.getAvailableDrivers();
    final reqLat = req.location.latitude != 0.0
        ? req.location.latitude
        : LocationService.defaultLocation.latitude;
    final reqLng = req.location.longitude != 0.0
        ? req.location.longitude
        : LocationService.defaultLocation.longitude;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.emergencyRed.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.emergency_rounded,
                color: AppColors.emergencyRed,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Assign Driver for #${req.requestId}',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_on_rounded,
                      size: 16,
                      color: AppColors.emergencyRed,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${req.emergencyType} • ${req.location.address}',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Available Fleet Drivers on Standby:',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              if (drivers.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  alignment: Alignment.center,
                  child: Text(
                    'No active drivers available. All units in mission.',
                    style: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                )
              else
                ...drivers.map((driver) {
                  final dist = LocationService.calculateDistanceInKm(
                    driver.currentLat,
                    driver.currentLng,
                    reqLat,
                    reqLng,
                  );
                  final eta = LocationService.calculateEtaMinutes(
                    dist,
                    averageSpeedKmH: 45,
                  );

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 4,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: AppColors.reliefGreenSoft,
                        child: const Icon(
                          Icons.airport_shuttle_rounded,
                          color: AppColors.reliefGreenMedium,
                        ),
                      ),
                      title: Text(
                        driver.name,
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        '${driver.vehicleNumber} • ${driver.vehicleModel}\n$dist km away • ~${eta}m ETA • ${driver.phone}',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      isThreeLine: true,
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.reliefGreenMedium,
                          minimumSize: const Size(80, 36),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () async {
                          try {
                            await firestore.assignRequest(
                              requestId: req.requestId,
                              employeeId: driver.employeeId,
                              employeeName:
                                  '${driver.name} (${driver.vehicleNumber})',
                            );
                            if (context.mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Mission #${req.requestId} assigned to ${driver.name} (${driver.vehicleNumber})',
                                  ),
                                  backgroundColor: AppColors.reliefGreenMedium,
                                ),
                              );
                            }
                          } catch (error) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    error.toString().replaceFirst(
                                      'Bad state: ',
                                      '',
                                    ),
                                  ),
                                  backgroundColor: AppColors.emergencyRed,
                                ),
                              );
                            }
                          }
                        },
                        child: Text(
                          'Dispatch',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddDriverDialog(BuildContext parentContext) {
    showSimulatedFleetDialog(
      parentContext,
      stagingPoint: LocationService.defaultLocation,
    );
  }

  void _showAssignDriverToRequestDialog(
    BuildContext context,
    Employee driver,
    List<EmergencyRequest> pendingRequests,
  ) {
    final firestore = context.read<FirestoreService>();

    if (pendingRequests.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.reliefGreenSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.reliefGreenMedium,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'All Incidents Dispatched',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
            ],
          ),
          content: Text(
            'There are no unassigned emergency calls waiting for dispatch right now.\n\nUnit ${driver.vehicleNumber} (${driver.name}) is on active standby and ready to respond.',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'OK',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.emergencyRed.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.emergency_rounded,
                color: AppColors.emergencyRed,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dispatch Unit: ${driver.vehicleNumber}',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                  Text(
                    'Driver: ${driver.name} • ${driver.vehicleModel}',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select Pending Emergency Call:',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: pendingRequests.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, idx) {
                    final req = pendingRequests[idx];
                    final reqLat = req.location.latitude != 0.0
                        ? req.location.latitude
                        : LocationService.defaultLocation.latitude;
                    final reqLng = req.location.longitude != 0.0
                        ? req.location.longitude
                        : LocationService.defaultLocation.longitude;
                    final dist = LocationService.calculateDistanceInKm(
                      driver.currentLat,
                      driver.currentLng,
                      reqLat,
                      reqLng,
                    );
                    final eta = LocationService.calculateEtaMinutes(
                      dist,
                      averageSpeedKmH: 45,
                    );

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.emergencyRed.withValues(
                                alpha: 0.1,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.warning_amber_rounded,
                              color: AppColors.emergencyRed,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      '#${req.requestId}',
                                      style: GoogleFonts.outfit(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    StatusBadge(status: req.status),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${req.emergencyType} • ${req.location.address}',
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '$dist km away • Estimated ETA: ~$eta mins',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.reliefGreenMedium,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () async {
                              await firestore.assignRequest(
                                requestId: req.requestId,
                                employeeId: driver.employeeId,
                                employeeName:
                                    '${driver.name} (${driver.vehicleNumber})',
                              );
                              if (context.mounted) {
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Unit ${driver.vehicleNumber} dispatched to #${req.requestId}!',
                                    ),
                                    backgroundColor:
                                        AppColors.reliefGreenMedium,
                                  ),
                                );
                              }
                            },
                            child: Text(
                              'Dispatch',
                              style: GoogleFonts.outfit(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final firestore = context.watch<FirestoreService>();

    return ResponsiveShell(
      desktopPortal: true,
      maxWidth: 560,
      appBar: AppBar(
        toolbarHeight: 68,
        title: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: AppColors.emergencyGradient,
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Icons.shield_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Operations HQ',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: AppColors.reliefGreenMedium,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          'Emergency coordination',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Admin menu',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) async {
              if (value == 'logout') {
                await auth.signOut();
              } else if (value == 'wipe' && context.mounted) {
                await _confirmDatabaseWipe(context, firestore);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.logout_rounded),
                  title: Text('Sign out'),
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'wipe',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.delete_forever_rounded,
                    color: AppColors.emergencyRed,
                  ),
                  title: Text('Wipe all data'),
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        height: 72,
        selectedIndex: _adminNavigationIndex,
        onDestinationSelected: _selectAdminDestination,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.inbox_outlined),
            selectedIcon: Icon(Icons.inbox_rounded),
            label: 'Queue',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map_rounded),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_border_rounded),
            selectedIcon: Icon(Icons.favorite_rounded),
            label: 'Welfare',
          ),
          NavigationDestination(
            icon: Icon(Icons.airport_shuttle_outlined),
            selectedIcon: Icon(Icons.airport_shuttle_rounded),
            label: 'Fleet',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'More',
          ),
        ],
      ),
      child: StreamBuilder<List<EmergencyRequest>>(
        stream: firestore.getRequestsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GridView.count(
                    crossAxisCount: MediaQuery.of(context).size.width > 900
                        ? 4
                        : 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    mainAxisExtent: 130,
                    children: const [
                      SkeletonMetricTile(),
                      SkeletonMetricTile(),
                      SkeletonMetricTile(),
                      SkeletonMetricTile(),
                    ],
                  ),
                  const SizedBox(height: 28),
                  const SkeletonBox(width: 220, height: 20, borderRadius: 6),
                  const SizedBox(height: 16),
                  const SkeletonListView(
                    count: 3,
                    skeleton: SkeletonEmergencyCard(),
                  ),
                ],
              ),
            );
          }
          final requests = snapshot.data ?? [];
          final pendingCount = requests
              .where((r) => r.status == EmergencyStatus.pending)
              .length;
          final activeCount = requests
              .where(
                (r) =>
                    r.status == EmergencyStatus.assigned ||
                    r.status == EmergencyStatus.inProgress ||
                    r.status == EmergencyStatus.arrived,
              )
              .length;
          final completedCount = requests
              .where((r) => r.status == EmergencyStatus.completed)
              .length;
          final fleet = firestore
              .getAllEmployees()
              .where((employee) => employee.role == 'driver')
              .toList();
          final availableFleet = fleet
              .where((employee) => employee.status == 'available')
              .length;

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (snapshot.hasError) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.emergencyRed.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.emergencyRed.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.cloud_off_rounded,
                          color: AppColors.emergencyRed,
                          size: 28,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Cloud Firestore Setup Required',
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14.5,
                                  color: AppColors.emergencyRed,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Your Firebase project currently does not have a Cloud Firestore Database created. Please open your Firebase Console > Firestore Database > Create Database (Start in test mode) to enable live synchronization.',
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                // KPI Metrics Overview
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth > 860) {
                      return Row(
                        children: [
                          Expanded(
                            child: _buildKpiCard(
                              title: 'Pending Dispatch',
                              value: '$pendingCount',
                              icon: Icons.warning_amber_rounded,
                              color: AppColors.statusPending,
                              subtitle: 'Requires immediate action',
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildKpiCard(
                              title: 'Active In Transit',
                              value: '$activeCount',
                              icon: Icons.airport_shuttle_rounded,
                              color: AppColors.statusInProgress,
                              subtitle: 'En route to victims',
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildKpiCard(
                              title: 'Completed Missions',
                              value: '$completedCount',
                              icon: Icons.check_circle_outline_rounded,
                              color: AppColors.statusCompleted,
                              subtitle: 'Successfully rescued',
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildKpiCard(
                              title: 'Ambulance Units',
                              value: '$availableFleet/${fleet.length}',
                              icon: Icons.emergency_rounded,
                              color: AppColors.reliefGreenMedium,
                              subtitle: 'Available now',
                            ),
                          ),
                        ],
                      );
                    } else {
                      return Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _buildKpiCard(
                                  title: 'Pending Dispatch',
                                  value: '$pendingCount',
                                  icon: Icons.warning_amber_rounded,
                                  color: AppColors.statusPending,
                                  subtitle: 'Requires immediate action',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildKpiCard(
                                  title: 'Active In Transit',
                                  value: '$activeCount',
                                  icon: Icons.airport_shuttle_rounded,
                                  color: AppColors.statusInProgress,
                                  subtitle: 'En route to victims',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildKpiCard(
                                  title: 'Completed Missions',
                                  value: '$completedCount',
                                  icon: Icons.check_circle_outline_rounded,
                                  color: AppColors.statusCompleted,
                                  subtitle: 'Successfully rescued',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildKpiCard(
                                  title: 'Ambulance Units',
                                  value: '$availableFleet/${fleet.length}',
                                  icon: Icons.emergency_rounded,
                                  color: AppColors.reliefGreenMedium,
                                  subtitle: 'Available now',
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    }
                  },
                ),

                const SizedBox(height: 28),

                _buildAdminSectionHeading(pendingCount),
                if (_selectedTabIndex == 2 ||
                    _selectedTabIndex == 3 ||
                    _selectedTabIndex == 7) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildTabButton('Donations', 2),
                      _buildTabButton('Blood Bank', 3),
                      _buildTabButton('Missing persons', 7),
                    ],
                  ),
                ],
                if (_selectedTabIndex == 5 || _selectedTabIndex == 6) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _buildTabButton('Reports', 5)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildTabButton('People', 6)),
                    ],
                  ),
                ],

                const SizedBox(height: 16),

                if (_selectedTabIndex == 0)
                  _buildRequestsTable(context, requests)
                else if (_selectedTabIndex == 1)
                  const AdminDispatchMapView()
                else if (_selectedTabIndex == 2)
                  const AdminDonationsView()
                else if (_selectedTabIndex == 3)
                  const AdminBloodBankView()
                else if (_selectedTabIndex == 4)
                  _buildFleetAndCentersView(context, firestore, requests)
                else if (_selectedTabIndex == 5)
                  const AdminReportsView()
                else if (_selectedTabIndex == 7)
                  const AdminMissingPersonsView()
                else
                  const AdminUsersView(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAdminSectionHeading(int pendingCount) {
    late final String title;
    late final String subtitle;
    late final IconData icon;

    switch (_selectedTabIndex) {
      case 0:
        title = 'Dispatch queue';
        subtitle = pendingCount == 0
            ? 'No emergencies are waiting for assignment'
            : '$pendingCount ${pendingCount == 1 ? 'incident needs' : 'incidents need'} attention';
        icon = Icons.inbox_rounded;
        break;
      case 1:
        title = 'Live operations map';
        subtitle = 'Track incidents and ambulance movement';
        icon = Icons.map_rounded;
        break;
      case 2:
      case 3:
        title = 'Welfare services';
        subtitle = 'Donations, blood coordination, and missing-person reports';
        icon = Icons.favorite_rounded;
        break;
      case 7:
        title = 'Missing-person reports';
        subtitle = 'Photos, last-seen details, and family contacts';
        icon = Icons.person_search_rounded;
        break;
      case 4:
        title = 'Fleet operations';
        subtitle = 'Drivers, vehicles, readiness, and centers';
        icon = Icons.airport_shuttle_rounded;
        break;
      default:
        title = 'Administration';
        subtitle = 'Reports, analytics, users, and personnel';
        icon = Icons.admin_panel_settings_rounded;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.emergencyRed.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: AppColors.emergencyRed, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(String title, int index) {
    final isSelected = _selectedTabIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedTabIndex = index),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.emergencyRed : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.emergencyRed : AppColors.border,
            width: 1.1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.emergencyRed.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Text(
          title,
          style: GoogleFonts.outfit(
            color: isSelected ? Colors.white : AppColors.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 13,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border, width: 1.1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: [
            Container(height: 3.5, color: color),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: color, size: 26),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          value,
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              color: color,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestsTable(
    BuildContext context,
    List<EmergencyRequest> requests,
  ) {
    if (requests.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(48),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(
              Icons.assignment_turned_in_outlined,
              size: 54,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 14),
            Text(
              'No Emergency Requests in Queue',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'All incident dispatches are currently settled and clear.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: requests.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final req = requests[index];
        final isPending = req.status == EmergencyStatus.pending;
        final isOverdue =
            isPending &&
            (req.createdAt != null &&
                DateTime.now().difference(req.createdAt!).inMinutes >= 3);

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isOverdue ? AppColors.emergencyRed : AppColors.border,
              width: isOverdue ? 1.5 : 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: isOverdue
                    ? AppColors.emergencyRed.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(18),
          child: LayoutBuilder(
            builder: (context, cardConstraints) {
              final isCardWide = cardConstraints.maxWidth > 750;

              final detailsColumn = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        '#${req.requestId}',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        '• ${req.emergencyType}',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      StatusBadge(status: req.status),
                      PriorityBadge(priority: req.priority),
                      if (req.isDuplicate) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade600),
                          ),
                          child: Text(
                            '⚠️ Duplicate #${req.duplicateOfRequestId ?? 'id'}',
                            style: GoogleFonts.inter(
                              color: Colors.amber.shade900,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                      if (req.fraudRiskLevel == 'High') ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade300),
                          ),
                          child: Text(
                            '🚨 High Fraud Risk (${(req.fraudRiskScore * 100).toInt()}%)',
                            style: GoogleFonts.inter(
                              color: Colors.red.shade900,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ] else if (req.fraudRiskLevel == 'Medium') ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.shade300),
                          ),
                          child: Text(
                            '⚠️ Moderate Risk (${(req.fraudRiskScore * 100).toInt()}%)',
                            style: GoogleFonts.inter(
                              color: Colors.orange.shade900,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.shade300),
                          ),
                          child: Text(
                            '🛡️ Verified',
                            style: GoogleFonts.inter(
                              color: Colors.green.shade800,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    req.description,
                    style: GoogleFonts.inter(
                      fontSize: 13.5,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.place_rounded,
                        size: 14,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          req.location.address,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (req.fraudRiskLevel == 'High' &&
                      req.fraudReason != null &&
                      req.fraudReason!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            size: 14,
                            color: Colors.red.shade700,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Fraud Engine Flag: ${req.fraudReason}',
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                color: Colors.red.shade800,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (isOverdue) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.emergencyRed.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.emergencyRed.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.alarm_on_rounded,
                            size: 14,
                            color: AppColors.emergencyRed,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'SLA ESCALATION: Unassigned > 3 mins (Immediate Dispatch Mandated)',
                              style: GoogleFonts.inter(
                                color: AppColors.emergencyRed,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              );

              final contactColumn = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    req.userName,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    req.userPhone,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (req.assignedEmployeeName != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.badge_rounded,
                          size: 14,
                          color: AppColors.reliefGreenMedium,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Driver: ${req.assignedEmployeeName}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppColors.reliefGreenMedium,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              );

              final actionButtons = Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (isPending && req.fraudRiskLevel == 'High') ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green.shade800,
                        side: BorderSide(color: Colors.green.shade400),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(
                        Icons.check_circle_outline_rounded,
                        size: 14,
                      ),
                      label: Text(
                        'Verify',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: () {
                        context.read<FirestoreService>().verifyEmergencyRequest(
                          req.requestId,
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Request marked as verified.'),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.cancel_outlined, size: 14),
                      label: Text(
                        'Reject Prank',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: () {
                        context
                            .read<FirestoreService>()
                            .rejectFraudEmergencyRequest(req.requestId);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Prank request rejected and archived.',
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (isPending && req.fraudRiskLevel != 'High')
                    ElevatedButton.icon(
                      icon: const Icon(Icons.near_me_rounded, size: 16),
                      label: Text(
                        'Assign Driver',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.emergencyRed,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () => _showAssignDialog(context, req),
                    ),
                  if (isPending && req.fraudRiskLevel != 'High')
                    const SizedBox(width: 8),
                  if (isPending)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.emergencyRed,
                        side: const BorderSide(
                          color: AppColors.border,
                          width: 1.2,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        context.read<FirestoreService>().updateRequestStatus(
                          req.requestId,
                          EmergencyStatus.cancelled,
                        );
                      },
                      child: Text(
                        'Decline',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              );

              if (isCardWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: isPending
                            ? AppColors.emergencyRed.withValues(alpha: 0.1)
                            : AppColors.background,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        req.status == EmergencyStatus.completed
                            ? Icons.check_circle_rounded
                            : (req.status == EmergencyStatus.inProgress
                                  ? Icons.directions_car_filled_rounded
                                  : Icons.emergency_rounded),
                        color: isPending
                            ? AppColors.emergencyRed
                            : AppColors.textSecondary,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(flex: 4, child: detailsColumn),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: contactColumn),
                    const SizedBox(width: 16),
                    actionButtons,
                  ],
                );
              } else {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: isPending
                                ? AppColors.emergencyRed.withValues(alpha: 0.1)
                                : AppColors.background,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            req.status == EmergencyStatus.completed
                                ? Icons.check_circle_rounded
                                : (req.status == EmergencyStatus.inProgress
                                      ? Icons.directions_car_filled_rounded
                                      : Icons.emergency_rounded),
                            color: isPending
                                ? AppColors.emergencyRed
                                : AppColors.textSecondary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: detailsColumn),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: AppColors.border),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 16,
                      runSpacing: 10,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [contactColumn, actionButtons],
                    ),
                  ],
                );
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildFleetAndCentersView(
    BuildContext context,
    FirestoreService firestore,
    List<EmergencyRequest> requests,
  ) {
    return StreamBuilder<List<Employee>>(
      stream: firestore.getEmployeesStream(),
      builder: (context, snapshot) {
        final employees = snapshot.data ?? firestore.getAllEmployees();
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData &&
            employees.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: SkeletonListView(
              count: 4,
              skeleton: SkeletonAmbulanceCard(),
            ),
          );
        }
        final drivers = employees.where((e) => e.role == 'driver').toList();
        final centers = firestore.getEdhiCenters();

        final availableCount = drivers
            .where((d) => d.status == 'available')
            .length;
        final busyCount = drivers.where((d) => d.status == 'busy').length;
        final offlineCount = drivers.where((d) => d.status == 'offline').length;
        final pendingRequests = requests
            .where((r) => r.status == EmergencyStatus.pending)
            .toList();

        final filteredDrivers = drivers.where((d) {
          final matchesQuery =
              _fleetSearchQuery.isEmpty ||
              d.name.toLowerCase().contains(_fleetSearchQuery.toLowerCase()) ||
              d.vehicleNumber.toLowerCase().contains(
                _fleetSearchQuery.toLowerCase(),
              ) ||
              d.vehicleModel.toLowerCase().contains(
                _fleetSearchQuery.toLowerCase(),
              ) ||
              d.phone.contains(_fleetSearchQuery);

          if (!matchesQuery) return false;

          if (_fleetStatusFilter == 'Available') return d.status == 'available';
          if (_fleetStatusFilter == 'In Mission') return d.status == 'busy';
          if (_fleetStatusFilter == 'Offline') return d.status == 'offline';
          return true;
        }).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Fleet Telemetry KPI Row
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 860;
                final tiles = [
                  _buildFleetKpiTile(
                    'Total Ambulance Fleet',
                    '${drivers.length} Units',
                    Icons.airport_shuttle_rounded,
                    AppColors.emergencyRed,
                    'Operational inventory',
                  ),
                  _buildFleetKpiTile(
                    'Active On Standby',
                    '$availableCount Ready',
                    Icons.check_circle_rounded,
                    AppColors.reliefGreenMedium,
                    'Available for instant dispatch',
                  ),
                  _buildFleetKpiTile(
                    'Engaged In Missions',
                    '$busyCount En Route',
                    Icons.navigation_rounded,
                    const Color(0xFF2563EB),
                    'Dispatched to emergencies',
                  ),
                  _buildFleetKpiTile(
                    'Offline / Depots',
                    '$offlineCount Units',
                    Icons.power_settings_new_rounded,
                    AppColors.textSecondary,
                    'Maintenance & reserve',
                  ),
                ];

                if (isWide) {
                  return Row(
                    children: tiles
                        .map(
                          (t) => Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              child: t,
                            ),
                          ),
                        )
                        .toList(),
                  );
                } else {
                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: tiles[0]),
                          const SizedBox(width: 8),
                          Expanded(child: tiles[1]),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: tiles[2]),
                          const SizedBox(width: 8),
                          Expanded(child: tiles[3]),
                        ],
                      ),
                    ],
                  );
                }
              },
            ),

            const SizedBox(height: 20),

            // Segmented Switcher & Top Action Button
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0D000000),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _buildFleetSubTabButton(
                          'Ambulances (${drivers.length})',
                          0,
                          Icons.airport_shuttle_rounded,
                        ),
                        _buildFleetSubTabButton(
                          'Edhi Center Depots (${centers.length})',
                          1,
                          Icons.local_hospital_rounded,
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.reliefGreenMedium,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 2,
                    ),
                    icon: const Icon(Icons.add_circle_rounded, size: 20),
                    label: Text(
                      'Create ambulance & assign driver',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                    onPressed: () => _showAddDriverDialog(context),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            if (_fleetSubTab == 0) ...[
              RegisteredDriversPanel(
                ambulances: drivers,
                stagingPoint: LocationService.defaultLocation,
                searchQuery: _fleetSearchQuery,
              ),
              const SizedBox(height: 16),
              // Filters & Search Bar for Drivers
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (val) =>
                            setState(() => _fleetSearchQuery = val),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            size: 20,
                            color: AppColors.textSecondary,
                          ),
                          hintText:
                              'Search by driver name, vehicle plate (e.g. EDHI-402), or model...',
                          filled: true,
                          fillColor: AppColors.background,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: ['All', 'Available', 'In Mission', 'Offline']
                            .map((status) {
                              final isSelected = _fleetStatusFilter == status;
                              return Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: ChoiceChip(
                                  label: Text(status),
                                  selected: isSelected,
                                  selectedColor: AppColors.reliefGreenMedium
                                      .withValues(alpha: 0.15),
                                  labelStyle: GoogleFonts.outfit(
                                    color: isSelected
                                        ? AppColors.reliefGreenMedium
                                        : AppColors.textPrimary,
                                    fontWeight: isSelected
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                  onSelected: (val) {
                                    if (val) {
                                      setState(
                                        () => _fleetStatusFilter = status,
                                      );
                                    }
                                  },
                                ),
                              );
                            })
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              if (filteredDrivers.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(48),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.airport_shuttle_outlined,
                        size: 50,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No matching ambulances found',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Add an ambulance or assign one to a registered driver above.',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isMultiCol = constraints.maxWidth > 860;
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: isMultiCol ? 2 : 1,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        mainAxisExtent: 220,
                      ),
                      itemCount: filteredDrivers.length,
                      itemBuilder: (context, idx) {
                        final driver = filteredDrivers[idx];
                        return _buildDriverCard(
                          context,
                          firestore,
                          driver,
                          centers,
                          pendingRequests,
                        );
                      },
                    );
                  },
                ),
            ] else ...[
              _buildEdhiCentersGrid(centers),
            ],
          ],
        );
      },
    );
  }

  Widget _buildFleetSubTabButton(String title, int index, IconData icon) {
    final isSelected = _fleetSubTab == index;
    return InkWell(
      onTap: () => setState(() => _fleetSubTab = index),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected
                  ? AppColors.emergencyRed
                  : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: GoogleFonts.outfit(
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 12.5,
                color: isSelected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFleetKpiTile(
    String label,
    String value,
    IconData icon,
    Color color,
    String subtitle,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverCard(
    BuildContext context,
    FirestoreService firestore,
    Employee driver,
    List<EdhiCenter> centers,
    List<EmergencyRequest> pendingRequests,
  ) {
    final isAvailable = driver.status == 'available';
    final isBusy = driver.status == 'busy';
    final assignedCenter = centers
        .where((c) => c.centerId == driver.assignedCenterId)
        .firstOrNull;

    final statusColor = isAvailable
        ? AppColors.reliefGreenMedium
        : (isBusy ? const Color(0xFF2563EB) : AppColors.textSecondary);
    final statusBg = isAvailable
        ? AppColors.reliefGreenSoft
        : (isBusy ? const Color(0xFFEFF6FF) : Colors.grey.shade100);
    final statusText = isAvailable
        ? 'AVAILABLE'
        : (isBusy ? 'IN MISSION' : 'OFFLINE');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border, width: 1.1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.airport_shuttle_rounded,
                  color: statusColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          driver.vehicleNumber,
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: statusBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: statusColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                statusText,
                                style: GoogleFonts.outfit(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: statusColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Text(
                      driver.vehicleModel,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onSelected: (val) async {
                  if (val == 'link_driver') {
                    await showLinkDriverDialog(context, driver);
                  } else if (val == 'toggle_status') {
                    final nextStatus = driver.status == 'available'
                        ? 'offline'
                        : 'available';
                    try {
                      await firestore.toggleDriverAvailability(
                        driver.employeeId,
                        nextStatus == 'available',
                      );
                    } catch (error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('$error')));
                      }
                      return;
                    }
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Unit ${driver.vehicleNumber} marked $nextStatus',
                        ),
                      ),
                    );
                  } else if (val == 'delete') {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: Text('Decommission ${driver.vehicleNumber}?'),
                        content: Text(
                          'Remove driver ${driver.name} and vehicle ${driver.vehicleNumber} from the active fleet?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.emergencyRed,
                            ),
                            onPressed: () => Navigator.pop(c, true),
                            child: const Text(
                              'Decommission',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      try {
                        await firestore.deleteEmployee(driver.employeeId);
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('$error')));
                        }
                        return;
                      }
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Unit ${driver.vehicleNumber} decommissioned from fleet.',
                            ),
                          ),
                        );
                      }
                    }
                  }
                },
                itemBuilder: (c) => [
                  PopupMenuItem(
                    value: 'link_driver',
                    enabled: driver.status != 'busy',
                    child: const Text('Link registered driver'),
                  ),
                  PopupMenuItem(
                    value: 'toggle_status',
                    enabled: driver.status != 'busy',
                    child: Row(
                      children: [
                        Icon(
                          driver.status == 'available'
                              ? Icons.pause_circle_outline
                              : Icons.play_circle_outline,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          driver.status == 'available'
                              ? 'Set Offline / Standby'
                              : 'Set Available',
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline_rounded,
                          color: AppColors.emergencyRed,
                          size: 16,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Decommission Unit',
                          style: TextStyle(color: AppColors.emergencyRed),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              const Icon(
                Icons.person_rounded,
                size: 14,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                driver.name,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(width: 12),
              const Icon(
                Icons.phone_rounded,
                size: 14,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                driver.phone,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              if (assignedCenter != null) ...[
                const SizedBox(width: 12),
                const Icon(
                  Icons.local_hospital_rounded,
                  size: 13,
                  color: AppColors.reliefGreenMedium,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    assignedCenter.name,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: AppColors.reliefGreenMedium,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.my_location_rounded,
                  size: 14,
                  color: AppColors.emergencyRed,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Position: ${driver.currentLat.toStringAsFixed(4)}, ${driver.currentLng.toStringAsFixed(4)}',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      driver.batteryFuel > 50
                          ? Icons.battery_charging_full_rounded
                          : Icons.battery_alert_rounded,
                      size: 14,
                      color: driver.batteryFuel > 50
                          ? AppColors.reliefGreenMedium
                          : Colors.orange,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      driver.batteryFuel < 0
                          ? 'Fuel not reported'
                          : '${driver.batteryFuel}% (reported)',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.speed_rounded,
                      size: 14,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${driver.speedKmh} km/h',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Spacer(),

          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(
                  Icons.map_rounded,
                  size: 15,
                  color: AppColors.textPrimary,
                ),
                label: Text(
                  'Locate on Map',
                  style: GoogleFonts.outfit(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                onPressed: () {
                  setState(() => _selectedTabIndex = 1);
                },
              ),
              const SizedBox(width: 8),
              if (isAvailable)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.reliefGreenMedium,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.send_rounded, size: 14),
                  label: Text(
                    'Assign to Call',
                    style: GoogleFonts.outfit(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onPressed: () => _showAssignDriverToRequestDialog(
                    context,
                    driver,
                    pendingRequests,
                  ),
                )
              else if (isBusy)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF93C5FD)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.navigation_rounded,
                        size: 13,
                        color: Color(0xFF1D4ED8),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'En Route Mission',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1D4ED8),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.textSecondary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.play_circle_outline, size: 14),
                  label: Text(
                    'Activate Unit',
                    style: GoogleFonts.outfit(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onPressed: () async {
                    try {
                      await firestore.updateEmployeeStatus(
                        driver.employeeId,
                        'available',
                      );
                    } catch (error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('$error')));
                      }
                      return;
                    }
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Unit ${driver.vehicleNumber} is now available on standby!',
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEdhiCentersGrid(List<EdhiCenter> centers) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 620
            ? 2
            : 1;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: centers
              .map(
                (center) => SizedBox(
                  width: width,
                  child: EdhiCenterCard(center: center),
                ),
              )
              .toList(),
        );
      },
    );
  }
}
