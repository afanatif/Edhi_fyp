import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../data/simulated_fleet.dart';
import '../../models/employee.dart';
import '../../models/edhi_center.dart';
import '../../models/app_user.dart';
import '../../services/firestore_service.dart';
import 'map_location_picker.dart';

Future<void> showLinkDriverDialog(BuildContext context, Employee employee) =>
    showDialog<void>(
      context: context,
      builder: (_) => _LinkDriverDialog(employee: employee),
    );

class _LinkDriverDialog extends StatefulWidget {
  final Employee employee;
  const _LinkDriverDialog({required this.employee});
  @override
  State<_LinkDriverDialog> createState() => _LinkDriverDialogState();
}

class _LinkDriverDialogState extends State<_LinkDriverDialog> {
  late final Stream<List<AppUser>> _users;
  late String _uid;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _uid = widget.employee.userId;
    _users = context.read<FirestoreService>().getUsersStream();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<FirestoreService>().linkDriverAccount(
        widget.employee.employeeId,
        _uid,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Link registered driver'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Ambulance ${widget.employee.vehicleNumber}. A linked driver can view and complete its jobs. Admin manages its starting position.',
            ),
            const SizedBox(height: 16),
            StreamBuilder<List<AppUser>>(
              stream: _users,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text(
                    'Unable to load registered drivers. Check admin access and connection.',
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final drivers = snapshot.data!
                    .where((u) => u.isEmployee && u.isActive)
                    .toList();
                final selectedExists =
                    _uid.isEmpty || drivers.any((u) => u.id == _uid);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedExists ? _uid : '',
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Registered driver account',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('No driver account linked'),
                        ),
                        ...drivers.map(
                          (u) => DropdownMenuItem(
                            value: u.id,
                            child: Text(
                              '${u.name} · ${u.phone}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _uid = v ?? ''),
                    ),
                    if (drivers.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'No active driver accounts yet. Register using the Driver option on signup.',
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            const Text(
              'One account per ambulance. Busy units cannot be relinked; complete the response first.',
              style: TextStyle(fontSize: 12),
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
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
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Save link'),
      ),
    ],
  );
}

Future<List<Employee>?> showSimulatedFleetDialog(
  BuildContext context, {
  required LatLng stagingPoint,
  AppUser? registeredDriver,
}) => showDialog<List<Employee>>(
  context: context,
  builder: (_) => _SimulatedFleetDialog(
    stagingPoint: stagingPoint,
    registeredDriver: registeredDriver,
  ),
);

class _SimulatedFleetDialog extends StatefulWidget {
  final LatLng stagingPoint;
  final AppUser? registeredDriver;
  const _SimulatedFleetDialog({
    required this.stagingPoint,
    this.registeredDriver,
  });
  @override
  State<_SimulatedFleetDialog> createState() => _SimulatedFleetDialogState();
}

class _SimulatedFleetDialogState extends State<_SimulatedFleetDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _plate = TextEditingController();
  final _phone = TextEditingController();
  late LatLng _mapCenter;
  LatLng? _parkingPoint;
  bool _random = false;
  bool _saving = false;
  bool _available = true;
  int _count = 3;
  String _centerId = '';
  String? _error;
  AppUser? _registeredDriver;
  late final Stream<List<AppUser>> _users;
  @override
  void initState() {
    super.initState();
    _users = context.read<FirestoreService>().getUsersStream();
    _registeredDriver = widget.registeredDriver;
    _setPosition(widget.stagingPoint);
    _name.text = widget.registeredDriver?.name ?? '';
    _phone.text = widget.registeredDriver?.phone ?? '';
  }

  void _setPosition(LatLng position) {
    _mapCenter = position;
    _parkingPoint = null;
  }

  @override
  void dispose() {
    for (final controller in [_name, _plate, _phone]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickParkingPoint() async {
    final point = await showParkingLocationPicker(
      context,
      mapCenter: _mapCenter,
      selectedPoint: _parkingPoint,
    );
    if (point != null && mounted) {
      setState(() {
        _parkingPoint = point;
        _error = null;
      });
    }
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final service = context.read<FirestoreService>();
      final position = _parkingPoint;
      if (position == null) {
        throw StateError('Choose a parking spot on the map before saving.');
      }
      List<Employee> added;
      if (_random) {
        added = await service.generateRandomDrivers(
          count: _count,
          stagingPoint: position,
          centerId: _centerId.isEmpty ? null : _centerId,
        );
      } else {
        final parked = await service.prepareSimulatedParkingPoint(position);
        final employee = Employee(
          employeeId: '',
          userId: _registeredDriver?.id ?? '',
          name: _name.text.trim(),
          phone: _phone.text.trim(),
          vehicleNumber: _plate.text.trim(),
          assignedCenterId: _centerId.isEmpty ? null : _centerId,
          currentLat: parked.latitude,
          currentLng: parked.longitude,
          status: _available ? 'available' : 'offline',
          isSimulated: true,
        );
        final id = await service.addEmployee(employee);
        added = [employee.copyWith(employeeId: id)];
      }
      if (mounted) Navigator.pop(context, added);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.read<FirestoreService>();
    final centers = service.getEdhiCenters();
    return AlertDialog(
      title: Text(
        _registeredDriver == null
            ? 'Add ambulances'
            : 'Add and assign ambulance',
      ),
      content: SizedBox(
        width: 520,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .65,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _registeredDriver == null
                        ? 'Add an ambulance with its vehicle number and parking position. You can link a registered driver from Fleet.'
                        : '${_registeredDriver!.name} will be linked to this ambulance. Enter its vehicle number and parking position.',
                  ),
                  const SizedBox(height: 12),
                  if (widget.registeredDriver == null)
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        ChoiceChip(
                          label: const Text('Enter manually'),
                          selected: !_random,
                          onSelected: _saving
                              ? null
                              : (_) => setState(() => _random = false),
                        ),
                        ChoiceChip(
                          label: const Text('Generate random drivers'),
                          selected: _random,
                          onSelected: _saving
                              ? null
                              : (_) => setState(() {
                                  _random = true;
                                  _registeredDriver = null;
                                }),
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  if (!_random && widget.registeredDriver == null) ...[
                    StreamBuilder<List<AppUser>>(
                      stream: _users,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const Text(
                            'Unable to load registered drivers. Check your connection.',
                          );
                        }
                        if (!snapshot.hasData) {
                          return const LinearProgressIndicator();
                        }
                        final drivers = snapshot.data!
                            .where(
                              (u) =>
                                  u.isEmployee &&
                                  u.isActive &&
                                  !service.getAllEmployees().any(
                                    (e) => e.userId == u.id,
                                  ),
                            )
                            .toList();
                        final selected =
                            drivers.any((u) => u.id == _registeredDriver?.id)
                            ? _registeredDriver?.id
                            : '';
                        return DropdownButtonFormField<String>(
                          key: ValueKey('registered-driver:$selected'),
                          initialValue: selected,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Assign registered driver (optional)',
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('Assign a driver later'),
                            ),
                            ...drivers.map(
                              (u) => DropdownMenuItem(
                                value: u.id,
                                child: Text(
                                  '${u.name} · ${u.phone}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: _saving
                              ? null
                              : (value) => setState(() {
                                  _registeredDriver = drivers
                                      .where((u) => u.id == value)
                                      .firstOrNull;
                                  _name.text = _registeredDriver?.name ?? '';
                                  _phone.text = _registeredDriver?.phone ?? '';
                                }),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  DropdownButtonFormField<String>(
                    initialValue: _centerId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Center / staging area',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Choose parking spot on map'),
                      ),
                      ...centers.map(
                        (c) => DropdownMenuItem(
                          value: c.centerId,
                          child: Text(
                            '${c.city} · ${c.name}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() {
                            _centerId = value ?? '';
                            final EdhiCenter? center = centers
                                .where((c) => c.centerId == _centerId)
                                .firstOrNull;
                            _setPosition(
                              SimulatedFleet.stagingPoint(
                                center,
                                widget.stagingPoint,
                              ),
                            );
                          }),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'The center opens the map near its city. Drop a pin at the ambulance’s parking spot; it will be aligned to the nearest drivable road.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  if (_random)
                    DropdownButtonFormField<int>(
                      initialValue: _count,
                      decoration: const InputDecoration(
                        labelText: 'Number of parked units',
                      ),
                      items: [1, 3, 5, 10]
                          .map(
                            (n) => DropdownMenuItem(
                              value: n,
                              child: Text('$n units'),
                            ),
                          )
                          .toList(),
                      onChanged: _saving
                          ? null
                          : (n) => setState(() => _count = n!),
                    )
                  else ...[
                    TextFormField(
                      controller: _name,
                      enabled: !_saving,
                      readOnly: _registeredDriver != null,
                      decoration: const InputDecoration(
                        labelText: 'Driver display name',
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Enter a name' : null,
                    ),
                    TextFormField(
                      controller: _plate,
                      enabled: !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Unique vehicle number',
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Enter a vehicle number'
                          : null,
                    ),
                    TextFormField(
                      controller: _phone,
                      enabled: !_saving,
                      readOnly: _registeredDriver != null,
                      decoration: InputDecoration(
                        labelText: _registeredDriver == null
                            ? 'Phone (optional)'
                            : 'Registered phone',
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Available for dispatch'),
                      value: _available,
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _available = v),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Text(
                    'Parking location',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _parkingPoint == null
                        ? 'Choose the location by dropping a pin on the map.'
                        : 'Parking spot selected on the map.',
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _pickParkingPoint,
                    icon: Icon(
                      _parkingPoint == null
                          ? Icons.map_outlined
                          : Icons.edit_location_alt,
                    ),
                    label: Text(
                      _parkingPoint == null
                          ? 'Choose on map'
                          : 'Change map pin',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Road routing needs internet. If positioning fails, no units are added. You can edit generated drivers and vehicle numbers.',
                    style: TextStyle(fontSize: 12),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!.replaceFirst('Bad state: ', ''),
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(
            _saving
                ? 'Preparing road positions…'
                : _random
                ? 'Generate fleet'
                : _registeredDriver == null
                ? 'Add ambulance'
                : 'Add and assign',
          ),
        ),
      ],
    );
  }
}
