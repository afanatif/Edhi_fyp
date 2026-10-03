import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../core/widgets/responsive_shell.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../services/auth_service.dart';
import '../../../services/firestore_service.dart';
import '../../../models/emergency_request.dart';
import '../../notifications/notification_dialog.dart';
import '../emergency_request/track_request_screen.dart';
import '../../../core/widgets/location_picker_sheet.dart';
import '../../../services/location_service.dart';
import '../donations/donations_screen.dart';
import '../blood_bank/blood_bank_screen.dart';
import '../profile/user_profile_screen.dart';
import '../quick_help/first_aid_screen.dart';
import '../quick_help/emergency_contacts_sheet.dart';
import '../quick_help/edhi_centers_screen.dart';
import '../chatbot/ai_chatbot_screen.dart';
import '../missing_persons/missing_persons_screen.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/emergency_policy_banner.dart';
import '../../../core/widgets/contact_actions.dart';
import '../../../core/widgets/current_location_display.dart';

class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen> {
  int _bottomNavIndex = 0;
  RequestLocation? _currentLocation;

  void _triggerSosQuickSheet(BuildContext context, [String? initialCategory]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _QuickSosModalSheet(
        initialCategory: initialCategory,
        initialLocation: _currentLocation,
      ),
    );
  }

  String _getTimeOfDayGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final firestore = context.watch<FirestoreService>();
    final user = auth.currentUser;

    return ResponsiveShell(
      appBar: AppBar(
        toolbarHeight: 70,
        title: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.reliefGreenSoft,
                  child: Text(
                    user != null && user.name.isNotEmpty
                        ? user.name[0].toUpperCase()
                        : 'C',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w800,
                      color: AppColors.reliefGreenMedium,
                      fontSize: 16,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppColors.reliefGreenMedium,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${_getTimeOfDayGreeting()}, ${user?.name.split(' ').first ?? 'Citizen'} 👋',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  CurrentLocationDisplay(
                    onChanged: (location) => _currentLocation = location,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Quick Helpline Pill
          InkWell(
            onTap: () => openDialer(context, '115'),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.reliefGreenSoft,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.reliefGreenMedium.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.phone_in_talk_rounded,
                    size: 14,
                    color: AppColors.reliefGreenMedium,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '115',
                    style: GoogleFonts.outfit(
                      color: AppColors.reliefGreenMedium,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const NotificationDialog(),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sign Out',
            onPressed: () => auth.signOut(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border, width: 1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _bottomNavIndex,
          onTap: (idx) => setState(() => _bottomNavIndex = idx),
          selectedItemColor: AppColors.emergencyRed,
          unselectedItemColor: AppColors.textSecondary,
          selectedLabelStyle: GoogleFonts.outfit(
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
          unselectedLabelStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w500,
            fontSize: 11,
          ),
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          backgroundColor: Colors.transparent,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.volunteer_activism_rounded),
              label: 'Donate',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.water_drop_rounded),
              label: 'Blood Bank',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
      child: _bottomNavIndex == 1
          ? const DonationsScreen()
          : _bottomNavIndex == 2
          ? const BloodBankScreen()
          : _bottomNavIndex == 3
          ? const UserProfileScreen()
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Prominent SOS Hero Card with Multi-Ring Pulse
                  if (user != null) EmergencyPolicyBanner(userId: user.id),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white,
                          AppColors.emergencyRed.withValues(alpha: 0.04),
                          AppColors.reliefGreenSoft.withValues(alpha: 0.08),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.border, width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.emergencyRed.withValues(alpha: 0.06),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.emergencyRed.withValues(
                              alpha: 0.1,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppColors.emergencyRed.withValues(
                                alpha: 0.2,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: AppColors.emergencyRed,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'REQUEST AMBULANCE',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.outfit(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.emergencyRed,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Do you need immediate help?',
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Share your location with Operations and follow your assigned ambulance. For urgent assistance, call Edhi 115.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // 3D Multi-Ring Ambient Pulse SOS Core
                        SosPulsingButton(
                          onTap: () => _triggerSosQuickSheet(context),
                        ),

                        const SizedBox(height: 20),

                        // 1-Tap Quick Category Selector Strip
                        Text(
                          'Or choose quick emergency category:',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            _buildFastDispatchChip(
                              'Road Accident',
                              Icons.car_crash_rounded,
                              AppColors.emergencyRed,
                            ),
                            _buildFastDispatchChip(
                              'Medical / Cardiac',
                              Icons.medical_services_rounded,
                              const Color(0xFF0284C7),
                            ),
                            _buildFastDispatchChip(
                              'Fire Crisis',
                              Icons.local_fire_department_rounded,
                              const Color(0xFFD97706),
                            ),
                            _buildFastDispatchChip(
                              'Patient Transfer',
                              Icons.accessible_rounded,
                              AppColors.reliefGreenMedium,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Active Requests Live Tracking HUD
                  StreamBuilder<List<EmergencyRequest>>(
                    stream: firestore.getUserRequestsStream(user?.id ?? ''),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        debugPrint(
                          'getUserRequestsStream notice: ${snapshot.error}',
                        );
                      }
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData) {
                        return const SkeletonEmergencyCard();
                      }
                      final requests = snapshot.data ?? [];
                      if (requests.isEmpty) return const SizedBox.shrink();

                      final active = requests.first;
                      final isCompleted =
                          active.status == EmergencyStatus.completed;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Active Mission Status',
                                style: GoogleFonts.outfit(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (!isCompleted)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.statusPending.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    'LIVE TELEMETRY',
                                    style: GoogleFonts.outfit(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.statusPending,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TrackRequestScreen(
                                    requestId: active.requestId,
                                  ),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isCompleted
                                      ? AppColors.reliefGreenMedium
                                      : AppColors.emergencyRedLight,
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        (isCompleted
                                                ? AppColors.reliefGreenMedium
                                                : AppColors.emergencyRed)
                                            .withValues(alpha: 0.08),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: AppColors.emergencyRed
                                                  .withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: const Icon(
                                              Icons.airport_shuttle_rounded,
                                              color: AppColors.emergencyRed,
                                              size: 20,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                active.emergencyType,
                                                style: GoogleFonts.outfit(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              Text(
                                                'Ticket #${active.requestId}',
                                                style: GoogleFonts.inter(
                                                  fontSize: 11,
                                                  color:
                                                      AppColors.textSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      StatusBadge(status: active.status),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppColors.background,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.location_pin,
                                          size: 16,
                                          color: AppColors.emergencyRed,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            active.location.address,
                                            style: GoogleFonts.inter(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (active.assignedEmployeeName != null) ...[
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        const CircleAvatar(
                                          radius: 12,
                                          backgroundColor:
                                              AppColors.reliefGreenSoft,
                                          child: Icon(
                                            Icons.directions_car_rounded,
                                            size: 14,
                                            color: AppColors.reliefGreenMedium,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Assigned: ${active.assignedEmployeeName}',
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color:
                                                  AppColors.reliefGreenMedium,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.reliefGreenSoft,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            'TRACK RESPONSE',
                                            style: GoogleFonts.outfit(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                              color:
                                                  AppColors.reliefGreenMedium,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  const SizedBox(height: 14),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text(
                                        'Tap to View Live Route & Driver Tracker',
                                        style: GoogleFonts.outfit(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.emergencyRed,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      const Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 14,
                                        color: AppColors.emergencyRed,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                        ],
                      );
                    },
                  ),

                  // Quick Help Services Section (2x3 Grid)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Emergency & Relief Services',
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        'Call 115',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.reliefGreenMedium,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    mainAxisExtent: 190,
                    children: [
                      _buildQuickActionCard(
                        icon: Icons.medical_services_rounded,
                        title: 'First Aid Tips',
                        subtitle: 'CPR & trauma guide',
                        tag: 'Life Support',
                        color: AppColors.reliefGreenMedium,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const FirstAidScreen(),
                            ),
                          );
                        },
                      ),
                      _buildQuickActionCard(
                        icon: Icons.contact_phone_rounded,
                        title: 'SOS Contacts',
                        subtitle: 'Emergency phone numbers',
                        tag: 'Contacts',
                        color: AppColors.emergencyRed,
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => const EmergencyContactsSheet(),
                          );
                        },
                      ),
                      _buildQuickActionCard(
                        icon: Icons.local_hospital_rounded,
                        title: 'Edhi Centers',
                        subtitle: 'Published office contacts',
                        tag: 'Office directory',
                        color: const Color(0xFF0284C7),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const EdhiCentersScreen(),
                            ),
                          );
                        },
                      ),
                      _buildQuickActionCard(
                        icon: Icons.support_agent_rounded,
                        title: 'AI Assistant',
                        subtitle: 'Instant FAQ triage',
                        tag: 'NLP Bot',
                        color: const Color(0xFF7C3AED),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AIChatbotScreen(),
                            ),
                          );
                        },
                      ),
                      _buildQuickActionCard(
                        icon: Icons.family_restroom_rounded,
                        title: 'Missing Persons',
                        subtitle: 'Tracing & reuniting',
                        tag: 'Family Desk',
                        color: const Color(0xFFD97706),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const MissingPersonsScreen(),
                            ),
                          );
                        },
                      ),
                      _buildQuickActionCard(
                        icon: Icons.volunteer_activism_rounded,
                        title: 'Make Donation',
                        subtitle: 'Fuel & emergency aid',
                        tag: 'Support',
                        color: const Color(0xFF0D9488),
                        onTap: () => setState(() => _bottomNavIndex = 1),
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // Live Community Impact Ticker
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.reliefGreenSoft,
                          AppColors.background,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.reliefGreenMedium.withValues(
                          alpha: 0.2,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.reliefGreenMedium,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.health_and_safety_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Confirm your location before sending SOS',
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'For immediate assistance call Edhi 115. The app tracks your request after Operations assigns an ambulance.',
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
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Widget _buildFastDispatchChip(String label, IconData icon, Color color) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label),
      labelStyle: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      backgroundColor: Colors.white,
      side: BorderSide(color: color.withValues(alpha: 0.3)),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      onPressed: () => _triggerSosQuickSheet(context, label),
    );
  }

  Widget _buildQuickActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String tag,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border, width: 1.1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
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
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    tag,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Modal bottom sheet for quick emergency request submission (Matching SDD Screen 4)
class _QuickSosModalSheet extends StatefulWidget {
  final String? initialCategory;
  final RequestLocation? initialLocation;
  const _QuickSosModalSheet({this.initialCategory, this.initialLocation});

  @override
  State<_QuickSosModalSheet> createState() => _QuickSosModalSheetState();
}

class _QuickSosModalSheetState extends State<_QuickSosModalSheet> {
  late String _selectedCategory;
  final _descController = TextEditingController();
  final _addressController = TextEditingController();
  double _latitude = 0;
  double _longitude = 0;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory ?? EmergencyCategories.medical;
    final location = widget.initialLocation;
    if (location != null && location.hasValidCoordinates) {
      _latitude = location.latitude;
      _longitude = location.longitude;
      _addressController.text = location.address;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final pos = await LocationService.getCurrentLocation(
          allowFallback: false,
        );
        if (mounted) {
          setState(() {
            _latitude = pos.latitude;
            _longitude = pos.longitude;
            _addressController.text =
                '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
          });
          final addr = await LocationService.getAddressFromCoordinates(
            pos.latitude,
            pos.longitude,
          );
          if (mounted && addr.isNotEmpty) {
            setState(() {
              _addressController.text = addr;
            });
          }
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _descController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _submitEmergency() async {
    if (_isSubmitting) return;
    if (!RequestLocation(
      latitude: _latitude,
      longitude: _longitude,
    ).hasValidCoordinates) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Set the patient location using GPS or the map. Call 115 if you need immediate assistance.',
          ),
        ),
      );
      return;
    }
    setState(() => _isSubmitting = true);

    final auth = context.read<AuthService>();
    final firestore = context.read<FirestoreService>();
    final user = auth.currentUser;

    final request = EmergencyRequest(
      requestId: '',
      userId: user?.id ?? 'guest_user',
      userName: user?.name ?? 'Anonymous Citizen',
      userPhone: user?.phone ?? '03001234567',
      emergencyType: _selectedCategory,
      location: RequestLocation(
        latitude: _latitude,
        longitude: _longitude,
        address: _addressController.text.trim(),
      ),
      description: _descController.text.trim().isEmpty
          ? 'Urgent emergency assistance requested.'
          : _descController.text.trim(),
      status: EmergencyStatus.pending,
    );

    try {
      // Availability is only a hint; dispatch confirms its atomic reservation.
      final nearest = firestore.findNearestAvailableAmbulance(
        _latitude,
        _longitude,
      );

      final reqId = await firestore.submitEmergencyRequest(
        request,
        autoAssignNearest: nearest != null,
      );
      final queuedOffline = firestore.isRequestQueued(reqId);

      if (mounted) {
        setState(() => _isSubmitting = false);
        Navigator.pop(context);

        final msg = queuedOffline
            ? 'SOS #$reqId is queued in this session. Retry from your profile. If danger is immediate, call Edhi 115 now.'
            : 'Request #$reqId received. An available ambulance will be assigned automatically. Track its status under My Requests.';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.airport_shuttle_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    msg,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: queuedOffline
                ? const Color(0xFFD97706)
                : (nearest != null
                      ? AppColors.reliefGreenMedium
                      : AppColors.emergencyRed),
            duration: Duration(seconds: queuedOffline ? 8 : 4),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            action: queuedOffline
                ? SnackBarAction(
                    label: 'CALL 115',
                    textColor: Colors.white,
                    onPressed: LocationService.callEdhiHelpline,
                  )
                : null,
          ),
        );

        // Transition smoothly into live tracking screen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TrackRequestScreen(requestId: reqId),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        final errText = e.toString().toLowerCase();
        final displayMsg =
            (errText.contains('not-found') ||
                errText.contains('does not exist'))
            ? 'Cloud Firestore database is not created yet in Firebase Console. Please open your Firebase Console and create a Cloud Firestore Database.'
            : 'Submission failed: $e';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(displayMsg),
            backgroundColor: AppColors.emergencyRed,
            duration: const Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Request Emergency Help',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              'Select emergency category and verify location for rapid dispatch',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),

            // Categories Chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: EmergencyCategories.all.map((cat) {
                final isSelected = _selectedCategory == cat;
                return ChoiceChip(
                  label: Text(cat),
                  selected: isSelected,
                  selectedColor: AppColors.emergencyRed.withValues(alpha: 0.15),
                  labelStyle: GoogleFonts.inter(
                    color: isSelected
                        ? AppColors.emergencyRed
                        : AppColors.textPrimary,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 13,
                  ),
                  onSelected: (val) {
                    if (val) setState(() => _selectedCategory = cat);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Location Input with Map Picker & Live GPS Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      minimumSize: Size.zero,
                      side: const BorderSide(
                        color: AppColors.reliefGreenMedium,
                      ),
                    ),
                    icon: const Icon(
                      Icons.map_rounded,
                      size: 16,
                      color: AppColors.reliefGreenMedium,
                    ),
                    label: Text(
                      'Pinpoint on Map',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.reliefGreenMedium,
                      ),
                    ),
                    onPressed: () async {
                      final picked =
                          await showModalBottomSheet<RequestLocation>(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => LocationPickerSheet(
                              initialLocation: RequestLocation(
                                latitude: _latitude,
                                longitude: _longitude,
                                address: _addressController.text,
                              ),
                            ),
                          );
                      if (picked != null) {
                        setState(() {
                          _latitude = picked.latitude;
                          _longitude = picked.longitude;
                          _addressController.text = picked.address;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      minimumSize: Size.zero,
                      side: const BorderSide(color: AppColors.emergencyRed),
                    ),
                    icon: const Icon(
                      Icons.gps_fixed_rounded,
                      size: 16,
                      color: AppColors.emergencyRed,
                    ),
                    label: Text(
                      'Detect GPS',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.emergencyRed,
                      ),
                    ),
                    onPressed: () async {
                      setState(() {
                        _addressController.text = 'Locating via GPS...';
                      });
                      try {
                        final pos = await LocationService.getCurrentLocation(
                          allowFallback: false,
                        );
                        if (!mounted) return;
                        setState(() {
                          _latitude = pos.latitude;
                          _longitude = pos.longitude;
                          _addressController.text =
                              '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
                        });
                        final place =
                            await LocationService.getAddressFromCoordinates(
                              pos.latitude,
                              pos.longitude,
                            );
                        if (mounted) {
                          setState(() => _addressController.text = place);
                        }
                      } catch (_) {
                        if (!mounted || !context.mounted) return;
                        setState(() => _addressController.text = '');
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'GPS unavailable. Enable location permission or select the patient pin on the map.',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            CustomTextField(
              label: 'Current Location',
              hint: 'Address or landmark',
              controller: _addressController,
              prefixIcon: Icons.my_location_rounded,
            ),
            const SizedBox(height: 14),

            CustomTextField(
              label: 'Emergency Situation / Details',
              hint: 'Describe what happened (injuries, fire, etc.)',
              controller: _descController,
              maxLines: 2,
              prefixIcon: Icons.description_outlined,
            ),
            Builder(
              builder: (ctx) {
                final firestore = ctx.watch<FirestoreService>();
                final nearest = firestore.findNearestAvailableAmbulance(
                  _latitude,
                  _longitude,
                );

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (nearest != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFBBF7D0)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.flash_on_rounded,
                              color: AppColors.reliefGreenMedium,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'Nearest Standby Unit:',
                                        style: GoogleFonts.inter(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.reliefGreenMedium,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${nearest.distanceKm.toStringAsFixed(1)} km away • ETA ~${nearest.etaMinutes}m',
                                        style: GoogleFonts.inter(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    '${nearest.employee.name} (${nearest.employee.vehicleNumber})',
                                    style: GoogleFonts.outfit(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.amber.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 16,
                              color: Colors.amber.shade900,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'No available ambulance nearby. Confirm the patient pin and submit to Operations. For urgent help, call Edhi 115.',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    CustomButton(
                      text: nearest != null && !firestore.isLiveFirebase
                          ? 'Dispatch Nearest Unit (${nearest.employee.vehicleNumber}) ⚡'
                          : 'Send emergency request',
                      isLoading: _isSubmitting,
                      onPressed: _submitEmergency,
                      backgroundColor: AppColors.emergencyRed,
                      icon: Icons.emergency_rounded,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
