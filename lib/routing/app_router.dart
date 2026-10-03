import 'package:flutter/material.dart';
import '../core/constants/app_constants.dart';
import '../features/user/home/user_home_screen.dart';
import '../features/employee/dashboard/employee_dashboard_screen.dart';
import '../features/admin/dashboard/admin_dashboard_screen.dart';

class AppRouter {
  AppRouter._();

  static Widget getDashboardForRole(String role) {
    switch (role.toLowerCase()) {
      case AppRoles.admin:
        return const AdminDashboardScreen();
      case AppRoles.employee:
        return const EmployeeDashboardScreen();
      case AppRoles.user:
      default:
        return const UserHomeScreen();
    }
  }
}
