import 'dart:math';
import '../models/emergency_request.dart';

class ChatbotReply {
  final String text;
  final bool isEmergencyIntent;
  final List<String> quickSuggestions;

  const ChatbotReply({
    required this.text,
    this.isEmergencyIntent = false,
    this.quickSuggestions = const [],
  });
}

class FraudAssessment {
  final double score; // 0.0 (clean) to 1.0 (fraud/prank)
  final String level; // 'Low', 'Medium', 'High'
  final List<String> reasons;

  const FraudAssessment({
    required this.score,
    required this.level,
    required this.reasons,
  });
}

class AITriageService {
  /// Evaluates incoming emergency parameters to detect prank calls, fraudulent spam, or spoofed locations.
  /// Generates a probabilistic Fraud Risk Score (0.0 to 1.0) and explainable risk factors.
  static FraudAssessment assessFraudRisk({
    required String description,
    required String userPhone,
    required RequestLocation location,
    List<EmergencyRequest> recentRequests = const [],
  }) {
    double risk = 0.0;
    final List<String> reasons = [];
    final text = description.trim().toLowerCase();

    // 1. NLP Heuristics: Prank, Joke, and Test keywords
    final prankKeywords = [
      'prank',
      'joke',
      'just kidding',
      'fake',
      'testing',
      'dummy',
      'asdf',
      'lol',
      'haha',
      'troll',
      'fun call',
      'party',
      'boring',
    ];

    for (final pk in prankKeywords) {
      if (text.contains(pk)) {
        risk += 0.45;
        reasons.add('Description contains prank/test term "$pk"');
        break;
      }
    }

    // Repetitive character spam (e.g. "aaaaaa", "zzzzz")
    if (RegExp(r'(.)\1{4,}').hasMatch(text)) {
      risk += 0.25;
      reasons.add('Repetitive character sequence / keyboard mash detected');
    }

    // Overly brief description for severe calls
    if (text.isNotEmpty && text.length < 4) {
      risk += 0.15;
      reasons.add('Vague description (< 4 characters)');
    }

    // 2. Contact Phone Verification Heuristics
    final cleanPhone = userPhone.replaceAll(RegExp(r'[^0-9]'), '');
    final dummyPatterns = [
      '0000000000',
      '123456789',
      '1111111111',
      '03000000000',
      '03333333333',
      '03123456789',
    ];

    if (dummyPatterns.any((p) => cleanPhone.contains(p))) {
      risk += 0.40;
      reasons.add('Contact phone exhibits dummy or sequential number pattern');
    } else if (cleanPhone.isNotEmpty && cleanPhone.length < 10) {
      risk += 0.20;
      reasons.add('Contact phone number is incomplete (< 10 digits)');
    }

    // 3. Geospatial Plausibility & Regional Boundary Check
    // Pakistan operational envelope: Lat ~23.5 to 37.8, Lng ~60.5 to 77.5
    final lat = location.latitude;
    final lng = location.longitude;
    if (lat == 0.0 && lng == 0.0) {
      risk += 0.25;
      reasons.add('Coordinates missing / Null Island location (0, 0)');
    } else if (lat < 23.5 || lat > 37.8 || lng < 60.5 || lng > 77.5) {
      risk += 0.40;
      reasons.add(
        'Coordinates located outside regional operational jurisdiction',
      );
    }

    // 4. Rate Anomaly & Rapid Multi-Submission Check
    final now = DateTime.now();
    final recentFromSamePhone = recentRequests.where((r) {
      if (r.status == 'Cancelled' || r.status == 'Completed') return false;
      final matchPhone =
          r.userPhone.isNotEmpty &&
          cleanPhone.isNotEmpty &&
          r.userPhone.replaceAll(RegExp(r'[^0-9]'), '') == cleanPhone;
      final createdAt = r.createdAt ?? now;
      final ageMinutes = now.difference(createdAt).inMinutes.abs();
      return matchPhone && ageMinutes <= 10;
    }).length;

    if (recentFromSamePhone >= 2) {
      risk += 0.35;
      reasons.add(
        'High submission velocity ($recentFromSamePhone unclosed requests in last 10 mins)',
      );
    }

    final normalizedScore = risk.clamp(0.0, 1.0);
    final String level = normalizedScore >= 0.55
        ? 'High'
        : (normalizedScore >= 0.30 ? 'Medium' : 'Low');

    return FraudAssessment(
      score: double.parse(normalizedScore.toStringAsFixed(2)),
      level: level,
      reasons: reasons,
    );
  }

