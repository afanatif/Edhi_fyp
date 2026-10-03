import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/widgets/responsive_shell.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../services/auth_service.dart';
import '../../../services/firestore_service.dart';
import '../../../models/employee.dart';
import '../../../models/emergency_request.dart';
import '../assigned_requests/driver_mission_screen.dart';

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              completedNow
                  ? 'Job completed. Ambulance is available; all panels update automatically.'
                  : 'The response was already completed.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not complete: $error')));
      }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update availability. Please retry.'),
          ),
        );
      }
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
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Your driver account is registered and awaiting an ambulance. Admin can open HQ → Fleet → Registered drivers → Assign ambulance, then select an existing ambulance or create one. Your dashboard will update when the assignment is saved.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (_jobsEmployeeId != driver.employeeId) {
            _jobsEmployeeId = driver.employeeId;
            _jobs = service.getAssignedRequestsStream(driver.employeeId);
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        driver.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Ambulance ${driver.vehicleNumber.isEmpty ? 'not assigned' : driver.vehicleNumber}',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        FirestoreService.simulatedFleetEnabled
                            ? 'Road movement and arrival update automatically. You or the citizen can confirm completion after assistance is finished.'
                            : driver.status == 'offline'
                            ? 'GPS sharing paused while off duty.'
                            : service.driverLocationError(driver.employeeId) ??
                                  (driver.hasFreshGps(DateTime.now())
                                      ? 'Live GPS connected • updates while you are on duty.'
                                      : 'Waiting for a fresh GPS fix. Keep this app open and enable location.'),
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (service.driverLocationError(driver.employeeId) !=
                          null)
                        TextButton.icon(
                          onPressed: () {
                            service.stopLiveDriverLocation(driver.employeeId);
                            service.startLiveDriverLocation(driver.employeeId);
                          },
                          icon: const Icon(Icons.gps_fixed),
                          label: const Text('Retry GPS'),
                        ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          driver.status == 'busy'
                              ? 'Responding to an emergency'
                              : 'Available for dispatch',
                        ),
                        subtitle: Text(
                          driver.status == 'busy'
                              ? 'Finish your assigned response before changing availability.'
                              : 'Turn off when you are off duty.',
                        ),
                        value: driver.status != 'offline',
                        onChanged: _saving || driver.status == 'busy'
                            ? null
                            : (v) => _availability(driver, v),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Assigned jobs',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              StreamBuilder<List<EmergencyRequest>>(
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
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No active assignments. New jobs appear when dispatch assigns your ambulance.',
                        ),
                      ),
                    );
                  }
                  return Column(
                    children: requests
                        .map(
                          (request) => Card(
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
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(request.location.address),
                                  const SizedBox(height: 8),
                                  Text(
                                    request.description,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 12),
                                  if (request.status == 'Arrived') ...[
                                    FilledButton.icon(
                                      icon: const Icon(Icons.task_alt),
                                      label: const Text(
                                        'Did my job · Complete response',
                                      ),
                                      onPressed: _saving
                                          ? null
                                          : () => _complete(request),
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
                                  FilledButton.icon(
                                    icon: const Icon(Icons.arrow_forward),
                                    label: const Text('Open job'),
                                    onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => DriverMissionScreen(
                                          requestId: request.requestId,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
