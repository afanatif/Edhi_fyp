import 'dart:math';
import '../models/emergency_request.dart';
import '../models/chatbot_reply.dart';
import 'welfare_knowledge_service.dart';
export '../models/chatbot_reply.dart';

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

  static ChatbotReply getChatbotResponse(
    String message, {
    List<String> history = const [],
  }) => WelfareKnowledgeService.answer(message, history: history);
}
