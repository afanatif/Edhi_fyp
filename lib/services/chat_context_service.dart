import '../models/chatbot_reply.dart';
import '../models/missing_person_report.dart';
import '../models/emergency_request.dart';

class ChatContextService {
  static String? topic(String text) {
    final lower = text.toLowerCase();
    if (RegExp(
      r'blood|donor|khoon|khun|خون|(?:^|\s)(?:ab|a|b|o|0)\s*(?:[+-]|positive|negative|plus|minus)',
    ).hasMatch(lower)) {
      return 'blood';
    }
    if (RegExp(
      r'missing|lost person|lost child|found person|گمشدہ|لاپتہ',
    ).hasMatch(lower)) {
      return 'missing';
    }
    if (RegExp(r'ambulance|track|request status|ایمبولینس').hasMatch(lower)) {
      return 'ambulance';
    }
    if (RegExp(
      r'donation|donate|payment|receipt|ration|rashan',
    ).hasMatch(lower)) {
      return 'donation';
    }
    if (RegExp(r'first aid|burn|cpr').hasMatch(lower)) return 'first-aid';
    if (RegExp(r'login|profile|account|password').hasMatch(lower)) {
      return 'account';
    }
    if (RegExp(r'center|centre|office').hasMatch(lower)) return 'center';
    return null;
  }

  /// Stop at a topic switch so a previous patient's group/city does not leak into a new task.
  static List<String> topicHistory(String message, List<String> history) {
    final current =
        topic(message) ??
        history.reversed.map(topic).whereType<String>().firstOrNull;
    final relevant = <String>[];
    var matchedTopic = false;
    for (final previous in history.reversed) {
      final subject = topic(previous);
      if (subject != null && subject != current) {
        if (!matchedTopic) relevant.clear();
        break;
      }
      if (subject == current && subject != null) matchedTopic = true;
      relevant.add(previous);
    }
    return relevant.reversed.toList();
  }

  static bool hasMissingIntent(
    String message, {
    List<String> history = const [],
  }) {
    final subject = topic(message);
    if (subject != null) return subject == 'missing';
    if (RegExp(
      r'^(hi|hello|hey|salam)[!.\s]*$',
      caseSensitive: false,
    ).hasMatch(message.trim())) {
      return false;
    }
    bool explicit(String text) => RegExp(
      r'missing|lost person|lost child|found person|گمشدہ|لاپتہ',
      caseSensitive: false,
    ).hasMatch(text);
    if (explicit(message)) return true;
    if (RegExp(
      r'blood|donor|khoon|خون|ambulance|donation|payment',
      caseSensitive: false,
    ).hasMatch(message)) {
      return false;
    }
    if (message.trim().split(RegExp(r'\s+')).length > 6) return false;
    for (final previous in history.reversed) {
      if (explicit(previous)) return true;
      if (RegExp(
        r'blood|donor|khoon|خون|ambulance|donation',
        caseSensitive: false,
      ).hasMatch(previous)) {
        return false;
      }
    }
    return false;
  }

  static ChatbotReply missingReply(
    String message, {
    List<String> history = const [],
    List<MissingPersonReport>? reports,
    String? city,
  }) {
    final text = message.toLowerCase();
    final posting = RegExp(
      r'post|report|submit|add|create|درج|رپورٹ',
    ).hasMatch(text);
    final suggestions = ['Open Missing Persons', 'Open Home'];
    if (posting &&
        RegExp(
          r'\b(post|submit|add|create|report a|report my)\b|درج',
        ).hasMatch(text)) {
      return ChatbotReply(
        text:
            'Open Missing Persons → Report Person. Enter the person’s name, age, last-seen location and time, description and contact details. Add a photo in that form, then submit the report there.',
        quickSuggestions: suggestions,
      );
    }
    if (reports == null) {
      return ChatbotReply(
        text:
            'Missing-person records could not be checked right now. Open Missing Persons to retry or use Report Person to submit a report.',
        quickSuggestions: suggestions,
      );
    }
    String? extractName(String query) =>
        RegExp(
              r'(?:named\s+|name\s*:\s*|search for\s+)([^,?!;\n]+)',
              caseSensitive: false,
            )
            .firstMatch(query)
            ?.group(1)
            ?.split(RegExp(r'\s+(?:in|from|near)\s+', caseSensitive: false))
            .first
            .trim();
    final shortName =
        !RegExp(
              r'missing|found|report|how|where|many|available|records|person|people|status|any|there|ones|show|list|yes|hello|hi\b|now|details|phone|contact|kitne|kahan|haan',
              caseSensitive: false,
            ).hasMatch(message) &&
            city == null &&
            message.split(' ').length <= 3
        ? message.trim()
        : null;
    var filterName = extractName(message) ?? shortName;
    if (filterName == null) {
      for (final previous in history.reversed) {
        filterName = extractName(previous);
        if (filterName != null) break;
      }
    }
    final statusQuery = [message, ...history.reversed].firstWhere(
      (m) => RegExp(
        r'found|reunited|all reports|searching|open reports|active reports',
        caseSensitive: false,
      ).hasMatch(m),
      orElse: () => '',
    );
    final includeClosed = RegExp(
      r'found|reunited|all reports',
      caseSensitive: false,
    ).hasMatch(statusQuery);
    final matches = reports
        .where(
          (report) =>
              (includeClosed || report.isSearching) &&
              (city == null ||
                  report.lastSeenLocation.toLowerCase().contains(
                    city.toLowerCase(),
                  )) &&
              (filterName == null ||
                  filterName.isEmpty ||
                  report.personName.toLowerCase().contains(
                    filterName.toLowerCase(),
                  )),
        )
        .toList();
    final scope = [?city, ?filterName].join(' · ');
    final heading =
        '${matches.length} matching ${includeClosed ? '' : 'open '}report(s)${scope.isEmpty ? '' : ' — $scope'} in the latest records checked.';
    return ChatbotReply(
      text:
          '$heading\n\n${matches.isEmpty ? 'No matching report was found in the records checked. Open Missing Persons to browse further or report a person.' : matches.take(4).map((r) => '• ${r.personName}, ${r.age} · ${r.status}\n  Last seen: ${r.lastSeenLocation} · Report #${r.reportId}').join('\n')}\n\nOpen Missing Persons for photos, full details and contact options.',
      quickSuggestions: suggestions,
    );
  }

