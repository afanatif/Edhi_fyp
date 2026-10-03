import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/simulated_fleet_dialog.dart';
import '../../../models/app_user.dart';
import '../../../models/employee.dart';
import '../../../services/firestore_service.dart';

/// Driver accounts exist before their operational ambulance assignment.
class RegisteredDriversPanel extends StatefulWidget {
  final List<Employee> ambulances;
  final LatLng stagingPoint;
  final String searchQuery;

  const RegisteredDriversPanel({
    super.key,
    required this.ambulances,
    required this.stagingPoint,
    this.searchQuery = '',
  });

  @override
  State<RegisteredDriversPanel> createState() => _RegisteredDriversPanelState();
}

class _RegisteredDriversPanelState extends State<RegisteredDriversPanel> {
  late final Stream<List<AppUser>> _users;

  @override
  void initState() {
    super.initState();
    _users = context.read<FirestoreService>().getUsersStream();
  }

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border),
    ),
    child: StreamBuilder<List<AppUser>>(
      stream: _users,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text(
            'Unable to load registered drivers. Check your connection and admin access.',
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final drivers = snapshot.data!.where((u) => u.isEmployee).toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
        final byDriver = {
          for (final unit in widget.ambulances)
            if (unit.userId.isNotEmpty) unit.userId: unit,
        };
        final waiting = drivers
            .where((u) => u.isActive && !byDriver.containsKey(u.id))
            .length;
        final query = widget.searchQuery.trim().toLowerCase();
        final filtered = drivers.where(
          (u) =>
              query.isEmpty ||
              u.name.toLowerCase().contains(query) ||
              u.phone.contains(query) ||
              u.cnic.contains(query),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Registered drivers (${drivers.length})',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '$waiting awaiting an ambulance. Assign an existing unit or add a new one.',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            if (drivers.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Driver accounts appear here as soon as they register.',
                ),
              )
            else if (filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('No registered drivers match your search.'),
              ),
            for (final driver in filtered) ...[
              const Divider(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final unit = byDriver[driver.id];
                  final details = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        driver.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (driver.phone.isNotEmpty) Text(driver.phone),
                      Text(
                        !driver.isActive
                            ? 'Account suspended'
                            : unit == null
                            ? 'Awaiting ambulance assignment'
                            : 'Assigned to ${unit.vehicleNumber}',
                        style: TextStyle(
                          color: unit == null
                              ? AppColors.statusPending
                              : AppColors.reliefGreen,
                        ),
                      ),
                    ],
                  );
                  final action = FilledButton.icon(
                    onPressed: driver.isActive && unit == null
                        ? () => showAssignRegisteredDriverDialog(
                            context,
                            driver: driver,
                            stagingPoint: widget.stagingPoint,
                          )
                        : null,
                    icon: const Icon(Icons.link),
                    label: const Text('Assign ambulance'),
                  );
                  if (constraints.maxWidth < 520) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        details,
                        if (unit == null) ...[
                          const SizedBox(height: 10),
                          action,
                        ],
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: details),
                      if (unit == null) action,
                    ],
                  );
                },
              ),
            ],
          ],
        );
      },
    ),
  );
}

Future<void> showAssignRegisteredDriverDialog(
  BuildContext context, {
  required AppUser driver,
  required LatLng stagingPoint,
}) => showDialog<void>(
  context: context,
  builder: (_) =>
      _AssignRegisteredDriverDialog(driver: driver, stagingPoint: stagingPoint),
);

class _AssignRegisteredDriverDialog extends StatefulWidget {
  final AppUser driver;
  final LatLng stagingPoint;
  const _AssignRegisteredDriverDialog({
    required this.driver,
    required this.stagingPoint,
  });

  @override
  State<_AssignRegisteredDriverDialog> createState() =>
      _AssignRegisteredDriverDialogState();
}

class _AssignRegisteredDriverDialogState
    extends State<_AssignRegisteredDriverDialog> {
  late final Stream<List<Employee>> _units;
  String? _employeeId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _units = context.read<FirestoreService>().getEmployeesStream();
  }

  Future<void> _save() async {
    if (_saving || _employeeId == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<FirestoreService>().linkDriverAccount(
        _employeeId!,
        widget.driver.id,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _add() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final units = await showSimulatedFleetDialog(
        context,
        stagingPoint: widget.stagingPoint,
        registeredDriver: widget.driver,
      );
      if (units != null && units.isNotEmpty && mounted) {
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Employee>>(
    stream: _units,
    builder: (context, snapshot) {
      final units = (snapshot.data ?? [])
          .where(
            (u) => u.role == 'driver' && u.status != 'busy' && u.userId.isEmpty,
          )
          .toList();
      final validSelection = units.any((u) => u.employeeId == _employeeId);
      return AlertDialog(
        title: const Text('Assign ambulance'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.driver.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(widget.driver.phone),
                const SizedBox(height: 16),
                if (snapshot.hasError)
                  const Text(
                    'Unable to load ambulances. Check your connection.',
                  )
                else if (!snapshot.hasData)
                  const Center(child: CircularProgressIndicator())
                else if (units.isEmpty)
                  const Text(
                    'No unassigned ambulances are available. Add an ambulance below to link this driver.',
                  )
                else
                  DropdownButtonFormField<String>(
                    key: ValueKey(
                      '${units.map((u) => u.employeeId).join(',')}:$_employeeId',
                    ),
                    initialValue: validSelection ? _employeeId : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Unassigned ambulance',
                    ),
                    items: units
                        .map(
                          (u) => DropdownMenuItem(
                            value: u.employeeId,
                            child: Text(
                              '${u.vehicleNumber} · ${u.status}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _employeeId = value),
                  ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _add,
                  icon: const Icon(Icons.add),
                  label: const Text('Create ambulance and assign driver'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Each driver can have one ambulance. Units on a mission or already linked to a driver cannot be selected here.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppColors.emergencyRed),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _saving || !validSelection ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save assignment'),
          ),
        ],
      );
    },
  );
}
