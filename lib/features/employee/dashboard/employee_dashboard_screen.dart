import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/responsive_shell.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../models/dispatch_offer.dart';
import '../../../services/auth_service.dart';
import '../../../services/firestore_service.dart';
import '../../../models/employee.dart';
import '../../../models/emergency_request.dart';
import '../assigned_requests/driver_mission_screen.dart';
import 'incoming_offer_card.dart';

class EmployeeDashboardScreen extends StatefulWidget {
  const EmployeeDashboardScreen({super.key});
  @override
  State<EmployeeDashboardScreen> createState() =>
      _EmployeeDashboardScreenState();
}

class _EmployeeDashboardScreenState extends State<EmployeeDashboardScreen> {
  bool _saving = false;
  FirestoreService? _service;
  Stream<List<Employee>>? _employees;
  Stream<List<EmergencyRequest>>? _jobs;
  String? _jobsEmployeeId;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = context.read<FirestoreService>();
    if (_service != service) {
      _service = service;
      _employees = service.getEmployeesStream();
      _jobsEmployeeId = null;
    }
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? AppColors.emergencyRedDark : null,
        content: Text(message),
      ),
    );
  }

  Future<void> _accept(DispatchOffer offer) async {
    try {
      await _service!.acceptDispatchOffer(offer.offerId);
      _toast('Accepted. Drive safely — the patient can see you are coming.');
    } catch (error) {
      _toast(
        'Could not accept: ${error.toString().replaceFirst('Bad state: ', '')}',
        error: true,
      );
    }
  }

  Future<void> _decline(DispatchOffer offer) async {
    try {
      await _service!.declineDispatchOffer(offer.offerId);
      _toast('Passed to the next-nearest ambulance. No penalty recorded.');
    } catch (error) {
      _toast(
        'Could not decline: ${error.toString().replaceFirst('Bad state: ', '')}',
        error: true,
      );
    }
  }

  Future<void> _complete(EmergencyRequest request) async {
    if (_saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Did my job — complete response?'),
        content: const Text(
          'Confirm patient assistance is finished. This closes the job for the citizen and admin, and makes your ambulance available again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Complete response'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final completedNow = await _service!.completeDriverResponse(
        request.requestId,
        context.read<AuthService>().currentUser!.id,
      );
      _toast(
        completedNow
            ? 'Job completed. Ambulance is available; all panels update automatically.'
            : 'The response was already completed.',
      );
    } catch (error) {
      _toast('Could not complete: $error', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _availability(Employee driver, bool available) async {
    setState(() => _saving = true);
    try {
      await context.read<FirestoreService>().toggleDriverAvailability(
        driver.employeeId,
        available,
      );
    } catch (_) {
      _toast('Could not update availability. Please retry.', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final service = context.watch<FirestoreService>();
    return ResponsiveShell(
      appBar: AppBar(
        title: const Text('Driver dashboard'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => auth.signOut(),
          ),
        ],
      ),
      child: StreamBuilder<List<Employee>>(
        stream: _employees,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'Unable to load driver details. Please check your connection.',
              ),
            );
          }
          if (!snapshot.hasData &&
              snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final driver = (snapshot.data ?? [])
              .where((e) => e.userId == auth.currentUser?.id)
              .firstOrNull;
          if (driver == null) {
            return const _EmptyState(
              icon: Icons.airport_shuttle_outlined,
              title: 'Waiting for an ambulance',
              message:
                  'Your driver account is registered and awaiting an ambulance. Admin can open HQ → Fleet → Registered drivers → Assign ambulance, then select an existing ambulance or create one. Your dashboard will update when the assignment is saved.',
            );
          }
          if (_jobsEmployeeId != driver.employeeId) {
            _jobsEmployeeId = driver.employeeId;
            _jobs = service.getAssignedRequestsStream(driver.employeeId);
          }
          final offer = service.pendingOfferForDriver(driver.userId);
          final record = service
              .driverAccountability()
              .where((r) => r.unit.employeeId == driver.employeeId)
              .firstOrNull;
          // A Column (not a lazy ListView) keeps the jobs StreamBuilder alive
          // when the offer card or response record appears above it.
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  transitionBuilder: (child, animation) => SizeTransition(
                    sizeFactor: animation,
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: offer == null
                      ? const SizedBox.shrink()
                      : Padding(
                          key: ValueKey(offer.offerId),
                          padding: const EdgeInsets.only(bottom: 16),
                          child: IncomingOfferCard(
                            offer: offer,
                            onAccept: () => _accept(offer),
                            onDecline: () => _decline(offer),
                            clock: () => service.clockNow,
                          ),
                        ),
                ),
                if (driver.isAutoOffline)
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.statusPendingBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.statusPending),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.bedtime_rounded,
                              color: AppColors.statusPending,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'You were taken off duty',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'You missed ${DispatchOffer.autoOfflineAfterMisses} emergencies in a row, so new patients are going to other ambulances. Switch back on when you can answer within 60 seconds.',
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          key: const Key('backOnDuty'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.reliefGreen,
                            minimumSize: const Size.fromHeight(46),
                          ),
                          onPressed: _saving
                              ? null
                              : () => _availability(driver, true),
                          icon: const Icon(Icons.power_settings_new),
                          label: const Text("I'm back · put me on duty"),
                        ),
                      ],
                    ),
                  ),
                _DriverHeader(
                  driver: driver,
                  saving: _saving,
                  gpsNote: FirestoreService.simulatedFleetEnabled
                      ? 'Road movement and arrival update automatically. Keep this app open so you hear new emergencies.'
                      : driver.status == 'offline'
                      ? 'GPS sharing paused while off duty.'
                      : service.driverLocationError(driver.employeeId) ??
                            (driver.hasFreshGps(DateTime.now())
                                ? 'Live GPS connected • updates while you are on duty.'
                                : 'Waiting for a fresh GPS fix. Keep this app open and enable location.'),
                  gpsError:
                      service.driverLocationError(driver.employeeId) != null,
                  onRetryGps: () {
                    service.stopLiveDriverLocation(driver.employeeId);
                    service.startLiveDriverLocation(driver.employeeId);
                  },
                  onAvailability: (v) => _availability(driver, v),
                ),
                if (record != null && record.offers > 0) ...[
                  const SizedBox(height: 14),
                  _ResponseRecord(record: record),
                ],
                const SizedBox(height: 22),
                Text(
                  'Assigned jobs',
                  style: GoogleFonts.outfit(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                StreamBuilder<List<EmergencyRequest>>(
                  key: const ValueKey('driver-jobs'),
                  stream: _jobs,
                  builder: (context, jobs) {
                    if (jobs.hasError) {
                      return const Text('Unable to load jobs. Please retry.');
                    }
                    if (!jobs.hasData &&
                        jobs.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final requests = jobs.data ?? [];
                    if (requests.isEmpty) {
                      return _EmptyState(
                        icon: Icons.verified_user_outlined,
                        title: 'No active assignments',
                        message: driver.status == 'offline'
                            ? 'You are off duty. Switch on "Available for dispatch" to receive emergencies.'
                            : 'You are on standby. New emergencies ring here with 60 seconds to accept.',
                        compact: true,
                      );
                    }
                    return Column(
                      children: requests
                          .map(
                            (request) => _JobCard(
                              request: request,
                              saving: _saving,
                              onComplete: () => _complete(request),
                              onOpen: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DriverMissionScreen(
                                    requestId: request.requestId,
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DriverHeader extends StatelessWidget {
  final Employee driver;
  final bool saving;
  final String gpsNote;
  final bool gpsError;
  final VoidCallback onRetryGps;
  final ValueChanged<bool> onAvailability;
  const _DriverHeader({
    required this.driver,
    required this.saving,
    required this.gpsNote,
    required this.gpsError,
    required this.onRetryGps,
    required this.onAvailability,
  });

  @override
  Widget build(BuildContext context) {
    final busy = driver.status == 'busy';
    final online = driver.status != 'offline';
    final (Color tone, String label, IconData icon) = busy
        ? (AppColors.statusInProgress, 'On a mission', Icons.local_shipping)
        : online
        ? (AppColors.reliefGreen, 'On duty · ready', Icons.wifi_tethering)
        : (AppColors.statusCancelled, 'Off duty', Icons.bedtime_outlined);
    return Material(
      color: Colors.white,
      elevation: 3,
      shadowColor: const Color(0x330F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: tone.withValues(alpha: 0.12),
                  child: Icon(icon, color: tone, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        driver.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Ambulance ${driver.vehicleNumber.isEmpty ? 'not assigned' : driver.vehicleNumber}',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: tone,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: tone,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(gpsNote, style: const TextStyle(fontSize: 12)),
            if (gpsError)
              TextButton.icon(
                onPressed: onRetryGps,
                icon: const Icon(Icons.gps_fixed),
                label: const Text('Retry GPS'),
              ),
            const Divider(height: 22),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              activeTrackColor: AppColors.reliefGreenMedium,
              title: Text(
                busy ? 'Responding to an emergency' : 'Available for dispatch',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                busy
                    ? 'Finish your assigned response before changing availability.'
                    : 'Turn off when you are off duty, so emergencies are not offered to you.',
              ),
              value: online,
              onChanged: saving || busy ? null : onAvailability,
            ),
          ],
        ),
      ),
    );
  }
}

class _ResponseRecord extends StatelessWidget {
  final DriverAccountability record;
  const _ResponseRecord({required this.record});

  @override
  Widget build(BuildContext context) {
    final avg = record.avgResponseSeconds;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: record.missed > 0
            ? AppColors.statusPendingBg
            : AppColors.reliefGreenSoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your response record',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 18,
            runSpacing: 10,
            children: [
              _Stat('${record.accepted}', 'Accepted', AppColors.reliefGreen),
              _Stat('${record.declined}', 'Declined', AppColors.statusApproved),
              _Stat(
                '${record.missed}',
                'Missed (penalty)',
                AppColors.emergencyRed,
              ),
              _Stat(
                avg == null ? '—' : '${avg.round()} s',
                'Avg answer',
                AppColors.textPrimary,
              ),
            ],
          ),
          if (record.missed > 0) ...[
            const SizedBox(height: 10),
            const Text(
              'Missed calls are shown to HQ. Keep this app open and your volume up while on duty.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _Stat(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        value,
        style: GoogleFonts.outfit(
          fontSize: 22,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
      Text(
        label,
        style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
      ),
    ],
  );
}

class _JobCard extends StatelessWidget {
  final EmergencyRequest request;
  final bool saving;
  final VoidCallback onComplete;
  final VoidCallback onOpen;
  const _JobCard({
    required this.request,
    required this.saving,
    required this.onComplete,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: AppColors.border),
    ),
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              StatusBadge(status: request.status),
              PriorityBadge(priority: request.priority),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            request.emergencyType,
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.place_outlined,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Expanded(child: Text(request.location.address)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            request.description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          if (request.status == 'Arrived') ...[
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.reliefGreen,
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.task_alt),
              label: const Text('Did my job · Complete response'),
              onPressed: saving ? null : onComplete,
            ),
            const SizedBox(height: 8),
          ] else if (request.status == 'InProgress' ||
              request.status == 'Assigned') ...[
            const Text(
              'Road travel and arrival update automatically. You can complete this job after arrival.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
            ),
            icon: const Icon(Icons.map_outlined),
            label: const Text('Open job · map & route'),
            onPressed: onOpen,
          ),
        ],
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final bool compact;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: compact ? 40 : 56, color: AppColors.textMuted),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(message, textAlign: TextAlign.center),
      ],
    );
    return compact
        ? Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: body,
          )
        : Center(
            child: Padding(padding: const EdgeInsets.all(24), child: body),
          );
  }
}