  static bool wantsRequestStatus(
    String message, {
    List<String> history = const [],
  }) {
    final text = message.toLowerCase();
    return RegExp(
          r'track|my request|my ambulance|request status|assigned to me',
        ).hasMatch(text) ||
        (history.any((m) => topic(m) == 'ambulance') &&
            RegExp(
              r'^(status|where is it|what now|assigned|arrived)[?.!\s]*$',
            ).hasMatch(text));
  }

  static ChatbotReply requestReply(List<EmergencyRequest>? requests) {
    if (requests == null) {
      return const ChatbotReply(
        text:
            'Your request status could not be loaded right now. Open Home and select your request to retry.',
        quickSuggestions: ['Open Home'],
      );
    }
    final open = requests
        .where((r) => r.status != 'Cancelled' && r.status != 'Completed')
        .toList();
    return ChatbotReply(
      text: open.isEmpty
          ? 'You have no open ambulance request in the records checked. Open Home to see your requests or create an Emergency Request.'
          : '${open.length} open request(s) in the records checked:\n\n${open.take(3).map((r) => '• Request #${r.requestId} · ${r.emergencyType}\n  Status: ${r.status}${r.assignedEmployeeId == null ? ' · Waiting for assignment' : ' · Unit: ${r.assignedEmployeeId}'}').join('\n')}\n\nOpen Home and select the request card for the tracking map and latest updates.',
      quickSuggestions: ['Open Home', 'Open Emergency Request'],
    );
  }

  static bool wantsBloodNeeds(
    String message, {
    List<String> history = const [],
  }) {
    bool asks(String text) => RegExp(
      r'blood requests|blood needs|who needs|urgent needs|donate blood|blood donation',
      caseSensitive: false,
    ).hasMatch(text);
    if (asks(message)) return true;
    if (RegExp(
      r'donor|find blood|need blood|register',
      caseSensitive: false,
    ).hasMatch(message)) {
      return false;
    }
    return history.reversed.any(asks);
  }

  static ChatbotReply bloodNeedsReply(
    List<Map<String, dynamic>>? needs, {
    String? group,
    String? city,
  }) {
    if (needs == null) {
      return const ChatbotReply(
        text:
            'Current blood requests could not be checked. Open Blood Bank → Requests to retry.',
        quickSuggestions: ['Open Blood Bank'],
      );
    }
    final matches = needs
        .where(
          (n) =>
              n['status'] == 'active' &&
              (group == null || n['bloodGroup'] == group) &&
              (city == null ||
                  n['hospital'].toString().toLowerCase().contains(
                    city.toLowerCase(),
                  )),
        )
        .toList();
    return ChatbotReply(
      text:
          '${matches.length} active blood request(s)${group == null ? '' : ' for $group'}${city == null ? '' : ' matching $city in the hospital details'} in the records checked.\n\n${matches.isEmpty ? 'No matching active request was found in these records.' : matches.take(4).map((n) => '• ${n['patientName']} · ${n['bloodGroup']} · ${n['unitsNeeded']} unit(s)\n  ${n['hospital']} · Contact: ${n['contact']}').join('\n')}\n\nOpen Blood Bank → Requests to view the full post and use I Will Donate. To register as a donor, use the Donate tab.',
      quickSuggestions: ['Open Blood Bank', 'Register as Blood Donor'],
    );
  }
}
