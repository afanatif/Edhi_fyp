import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../services/firestore_service.dart';
import '../../../models/app_user.dart';
import '../../../models/employee.dart';
import '../../../core/widgets/skeleton_loader.dart';

class AdminUsersView extends StatefulWidget {
  const AdminUsersView({super.key});

  @override
  State<AdminUsersView> createState() => _AdminUsersViewState();
}

class _AdminUsersViewState extends State<AdminUsersView> {
  String _selectedRoleFilter = 'All';
  String _searchQuery = '';

  void _showEditUserDialog(BuildContext context, AppUser user) {
    final nameController = TextEditingController(text: user.name);
    final phoneController = TextEditingController(text: user.phone);
    final addressController = TextEditingController(text: user.address);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit User: ${user.name}'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(
                  labelText: 'Station / Address',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.reliefGreenMedium,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Updated profile for ${nameController.text}'),
                  backgroundColor: AppColors.reliefGreenMedium,
                ),
              );
            },
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final firestore = context.watch<FirestoreService>();

    return StreamBuilder<List<AppUser>>(
      stream: firestore.getUsersStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Expanded(child: SkeletonMetricTile()),
                  SizedBox(width: 12),
                  Expanded(child: SkeletonMetricTile()),
                  SizedBox(width: 12),
                  Expanded(child: SkeletonMetricTile()),
                ],
              ),
              const SizedBox(height: 24),
              const SkeletonBox(
                width: double.infinity,
                height: 50,
                borderRadius: 12,
              ),
              const SizedBox(height: 16),
              const SkeletonListView(count: 5, skeleton: SkeletonUserCard()),
            ],
          );
        }
        final users = snapshot.data ?? [];
        final employees = firestore.getAllEmployees();

        final filteredUsers = users.where((u) {
          final query = _searchQuery.trim().toLowerCase();
          final matchesSearch =
              query.isEmpty ||
              u.name.toLowerCase().contains(query) ||
              u.email.toLowerCase().contains(query) ||
              u.phone.contains(query) ||
              u.cnic.toLowerCase().contains(query) ||
              AppUser.cleanCnic(u.cnic).contains(query);
          if (!matchesSearch) return false;

          if (_selectedRoleFilter == 'Citizens') return u.role == AppRoles.user;
          if (_selectedRoleFilter == 'Drivers') {
            return u.role == AppRoles.employee;
          }
          if (_selectedRoleFilter == 'Admins') return u.role == AppRoles.admin;
          return true;
        }).toList();

        final citizenCount = users.where((u) => u.role == AppRoles.user).length;
        final driverCount = employees.length;
        final activeDrivers = employees
            .where((e) => e.status == 'available')
            .length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header stats
            Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    'Total Users',
                    '${users.length}',
                    Icons.people_alt_outlined,
                    AppColors.emergencyRed,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricTile(
                    'Citizens',
                    '$citizenCount',
                    Icons.person_outline,
                    AppColors.reliefGreenMedium,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricTile(
                    'Ambulance Drivers',
                    '$activeDrivers / $driverCount Available',
                    Icons.directions_car_outlined,
                    AppColors.emergencyRedDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Controls Bar (Search + Filter Chips)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          onChanged: (val) =>
                              setState(() => _searchQuery = val),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(
                              Icons.search,
                              color: AppColors.textSecondary,
                            ),
                            hintText:
                                'Search by name, email, or contact number...',
                            filled: true,
                            fillColor: AppColors.background,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Wrap(
                        spacing: 8,
                        children: ['All', 'Citizens', 'Drivers', 'Admins'].map((
                          role,
                        ) {
                          final isSelected = _selectedRoleFilter == role;
                          return ChoiceChip(
                            label: Text(role),
                            selected: isSelected,
                            selectedColor: AppColors.reliefGreenMedium
                                .withValues(alpha: 0.2),
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? AppColors.reliefGreenMedium
                                  : AppColors.textPrimary,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              fontSize: 12,
                            ),
                            onSelected: (sel) {
                              if (sel) {
                                setState(() => _selectedRoleFilter = role);
                              }
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Users Table / Cards
            if (filteredUsers.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(48),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Column(
                  children: [
                    Icon(
                      Icons.person_off_outlined,
                      size: 48,
                      color: AppColors.textSecondary,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'No matching personnel found',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filteredUsers.length,
                separatorBuilder: (context, _) => const SizedBox(height: 12),
                itemBuilder: (context, idx) {
                  final user = filteredUsers[idx];
                  Employee? matchedEmp;
                  if (user.role == AppRoles.employee) {
                    matchedEmp = employees.firstWhere(
                      (e) =>
                          e.employeeId == user.id ||
                          e.userId == user.id ||
                          e.phone == user.phone,
                      orElse: () => Employee(
                        employeeId: user.id,
                        userId: user.id,
                        name: user.name,
                        phone: user.phone,
                        status: 'available',
                        vehicleNumber: 'EDHI-AMB-201',
                      ),
                    );
                  }

                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: user.isActive
                            ? AppColors.border
                            : Colors.red.shade200,
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: user.role == AppRoles.admin
                              ? Colors.purple.shade50
                              : user.role == AppRoles.employee
                              ? AppColors.emergencyRed.withValues(alpha: 0.1)
                              : AppColors.reliefGreenSoft,
                          child: Icon(
                            user.role == AppRoles.admin
                                ? Icons.admin_panel_settings
                                : user.role == AppRoles.employee
                                ? Icons.emergency
                                : Icons.person,
                            color: user.role == AppRoles.admin
                                ? Colors.purple
                                : user.role == AppRoles.employee
                                ? AppColors.emergencyRed
                                : AppColors.reliefGreenMedium,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    user.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: user.role == AppRoles.admin
                                          ? Colors.purple.withValues(alpha: 0.1)
                                          : user.role == AppRoles.employee
                                          ? AppColors.emergencyRed.withValues(
                                              alpha: 0.1,
                                            )
                                          : AppColors.reliefGreenSoft,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      user.role.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: user.role == AppRoles.admin
                                            ? Colors.purple
                                            : user.role == AppRoles.employee
                                            ? AppColors.emergencyRed
                                            : AppColors.reliefGreenMedium,
                                      ),
                                    ),
                                  ),
                                  if (user.cnic.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEFF6FF),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: const Color(0xFFBFDBFE),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.badge_outlined,
                                            size: 10,
                                            color: Color(0xFF2563EB),
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            user.cnic,
                                            style: const TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF1D4ED8),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  if (!user.isActive) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade200,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'DEACTIVATED',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.email_outlined,
                                    size: 13,
                                    color: AppColors.textSecondary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    user.email,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Icon(
                                    Icons.phone_outlined,
                                    size: 13,
                                    color: AppColors.textSecondary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    user.phone,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  if (user.address.isNotEmpty) ...[
                                    const SizedBox(width: 12),
                                    const Icon(
                                      Icons.location_on_outlined,
                                      size: 13,
                                      color: AppColors.textSecondary,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        user.address,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (matchedEmp != null) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.background,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.airport_shuttle,
                                        size: 14,
                                        color: AppColors.emergencyRed,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Assigned Vehicle: ${matchedEmp.vehicleNumber}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Status: ${matchedEmp.status.toUpperCase()}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color:
                                              matchedEmp.status == 'available'
                                              ? AppColors.reliefGreenMedium
                                              : Colors.orange,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        // Action buttons
                        Row(
                          children: [
                            if (matchedEmp != null) ...[
                              Tooltip(
                                message: matchedEmp.status == 'available'
                                    ? 'Set driver standby / offline'
                                    : 'Mark driver available for dispatch',
                                child: TextButton.icon(
                                  icon: Icon(
                                    matchedEmp.status == 'available'
                                        ? Icons.pause_circle
                                        : Icons.play_circle,
                                    size: 16,
                                    color: matchedEmp.status == 'available'
                                        ? Colors.orange
                                        : AppColors.reliefGreenMedium,
                                  ),
                                  label: Text(
                                    matchedEmp.status == 'available'
                                        ? 'Standby'
                                        : 'Go Active',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: matchedEmp.status == 'available'
                                          ? Colors.orange
                                          : AppColors.reliefGreenMedium,
                                    ),
                                  ),
                                  onPressed: matchedEmp.status == 'busy'
                                      ? null
                                      : () async {
                                          final newStatus =
                                              matchedEmp!.status == 'available'
                                              ? 'offline'
                                              : 'available';
                                          try {
                                            await firestore
                                                .updateEmployeeStatus(
                                                  matchedEmp.employeeId,
                                                  newStatus,
                                                );
                                          } catch (error) {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text('$error'),
                                                ),
                                              );
                                            }
                                            return;
                                          }
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                '${user.name} marked $newStatus',
                                              ),
                                              duration: const Duration(
                                                seconds: 2,
                                              ),
                                            ),
                                          );
                                        },
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            IconButton(
                              icon: const Icon(
                                Icons.edit_outlined,
                                size: 18,
                                color: AppColors.textSecondary,
                              ),
                              tooltip: 'Edit Profile',
                              onPressed: () =>
                                  _showEditUserDialog(context, user),
                            ),
                            Tooltip(
                              message: user.isActive
                                  ? 'Deactivate User'
                                  : 'Activate User',
                              child: Switch(
                                value: user.isActive,
                                activeTrackColor: AppColors.reliefGreenMedium,
                                onChanged: (val) {
                                  firestore.updateUserStatus(user.id, val);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '${user.name} is now ${val ? "Active" : "Deactivated"}',
                                      ),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  Widget _buildMetricTile(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
