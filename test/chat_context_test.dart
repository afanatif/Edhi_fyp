import 'package:flutter_test/flutter_test.dart';
import 'package:edhiconnect_ai/services/chat_context_service.dart';
import 'package:edhiconnect_ai/services/welfare_knowledge_service.dart';
import 'package:edhiconnect_ai/services/firestore_service.dart';
import 'package:edhiconnect_ai/models/blood_donor.dart';
import 'package:edhiconnect_ai/models/missing_person_report.dart';
import 'package:edhiconnect_ai/models/emergency_request.dart';

MissingPersonReport report(
  String id,
  String name,
  String city, {
  String status = 'Searching',
}) => MissingPersonReport(
  reportId: id,
  personName: name,
  age: 12,
  gender: 'Not specified',
  lastSeenLocation: city,
  description: 'Details',
  contactName: 'Contact',
  contactPhone: '+923001234567',
  reportedAt: DateTime.now(),
  status: status,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Missing-person name, city and status follow-ups filter actual records',
    () {
      final records = [
        report('one', 'Ali', 'Abbottabad'),
        report('two', 'Ali', 'Karachi'),
        report('three', 'Sara', 'Abbottabad'),
        report('closed', 'Ali', 'Abbottabad', status: 'Found'),
      ];
      final history = ['missing person reports', 'name: Ali'];
      final reply = ChatContextService.missingReply(
        'Abbottabad',
        history: history,
        reports: records,
        city: 'Abbottabad',
      );
      expect(reply.text, contains('1 matching open report'));
      expect(reply.text, contains('#one'));
      for (final excluded in ['#two', '#three', '#closed']) {
        expect(reply.text, isNot(contains(excluded)));
      }
      expect(
        ChatContextService.missingReply(
          'all reports',
          history: history,
          reports: records,
          city: 'Abbottabad',
        ).text,
        contains('#closed'),
      );
      expect(
        ChatContextService.missingReply('any?', reports: records).text,
        contains('3 matching open'),
      );
      expect(
        ChatContextService.missingReply('missing persons', reports: null).text,
        contains('could not be checked'),
      );
      final guidance = ChatContextService.missingReply(
        'post missing person',
        reports: records,
      );
      expect(guidance.text, contains('Missing Persons → Report Person'));
      expect(guidance.quickSuggestions, ['Open Missing Persons', 'Open Home']);
    },
  );

  test('A topic switch clears irrelevant group, city and request context', () {
    final history = [
      'need A+ blood in Karachi',
      'missing person reports in Abbottabad',
      'name: Ali',
    ];
    expect(ChatContextService.topicHistory('B negative', history), isEmpty);
    expect(
      ChatContextService.hasMissingIntent('B negative', history: history),
      false,
    );
    final reply = WelfareKnowledgeService.answer(
      'blood donors available?',
      history: history,
      donors: [
        const BloodDonor(
          donorId: 'new',
          userId: 'u',
          userName: 'Fresh donor',
          userPhone: '+923001234567',
          bloodGroup: 'O-',
          city: 'Haripur',
        ),
      ],
    );
    expect(reply.text, contains('Fresh donor'));
    expect(reply.text, isNot(contains('Karachi')));
    expect(reply.text, isNot(contains('Abbottabad')));
    expect(
      ChatContextService.wantsRequestStatus(
        'status?',
        history: ChatContextService.topicHistory('status?', [
          'track my ambulance',
          'need blood',
        ]),
      ),
      false,
    );
  });

  test(
    'Service checks available donors and remembers group/city across multiple follow-ups',
    () async {
      final service = FirestoreService(automaticSimulation: false);
      addTearDown(service.dispose);
      await service.registerBloodDonor(
        const BloodDonor(
          donorId: '',
          userId: 'context-donor',
          userName: 'Context donor',
          userPhone: '+923001234567',
          bloodGroup: 'A+',
          city: 'Haripur',
        ),
      );
      await service.registerBloodDonor(
        const BloodDonor(
          donorId: '',
          userId: 'busy-donor',
          userName: 'Busy donor',
          userPhone: '+923001234568',
          bloodGroup: 'A+',
          city: 'Haripur',
          availability: false,
        ),
      );
      await service.sendChatMessage('I need A+ blood');
      await service.sendChatMessage('Haripur');
      await service.sendChatMessage('how many are available?');
      final reply = (await service.getChatStream().first).last.message;
      expect(reply, contains('Context donor'));
      expect(reply, contains('Haripur'));
      expect(reply, contains('1 available'));
      expect(reply, isNot(contains('Busy donor')));
    },
  );

  test(
    'Service reads newly added reports, blood needs and only the current requester’s jobs',
    () async {
      final service = FirestoreService(automaticSimulation: false);
      addTearDown(service.dispose);
      await service.submitMissingPersonReport(
        report('', 'Context Person', 'Haripur'),
      );
      await service.sendChatMessage('missing person reports');
      await service.sendChatMessage('name: Context Person');
      await service.sendChatMessage('Haripur');
      expect(
        (await service.getChatStream().first).last.message,
        contains('Context Person'),
      );
      await service.submitUrgentBloodNeed(
        UrgentBloodNeed(
          id: 'context-need',
          patientName: 'Patient Context',
          hospital: 'Haripur hospital',
          bloodGroup: 'AB-',
          unitsNeeded: 2,
          contact: '+923001234567',
          userId: 'need-owner',
          createdAt: DateTime.now(),
        ),
      );
      await service.sendChatMessage('AB- blood requests in Haripur');
      expect(
        (await service.getChatStream().first).last.message,
        contains('Patient Context'),
      );
      final now = DateTime.now();
      await service.submitEmergencyRequest(
        EmergencyRequest(
          requestId: '',
          userId: 'local_demo',
          emergencyType: 'Own request',
          description: 'Patient needs assistance',
          createdAt: now,
          location: const RequestLocation(
            latitude: 34.2,
            longitude: 73.2,
            address: 'Location',
          ),
        ),
      );
      await service.submitEmergencyRequest(
        EmergencyRequest(
          requestId: '',
          userId: 'someone-else',
          emergencyType: 'Private other request',
          description: 'Patient needs assistance',
          createdAt: now,
          location: const RequestLocation(
            latitude: 34.3,
            longitude: 73.3,
            address: 'Other location',
          ),
        ),
      );
      await service.sendChatMessage('track my ambulance');
      final ownReply = (await service.getChatStream().first).last.message;
      expect(ownReply, contains('Own request'));
      expect(ownReply, isNot(contains('Private other request')));
      expect(
        (await service.getMissingPersonsStream().first)
            .where((r) => r.personName == 'Context Person')
            .length,
        1,
      );
    },
  );
}