  /// Analyzes emergency description & type to assign a clinical priority level.
  /// Increment 3 AI Module Requirement.
  static String classifyPriority({
    required String emergencyType,
    required String description,
  }) {
    final text = '${emergencyType.toLowerCase()} ${description.toLowerCase()}';

    // High critical triage triggers (P1 - Immediate Life Threat)
    final criticalKeywords = [
      'unconscious',
      'not breathing',
      'no pulse',
      'cardiac',
      'heart attack',
      'heavy bleeding',
      'severe bleeding',
      'fire explosion',
      'blast',
      'head trauma',
      'head injury',
      'drowning',
      'electrocution',
      'choking',
      'critical',
      'fatal',
      'collapsed',
    ];

    for (final kw in criticalKeywords) {
      if (text.contains(kw)) {
        return 'Critical P1';
      }
    }

    // Urgent triage triggers (P2 - Serious Condition, Not Immediately Fatal)
    final urgentKeywords = [
      'fracture',
      'broken bone',
      'burn',
      'chest pain',
      'asthma',
      'breathlessness',
      'poison',
      'bleeding',
      'collision',
      'accident',
      'maternity',
      'labour',
      'high fever',
    ];

    for (final kw in urgentKeywords) {
      if (text.contains(kw)) {
        return 'Urgent P2';
      }
    }

    // Default to Standard Priority (P3)
    return 'Standard P3';
  }

  /// Evaluates whether an incoming emergency is a likely duplicate of an existing active incident.
  /// Proposal Module 9 Requirement (within 150 meters and 20 minutes).
  static EmergencyRequest? detectDuplicate({
    required RequestLocation newLoc,
    required List<EmergencyRequest> activeRequests,
  }) {
    final now = DateTime.now();

    for (final req in activeRequests) {
      // Only compare with uncompleted & non-cancelled incidents
      if (req.status == 'Completed' || req.status == 'Cancelled') continue;

      final createdAt = req.createdAt ?? now;
      final diffMinutes = now.difference(createdAt).inMinutes.abs();

      // Within 20-minute window
      if (diffMinutes <= 20) {
        final distanceKm = _calculateDistance(
          newLoc.latitude,
          newLoc.longitude,
          req.location.latitude,
          req.location.longitude,
        );

        // Within 150 meters (0.15 km)
        if (distanceKm <= 0.15) {
          return req;
        }
      }
    }

    return null;
  }

  /// Calculates Haversine distance in Kilometers between two coordinates.
  static double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    if (lat1 == 0.0 || lon1 == 0.0 || lat2 == 0.0 || lon2 == 0.0) return 999.0;

