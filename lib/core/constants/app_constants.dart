/// Global constants for roles, collection names, and emergency statuses.
class AppConstants {
  AppConstants._();

  static const String appName = 'EdhiConnect AI';
  static const String appTagline = 'Emergency Response & Social Welfare System';

  // Firestore Collections
  static const String usersCollection = 'users';
  static const String requestsCollection = 'emergency_requests';
  static const String donationsCollection = 'donations';
  static const String bloodDonorsCollection = 'blood_donors';
  static const String bloodNeedsCollection = 'blood_needs';
  static const String employeesCollection = 'employees';
  static const String tasksCollection = 'tasks';
  static const String centersCollection = 'edhi_centers';
  static const String notificationsCollection = 'notifications';
  static const String chatThreadsCollection = 'chat_threads';
  static const String chatMessagesCollection = 'chat_messages';
  static const String feedbackCollection = 'feedback';
  static const String missingPersonsCollection = 'missing_persons';
}

/// User roles in the platform.
class AppRoles {
  AppRoles._();

  static const String user = 'user';
  static const String employee = 'employee';
  static const String admin = 'admin';

  static const List<String> allRoles = [user, employee, admin];

  static String getDisplayName(String role) {
    switch (role.toLowerCase()) {
      case admin:
        return 'Administrator';
      case employee:
        return 'Ambulance Driver / Staff';
      case user:
      default:
        return 'Public Citizen';
    }
  }
}

/// Statuses for Emergency Requests.
class EmergencyStatus {
  EmergencyStatus._();

  static const String pending = 'Pending';
  static const String approved = 'Approved';
  static const String assigned = 'Assigned';
  static const String inProgress = 'InProgress';
  static const String arrived = 'Arrived';
  static const String completed = 'Completed';
  static const String cancelled = 'Cancelled';

  static bool canTransition(String from, String to) {
    if (from == to) return true;
    return switch (from) {
      pending => const [approved, assigned, cancelled].contains(to),
      approved => const [assigned, cancelled].contains(to),
      assigned => const [inProgress, cancelled].contains(to),
      inProgress => const [arrived, cancelled].contains(to),
      arrived => const [completed, cancelled].contains(to),
      _ => false,
    };
  }

  static const List<String> all = [
    pending,
    approved,
    assigned,
    inProgress,
    arrived,
    completed,
    cancelled,
  ];
}

/// Categories of emergencies.
class EmergencyCategories {
  EmergencyCategories._();

  static const String medical = 'Medical Emergency';
  static const String roadAccident = 'Road Accident';
  static const String fire = 'Fire or Burn';
  static const String safety = 'Safety Emergency';
  static const String other = 'Other Emergency';

  static const List<String> all = [medical, roadAccident, fire, safety, other];
}
