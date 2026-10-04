import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../services/auth_service.dart';
import '../../../services/firestore_service.dart';
import '../../../models/app_user.dart';
import '../../../models/emergency_usage.dart';
import 'admin_user_dialogs.dart';

class AdminUsersView extends StatefulWidget {
  const AdminUsersView({super.key});
  @override
  State<AdminUsersView> createState() => _AdminUsersViewState();
}

class _AdminUsersViewState extends State<AdminUsersView> {
  String _role = 'All', _search = '';
  final Set<String> _busy = {};
  late final Stream<List<AppUser>> _users;
  late final Stream<Map<String, EmergencyUsage>> _usage;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    final service = context.read<FirestoreService>();
    _users = service.getUsersStream();
    _usage = service.watchAllEmergencyUsage();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _action(AppUser user, Future<void> Function() perform) async {
    if (_busy.contains(user.id)) return;
    setState(() => _busy.add(user.id));
    try {
      await perform();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(user.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<FirestoreService>();
    final selfId = context.read<AuthService>().currentUser?.id;
    return StreamBuilder<List<AppUser>>(
      stream: _users,
      builder: (context, usersSnapshot) => StreamBuilder<Map<String, EmergencyUsage>>(
        stream: _usage,
        builder: (context, usageSnapshot) {
          if (usersSnapshot.hasError || usageSnapshot.hasError) {
            return const Text(
              'Unable to load user management. Check your connection and administrator access.',
            );
          }
          if (!usersSnapshot.hasData || !usageSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final users = usersSnapshot.data!;
          final usage = usageSnapshot.data!;
          final now = DateTime.now();
          final filtered = users.where((user) {
            final query = _search.trim().toLowerCase();
            final matches =
                query.isEmpty ||
                [
                  user.name,
                  user.email,
                  user.phone,
                  user.cnic,
                  AppUser.cleanCnic(user.cnic),
                ].any((v) => v.toLowerCase().contains(query));
            final matchesRole = switch (_role) {
              'Citizens' => user.isUser,
              'Drivers' => user.isEmployee,
              'Admins' => user.isAdmin,
              'Flagged' => (usage[user.id]?.cancellationCount ?? 0) >= 3,
              'Banned' => usage[user.id]?.isBanned(now) ?? false,
              _ => true,
            };
            return matches && matchesRole;
          }).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'User management',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  FilledButton.icon(
                    onPressed: () => showAdminUserDialog(context),
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Add user'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  Text('${users.length} users'),
                  Text('${users.where((u) => u.isUser).length} citizens'),
                  Text(
                    '${users.where((u) => (usage[u.id]?.cancellationCount ?? 0) >= 3).length} flagged',
                  ),
                  Text(
                    '${users.where((u) => usage[u.id]?.isBanned(now) ?? false).length} banned',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                onChanged: (value) => setState(() => _search = value),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search by name, CNIC, email or phone',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    [
                          'All',
                          'Citizens',
                          'Drivers',
                          'Admins',
                          'Flagged',
                          'Banned',
                        ]
                        .map(
                          (role) => ChoiceChip(
                            label: Text(role),
                            selected: _role == role,
                            onSelected: (selected) {
                              if (selected) setState(() => _role = role);
                            },
                          ),
                        )
                        .toList(),
              ),
              const SizedBox(height: 10),
              const Text(
                'Yellow rows mark three or more cancellations. Admin bans last until unbanned; account activation is separate.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 16),
              if (filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No matching users.'),
                ),
              for (final user in filtered) ...[
                _card(
                  user,
                  usage[user.id] ?? const EmergencyUsage(),
                  service,
                  selfId,
                ),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _card(
    AppUser user,
    EmergencyUsage usage,
    FirestoreService service,
    String? selfId,
  ) {
    final flagged = usage.cancellationCount >= 3;
    final banned = usage.isBanned(DateTime.now());
    final busy = _busy.contains(user.id);
    final self = selfId == user.id;
    final unit = service
        .getAllEmployees()
        .where((e) => e.userId == user.id || e.employeeId == user.id)
        .firstOrNull;
    final color = user.isAdmin
        ? Colors.purple
        : user.isEmployee
        ? AppColors.emergencyRed
        : AppColors.reliefGreenMedium;
    final info = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(
            user.isAdmin
                ? Icons.admin_panel_settings
                : user.isEmployee
                ? Icons.emergency
                : Icons.person,
            color: color,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    user.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  _tag(user.role.toUpperCase(), color),
                  if (user.cnic.isNotEmpty) _tag(user.cnic, Colors.blue),
                  if (!user.isActive) _tag('ACCOUNT INACTIVE', Colors.red),
                  if (flagged)
                    _tag(
                      '${usage.cancellationCount} cancellations',
                      Colors.orange.shade900,
                    ),
                  if (banned) _tag('EMERGENCY REQUESTS BANNED', Colors.red),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  if (user.email.isNotEmpty)
                    Text(
                      user.email,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  Text(
                    user.phone,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (user.address.isNotEmpty)
                    Text(
                      user.address,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
              if (user.isEmployee) ...[
                const SizedBox(height: 8),
                Text(
                  unit == null
                      ? 'No ambulance linked'
                      : 'Assigned vehicle: ${unit.vehicleNumber} · ${unit.status.toUpperCase()}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (banned) ...[
                const SizedBox(height: 6),
                Text(
                  usage.adminBanned
                      ? 'Banned by admin until unbanned'
                      : 'Automatic restriction until ${usage.bannedUntil!.toLocal()}',
                  style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (unit != null)
          TextButton.icon(
            onPressed: busy || unit.status == 'busy'
                ? null
                : () => _action(
                    user,
                    () => service.updateEmployeeStatus(
                      unit.employeeId,
                      unit.status == 'available' ? 'offline' : 'available',
                    ),
                  ),
            icon: Icon(
              unit.status == 'available'
                  ? Icons.pause_circle_outline
                  : Icons.play_circle_outline,
              size: 18,
            ),
            label: Text(unit.status == 'available' ? 'Standby' : 'Go active'),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Ban', style: TextStyle(fontSize: 12)),
            Switch(
              key: ValueKey('ban-${user.id}'),
              value: banned,
              activeThumbColor: Colors.red,
              onChanged: busy || self
                  ? null
                  : (value) => _action(
                      user,
                      () => value
                          ? service.banEmergencyUser(user.id)
                          : service.unbanEmergencyUser(user.id),
                    ),
            ),
            Text(
              banned ? 'Banned' : 'Allowed',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        Tooltip(
          message: 'Account activation',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Active', style: TextStyle(fontSize: 12)),
              Switch(
                key: ValueKey('active-${user.id}'),
                value: user.isActive,
                onChanged: busy || self
                    ? null
                    : (value) => _action(
                        user,
                        () => service.updateUserStatus(user.id, value),
                      ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Edit ${user.name}',
          onPressed: busy
              ? null
              : () => showAdminUserDialog(context, user: user),
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: 'Delete ${user.name}',
          onPressed: busy || self
              ? null
              : () => showAdminDeleteUserDialog(context, user),
          icon: const Icon(Icons.delete_outline),
          color: Colors.red,
        ),
      ],
    );
    return Container(
      key: ValueKey('user-card-${user.id}'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: flagged ? const Color(0xFFFFF3CD) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: flagged
              ? Colors.amber.shade600
              : !user.isActive
              ? Colors.red.shade200
              : AppColors.border,
          width: flagged ? 2 : 1,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 1100) {
            return Row(
              children: [
                Expanded(child: info),
                const SizedBox(width: 16),
                actions,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [info, const SizedBox(height: 14), actions],
          );
        },
      ),
    );
  }

  Widget _tag(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
    ),
  );
}
