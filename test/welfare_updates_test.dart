import 'package:flutter_test/flutter_test.dart';
import 'package:edhiconnect_ai/services/welfare_knowledge_service.dart';
import 'package:edhiconnect_ai/services/firestore_service.dart';
import 'package:edhiconnect_ai/models/emergency_request.dart';
import 'package:edhiconnect_ai/models/route_playback.dart';
import 'package:latlong2/latlong.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Arrival waits five real seconds after the endpoint', () {
    final start = DateTime(2026, 10, 4);
    final route = RoutePlayback(
      requestId: 'job',
      points: [const LatLng(34, 73)],
      startedAt: start,
      durationSeconds: 10.0005,
      speedFactor: 10,
    );
    expect(
      route.arrivalReadyAt(start.add(const Duration(milliseconds: 15000))),
      false,
    );
    expect(
      route.arrivalReadyAt(start.add(const Duration(milliseconds: 15001))),
      true,
    );
    expect(
      RoutePlayback(
        requestId: 'job',
        points: route.points,
        startedAt: start,
        durationSeconds: 10,
        pausedAt: start,
      ).arrivalReadyAt(start.add(const Duration(hours: 1))),
      false,
    );
  });
  test('Admin unban retains review history and restarts counting', () async {
    final now = DateTime(2026, 10, 4);
    final service = FirestoreService(
      automaticSimulation: false,
      clock: () => now,
    );
    addTearDown(service.dispose);
    for (var i = 0; i < 3; i++) {
      final id = await service.submitEmergencyRequest(
        EmergencyRequest(
          requestId: '',
          userId: 'review-user',
          emergencyType: 'Medical Emergency',
          description: 'Help required',
          createdAt: now,
          location: const RequestLocation(
            latitude: 34.2,
            longitude: 73.2,
            address: 'Patient location',
          ),
        ),
      );
      await service.cancelEmergencyRequest(id, 'review-user');
    }
    expect(
      (await service.getEmergencyUsage('review-user')).isBanned(now),
      true,
    );
    await service.unbanEmergencyUser('review-user');
    final usage = await service.getEmergencyUsage('review-user');
    expect(usage.isBanned(now), false);
    expect(usage.cancellationCount, 3);
    expect(usage.afterCancellation(now).cancellationCount, 1);
  });
  test('Organization questions, typos and greetings are distinguished', () {
    final chhipa = WelfareKnowledgeService.answer('Chipa ambulance number');
    expect(chhipa.text, contains('1020'));
    expect(chhipa.text, isNot(contains('Assalam')));
    expect(chhipa.isEmergencyIntent, false);
    expect(chhipa.sourceUrls.single, contains('chhipa.org'));
    expect(WelfareKnowledgeService.answer('hello').text, contains('Assalam'));
    expect(
      WelfareKnowledgeService.answer('Edhi ambulanse services').text,
      contains('115'),
    );
  });
  test(
    'Administrator profile edits persist instead of displaying a false save',
    () async {
      final service = FirestoreService(automaticSimulation: false);
      addTearDown(service.dispose);
      final user = (await service.getUsersStream().first).first;
      await service.updateUserProfile(
        user.id,
        name: 'Updated citizen',
        address: 'Updated address',
      );
      final saved = (await service.getUsersStream().first).firstWhere(
        (u) => u.id == user.id,
      );
      expect(saved.name, 'Updated citizen');
      expect(saved.address, 'Updated address');
      expect(saved.phone, user.phone);
    },
  );
  test('Roman Urdu and Urdu distress always surface emergency help', () {
    for (final message in [
      'patient behosh hai',
      'saans nahi aa rahi',
      'مریض بے ہوش ہے',
      'I need an ambulance immediately!',
    ]) {
      final reply = WelfareKnowledgeService.answer(message);
      expect(reply.isEmergencyIntent, true, reason: message);
      expect(reply.text, contains('115'));
      expect(reply.text, contains('1020'));
    }
    expect(
      WelfareKnowledgeService.answer('mujhe khoon donor chahiye').text,
      contains('Blood Bank'),
    );
  });
  test(
    'Provider follow-up stays in context and unknown facts are admitted',
    () {
      expect(
        WelfareKnowledgeService.answer(
          'what about their number?',
          history: ['Chhipa ambulance'],
        ).text,
        contains('1020'),
      );
      expect(
        WelfareKnowledgeService.answer('Chhipa charges today').text,
        contains('cannot verify'),
      );
      expect(
        WelfareKnowledgeService.answer('quantum rocket engines').text,
        contains('outside this welfare assistant'),
      );
    },
  );
  test('Official corpus loads once and cached responses stay fast', () async {
    await WelfareKnowledgeService.initialize();
    final timer = Stopwatch()..start();
    for (var i = 0; i < 25; i++) {
      expect(
        WelfareKnowledgeService.answer('Chhipa ambulance number').text,
        contains('1020'),
      );
    }
    timer.stop();
    expect(timer.elapsedMilliseconds, lessThan(2000));
  });
}