    const double earthRadiusKm = 6371.0;
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadiusKm * c;
  }

  static double _degreesToRadians(double degrees) => degrees * (pi / 180.0);

  /// AI Chatbot Natural Language Processor & FAQ Engine for Edhi Foundation Services
  static ChatbotReply getChatbotResponse(String message) {
    final lower = message.trim().toLowerCase();

    // Emergency Detection
    if (lower.contains('emergency') ||
        lower.contains('ambulance') ||
        lower.contains('sos') ||
        lower.contains('accident') ||
        lower.contains('dying') ||
        lower.contains('heart attack') ||
        lower.contains('bleeding')) {
      return const ChatbotReply(
        text:
            '⚠️ **EMERGENCY DETECTED:** If someone is in immediate danger, tap the button below to dispatch an ambulance or dial 115 directly. Keep the patient calm and apply basic first aid if trained.',
        isEmergencyIntent: true,
        quickSuggestions: [
          'Dispatch Ambulance Now',
          'Call Helpline 115',
          'First Aid Instructions',
        ],
      );
    }

    // Blood Donation inquiries
    if (lower.contains('blood') ||
        lower.contains('donor') ||
        lower.contains('plasma')) {
      return const ChatbotReply(
        text:
            '🩸 **Edhi Blood Services:** You can register as a voluntary blood donor or submit an urgent blood request through our Blood Bank section. We connect verified donors with hospitals across Pakistan. Compatible donors are notified instantly.',
        quickSuggestions: [
          'Register as Blood Donor',
          'Request Blood for Patient',
          'Check Blood Groups',
        ],
      );
    }

    // Donations & Sadaqah inquiries
    if (lower.contains('donate') ||
        lower.contains('donation') ||
        lower.contains('zakat') ||
        lower.contains('ration') ||
        lower.contains('money')) {
      return const ChatbotReply(
        text:
            '💚 **Donations & Transparency:** Edhi Foundation accepts monetary donations, ration packages, clothing, and ambulance fuel support. Every contribution generates a verifiable digital receipt with a unique transaction ID. You can also request home pickup for in-kind food or clothing.',
        quickSuggestions: [
          'Donate Money Online',
          'Ration / Food Drive',
          'View Active Campaigns',
        ],
      );
    }

    // Edhi Centers inquiries
    if (lower.contains('center') ||
        lower.contains('office') ||
        lower.contains('address') ||
        lower.contains('location') ||
        lower.contains('branch')) {
      return const ChatbotReply(
        text:
            '🏢 **Edhi Centers & Stations:** We operate nationwide emergency relief centers. Key stations include Mandian (Abbottabad), G-8 Markaz (Islamabad), and Bolton Market (Karachi Head Office). All centers operate 24/7 emergency dispatch and morgue services.',
        quickSuggestions: ['Find Nearest Center', 'Emergency Contacts'],
      );
    }

    // First Aid inquiries
    if (lower.contains('first aid') ||
        lower.contains('cpr') ||
        lower.contains('burn') ||
        lower.contains('fracture') ||
        lower.contains('chok')) {
      return const ChatbotReply(
        text:
            '🩹 **First Aid Assistance:** EdhiConnect provides verified life-saving protocols for CPR, severe bleeding control (direct pressure), burns (cool running water for 10-20 min), and fractures. Access our First Aid Guide from the Quick Help dashboard.',
        quickSuggestions: [
          'How to do CPR',
          'Treating Severe Bleeding',
          'Burn First Aid',
        ],
      );
    }

    // Missing Persons inquiries
    if (lower.contains('missing') ||
        lower.contains('found') ||
        lower.contains('lost person') ||
        lower.contains('child')) {
      return const ChatbotReply(
        text:
            '🔍 **Missing Persons & Reunification:** Edhi Foundation provides family reunification support. You can report a missing or found person with photo, last seen location, and contact details. Our team matches reports with Edhi shelter records.',
        quickSuggestions: ['Report Missing Person', 'Call Helpline 115'],
      );
    }

    // Greeting
    if (lower.contains('hello') ||
        lower.contains('hi') ||
        lower.contains('salam') ||
        lower.contains('hey')) {
      return const ChatbotReply(
        text:
            'Assalam-o-Alaikum! I am your **EdhiConnect AI Assistant**. I can help guide you with emergency ambulance requests, blood donation coordination, charity campaigns, first-aid instructions, and finding nearby Edhi relief centers.',
        quickSuggestions: [
          'How to request an ambulance?',
          'Register as Blood Donor',
          'Donate to Flood Relief',
          'Nearby Edhi Centers',
        ],
      );
    }

    // General fallback
    return const ChatbotReply(
      text:
          'Thank you for reaching out to EdhiConnect AI. I can assist you with emergency response protocols, ambulance dispatch, blood requests, donations, and finding Edhi welfare centers. How can I assist you today?',
      quickSuggestions: [
        'Request Emergency Help',
        'Blood Bank Registry',
        'Make a Donation',
        'Call Edhi 115',
      ],
    );
  }
}
